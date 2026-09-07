#include "CLI11.hpp"

#include <crabber/crabber.hpp>
#include <crabber/json_export.hpp>
#include <crabber/lean_verify.hpp>
#include <crab/domains/abstract_domain_params.hpp>
#include <fstream>
#include <cstdio>
#include <memory>
#include <sstream>
#include <string>
#include <unistd.h>

using namespace std;

namespace crabber {
TestResult run_program(std::istream &is, const CrabIrBuilderOpts &irOpts,
                    const CrabIrAnalyzerOpts &anaOpts,
                    const LeanVerifyOpts &leanOpts) {
  CrabIrBuilder crabIR(is, irOpts);
  CrabIrAnalyzer crabAnalyzer(crabIR, anaOpts);
  crabAnalyzer.analyze();

  if (anaOpts.print_invariants) {
    crabAnalyzer.write(crab::outs());
  }
  if (anaOpts.print_invariants_to_dot) {
    crabAnalyzer.write_to_dot();
  }
  auto with_output = [](const std::string &path, auto &&write) {
    std::ofstream ofs(path);
    if (!ofs.is_open()) {
      CRAB_ERROR("Cannot open file ", path, " for writing");
    }
    crab::crab_os os(&ofs);
    write(os);
  };
  if (!irOpts.cfg_to_json.empty()) {
    with_output(irOpts.cfg_to_json, [&](crab::crab_os &os) {
      writeCFGsToJson(os, crabIR, irOpts);
    });
  }
  if (!anaOpts.print_invariants_to_json.empty()) {
    with_output(anaOpts.print_invariants_to_json, [&](crab::crab_os &os) {
      writeInvariantsToJson(os, crabIR, crabAnalyzer, irOpts, anaOpts);
    });
  }

  // The document just written is the whole interface to the Lean side: it is
  // read back by Lean, not passed along in memory, so what gets proved is
  // exactly what was exported.
  if (leanOpts.enabled) {
    crab::outs() << "\n### LEAN VERIFICATION ###\n";
    // Announced before the results, since every CFG below was checked against
    // this one document.
    if (leanOpts.keep_temp) {
      crab::outs() << "  invariants : " << anaOpts.print_invariants_to_json
                   << "\n";
    }
    auto results =
        verifyWithLean(anaOpts.print_invariants_to_json, crabIR, leanOpts);
    for (auto const &r : results) {
      crab::outs() << describe(r) << "\n";
      // Where the arithmetic ran out, in the program's own variables. It is an
      // assignment the proof could not rule out, not necessarily a reachable
      // one -- but it is the fastest way to see what fact is missing.
      if (!r.counterexample.empty()) {
        crab::outs() << "  cannot rule out : " << r.counterexample << "\n";
      }
      // Everything needed to take a failure apart by hand: the file Lean was
      // given, and the command that runs it again.
      if (!r.lean_file.empty()) {
        crab::outs() << "  lean file  : " << r.lean_file << "\n"
                     << "  reproduce  : " << leanReproduceCommand(r.lean_file)
                     << "\n";
      }
      if (leanOpts.show_output && r.verdict != LeanVerdict::Proved &&
          !r.output.empty()) {
        crab::outs() << r.output;
      }
    }
    // Said once, rather than implied by each line: a negative result here is
    // about this proof attempt, never about the analysis.
    crab::outs() << "(\"could not verify\" means Lean found no proof; it is not "
                    "a claim that the invariants are wrong)\n";
  }

  unsigned expected_ok = 0;
  unsigned unexpected_ok = 0;
  unsigned expected_failure = 0;
  unsigned unexpected_failure = 0;
  crab::crab_string_os msg;
  auto checks = crabAnalyzer.getChecks().get_all_checks();
  for (auto &kv : checks) {
    auto dbg_info = kv.first;
    auto results = kv.second;
    if (results.size() != 1) {
      CRAB_ERROR("Expected one result per assertion");
    }
    auto result = results[0];
    auto it = crabIR.getExpectedResults().find(dbg_info.get_id());
    if (it != crabIR.getExpectedResults().end()) {
      expected_result exp_res = it->second;
      switch (result) {
      case crab::checker::check_kind::CRAB_SAFE:
      case crab::checker::check_kind::CRAB_UNREACH:
        if (exp_res == expected_result::OK) {
          expected_ok++;
          msg << dbg_info << " expected OK\n";
        } else {
          unexpected_ok++;
          msg << dbg_info << " unexpected OK\n";
        }
        break;
      case crab::checker::check_kind::CRAB_ERR:
      case crab::checker::check_kind::CRAB_WARN:
        if (exp_res == expected_result::FAILED) {
          expected_failure++;
          msg << dbg_info << " expected failure\n";
        } else {
          unexpected_failure++;
          msg << dbg_info << " unexpected failure\n";
        }
      }
    }
  }
  return TestResult{expected_ok, unexpected_ok, expected_failure,
                    unexpected_failure, msg.str()};
}
} // end namespace crabber

