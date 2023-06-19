#include "CLI11.hpp"

#include <crab_tests/run_test.hpp>
#include <memory>
#include <string>

using namespace std;

namespace crab_tests {
TestResult run_test(std::istream &is, const CrabIrBuilderOpts &irOpts,
                    const CrabIrAnalyzerOpts &anaOpts) {
  CrabIrBuilder crabIR(is, irOpts);
  CrabIrAnalyzer crabAnalyzer(crabIR, anaOpts);
  crabAnalyzer.analyze();

  if (anaOpts.print_invariants) {
    crabAnalyzer.write(crab::outs());
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
} // end namespace crab_tests

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

using namespace crab_tests;

int main(int argc, char **argv) {
  CLI::App app{"Run Crab analyzer"};
  //  string filename = "";
  //  app.add_option("-i,--input", filename, "Input file")->type_name("FILE");
  std::string filename;
  app.add_option("filename", filename, "CrabIR file.")
      ->required()
      ->type_name("FILE");

  string domain;
  app.add_option("-d,--domain", domain,
                 "Select abstract domain: int, zones, octagons, pk, pk-lite");

  unsigned widening_delay = 2;
  app.add_option("--widening-delay", widening_delay, "Number of fixpoint iterations until widening is applied (default 2)");

  unsigned thresholds_size = 0;
  app.add_option("--widening-thresholds", thresholds_size, "Size of widening thresholds (default 0)");
  
  unsigned descending_iters = 1;
  app.add_option("--descending-iters", descending_iters, "Number of descending (narrowing) iterations (default 1)");
  
  bool no_checker = false;
  app.add_flag("--no-checker", no_checker, "Disable assertion checking");

  bool print_invariants = false;
  app.add_flag("--print-invariants", print_invariants, "Print invariants");

  
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
  app.add_flag("--warnings", cwarning, "Print warning messages");

  CLI11_PARSE(app, argc, argv);

  crab_verbose = cverbose;
  crab_sanity = csanity;
  crab_loc = cloc;
  crab_stats = cstats;
  crab_warning = cwarning;

  // istream *is = nullptr;
  // if (filename != "") {
  //   auto ifs = new ifstream(filename);
  //   if (!ifs->is_open()){
  //     CRAB_ERROR("Cannot open file ", filename);
  //   }
  //   is = ifs;
  // } else {
  //   is = &std::cin;
  // }

  ifstream ifs(filename);
  if (!ifs.is_open()) {
    CRAB_ERROR("Cannot open file ", filename);
  }

  CrabIrBuilderOpts irOpts;
  CrabIrAnalyzerOpts anaOpts;
  bool foundDomain = false;
  for (auto dom : AbstractDomain::List) {
    if (dom.name() == domain) {
      anaOpts.domain = dom;
      foundDomain = true;
    }
  }

  if (!foundDomain) {
    CRAB_ERROR("cannot recognize domain ", domain);
  }
  
  anaOpts.run_checker = !no_checker;
  anaOpts.print_invariants = print_invariants;
  anaOpts.widening_delay = widening_delay;
  anaOpts.descending_iters = descending_iters;
  anaOpts.thresholds_size = thresholds_size;
  TestResult res = run_test(ifs, irOpts, anaOpts);

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