/* Debugging/Logging/Sanity Checks options */

struct LogOpt {
  void operator=(const std::string &tag) const { crab::CrabEnableLog(tag); }
};
LogOpt crab_loc;

struct VerboseOpt {
  void operator=(unsigned level) const { crab::CrabEnableVerbosity(level); }
};
VerboseOpt crab_verbose;

struct WarningOpt {
  void operator=(bool val) const { crab::CrabEnableWarningMsg(val); }
};
WarningOpt crab_warning;

struct SanityChecksOpt {
  void operator=(bool val) const { crab::CrabEnableSanityChecks(val); }
};
SanityChecksOpt crab_sanity;

struct StatsOpt {
  void operator=(bool val) const { crab::CrabEnableStats(val); }
};
StatsOpt crab_stats;

using namespace crabber;

int main(int argc, char **argv) {
  CLI::App app{"Run Crab analyzer on CrabIR programs"};
  std::string filename;
  app.add_option("filename", filename, "CrabIR file.")
      ->required()
      ->type_name("FILE");

  string domain = "int";
  auto domain_opt = app.add_option("-d,--domain", domain,
                 "Select abstract domain (default int; see --show-domains)");

  bool print_domains = false;
  app.add_flag("--show-domains", print_domains, "Show all the available abstract domains");
  
  unsigned widening_delay = 2;
  app.add_option("--widening-delay", widening_delay, "Number of fixpoint iterations until widening is applied (default 2)");

  unsigned thresholds_size = 0;
  app.add_option("--widening-thresholds", thresholds_size, "Size of widening thresholds (default 0)");
  
  unsigned descending_iters = 1;
  app.add_option("-n,--descending-iters", descending_iters, "Number of descending (narrowing) iterations (default 1)");

  string tvpi_coefficients = "";
  app.add_option("--coefficients", tvpi_coefficients, "Non-unit coefficients for tvpi-dbm: each separated by comma");
  
  bool no_checker = false;
  app.add_flag("--no-checker", no_checker, "Disable assertion checking");

  bool print_invariants = false;
  app.add_flag("--print-invariants", print_invariants, "Print invariants");

  bool print_invariants_to_dot = false;
  app.add_flag("-p,--print-invariants-to-dot", print_invariants_to_dot, "Print invariants and analyzed CFG to dot format");
  
  bool simplify = false;
  app.add_flag("-s,--simplify-cfg", simplify, "Simplify CFG");

  bool cfg_to_dot = false;
  app.add_flag("--cfg-to-dot", cfg_to_dot, "Print CFG to dot format");

  string cfg_to_json = "";
  app.add_option("--cfg-to-json", cfg_to_json,
                 "Write the analyzed CFG to FILE in JSON format")
      ->type_name("FILE");

  string print_invariants_to_json = "";
  app.add_option("--print-invariants-to-json", print_invariants_to_json,
                 "Write invariants and analyzed CFG to FILE in JSON format")
      ->type_name("FILE");

  // Registered whether or not this build can act on it, so that a user on an
  // unconfigured build is told a build flag exists instead of being given
  // CLI11's bare "unknown option".
  bool verify_with_lean = false;
  app.add_flag("--verify-with-lean", verify_with_lean,
               "After the analysis, ask Lean to prove the inferred invariants "
               "sound (implies --print-invariants-to-json)");

  unsigned lean_heartbeats = 400000;
  app.add_option("--lean-heartbeats", lean_heartbeats,
                 "Elaboration budget per CFG for --verify-with-lean "
                 "(default 400000)");

  bool lean_keep_temp = false;
  app.add_flag("--lean-keep-temp", lean_keep_temp,
               "Keep the exported JSON and the generated Lean files, and print "
               "where they are and how to re-run them");

  bool lean_show_output = false;
  app.add_flag("--lean-show-output", lean_show_output,
               "Print Lean's full output for a CFG that was not proved");
  
  /// Options for debugging/logging in crab

  unsigned cverbose = 0;
  app.add_option("-v,--verbose", cverbose, "Crab verbose");

  bool csanity = false;
  app.add_flag("--sanity", csanity, "Sanity checks");

  string cloc = "";
  app.add_option("--log", cloc, "Logger");

  bool cstats = false;
  app.add_flag("--stats", cstats, "Print stats");

  bool cwarning = false;
  app.add_flag("-w,--warnings", cwarning, "Print warning messages");

  CLI11_PARSE(app, argc, argv);

  crab_verbose = cverbose;
  crab_sanity = csanity;
  crab_loc = cloc;
  crab_stats = cstats;
  crab_warning = cwarning;

  if (print_domains) {
    cout << "Available domains: \n";
    for (auto const &d: AbstractDomain::List) {
      cout << "\t" << d.name() << ": " <<  d.desc() << "\n";
    }
    return 0;
  }
  
  ifstream ifs(filename);
  if (!ifs.is_open()) {
    CRAB_ERROR("Cannot open file ", filename);
  }

  LeanVerifyOpts leanOpts;
  leanOpts.enabled = verify_with_lean;
  leanOpts.heartbeats = lean_heartbeats;
  leanOpts.keep_temp = lean_keep_temp;
  leanOpts.show_output = lean_show_output;

  // Written here rather than left to a temporary that outlives this scope: the
  // path has to stay valid until run_program has both exported to it and had
  // Lean read it back.
  string lean_scratch_json;
  if (leanOpts.enabled) {
    if (!leanAvailable()) {
      CRAB_ERROR("--verify-with-lean is not available: ",
                 leanUnavailableReason());
    }
    // The check reads whatever document the export produced, so if the user did
    // not ask for one, produce one for it alone.
    if (print_invariants_to_json.empty()) {
      const char *tmp = getenv("TMPDIR");
      string dir = tmp ? string(tmp) : string("/tmp");
      if (!dir.empty() && dir.back() == '/') {
        dir.pop_back();
      }
      lean_scratch_json =
          dir + "/crabber-" + std::to_string(getpid()) + ".json";
      print_invariants_to_json = lean_scratch_json;
    }
  }

  CrabIrBuilderOpts irOpts;
  irOpts.simplify_cfg = simplify;
  irOpts.cfg_to_dot = cfg_to_dot;
  irOpts.cfg_to_json = cfg_to_json;
  // Recorded in the JSON header, as provenance for the document.
  if (!cfg_to_json.empty() || !print_invariants_to_json.empty()) {
    irOpts.source_name = filename;
  }
  
  if (domain_opt->count() == 0) {
    cout << "No domain selected with -d/--domain; using default domain '"
         << domain << "'.\n";
  }

  CrabIrAnalyzerOpts anaOpts;
  bool foundDomain = false;
  for (auto dom : AbstractDomain::List) {
    if (dom.name() == domain) {
      anaOpts.domain = dom;
      foundDomain = true;
    }
  }

  if (!foundDomain) {
    string names;
    for (auto const &d : AbstractDomain::List) {
      if (!names.empty()) {
        names += ", ";
      }
      names += d.name();
    }
    CRAB_ERROR("cannot recognize domain '", domain,
               "'. Available domains: ", names,
               " (use --show-domains for descriptions)");
  }

  if (tvpi_coefficients != "") {
    stringstream ss(tvpi_coefficients);
    string str;
    while (getline(ss, str, ',')) {
      crab::domains::crab_domain_params_man::get().coefficients().push_back(stoul(str));
    }
  }
  
  anaOpts.run_checker = !no_checker;
  anaOpts.print_invariants = print_invariants;
  anaOpts.print_invariants_to_dot = print_invariants_to_dot;
  anaOpts.print_invariants_to_json = print_invariants_to_json;
  anaOpts.widening_delay = widening_delay;
  anaOpts.descending_iters = descending_iters;
  anaOpts.thresholds_size = thresholds_size;
  TestResult res = run_program(ifs, irOpts, anaOpts, leanOpts);

  // Only if we made it ourselves; a path the user asked for is theirs to keep,
  // and --lean-keep-temp keeps ours too so the failure can be reproduced.
  if (!lean_scratch_json.empty() && !leanOpts.keep_temp) {
    std::remove(lean_scratch_json.c_str());
  }

  cout << "\n### TESTS RESULTS ###\n";
  cout << "Expected OK         : " << res.expected_ok << "\n";
  cout << "Unexpected OK       : " << res.unexpected_ok << "\n";
  cout << "Expected failures   : " << res.expected_failure << "\n";
  cout << "Unexpected failures : " << res.unexpected_failure << "\n";

  if (cverbose > 0) {
    cout << "\n" << res.msg << "\n";
  }

  if (res.unexpected_failure == 0 && res.unexpected_ok == 0) {
    return 0;
  } else {
    return 1;
  }
}
