#include <crabber/lean_verify.hpp>

#include <crabber/crabber.hpp>

#include <boost/range/iterator_range.hpp>

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <vector>
#include <unistd.h>

#ifdef CRABBER_WITH_LEAN
#include <climits>
#include <sys/wait.h>
#endif

namespace crabber {

bool leanAvailable() {
#ifdef CRABBER_WITH_LEAN
  return true;
#else
  return false;
#endif
}

std::string leanProjectDir() {
#ifdef CRABBER_WITH_LEAN
  return CRABBER_LEAN_PROJECT;
#else
  return "";
#endif
}

std::string leanReproduceCommand(const std::string &leanFile) {
  return "cd " + leanProjectDir() + " && lake env lean " + leanFile;
}

std::string leanUnavailableReason() {
  return "this build was configured without Lean support; reconfigure with "
         "-DLAKE_EXECUTABLE=$(which lake)";
}

std::string describe(const LeanResult &r) {
  std::ostringstream os;
  switch (r.verdict) {
  case LeanVerdict::Proved:
    os << "proved            " << r.cfg_name
       << " : invariants sound, all assertions proved";
    break;
  case LeanVerdict::OutOfScope:
    os << "not attempted     " << r.cfg_name << " : " << r.detail;
    break;
  case LeanVerdict::Exhausted:
    os << "gave up           " << r.cfg_name
       << " : elaboration budget exhausted (raise --lean-heartbeats)";
    break;
  case LeanVerdict::Skipped:
    os << "not checked       " << r.cfg_name
       << " : called by another CFG; its invariants hold relative to its "
          "callers, which this check does not model";
    break;
  case LeanVerdict::Unproved:
    // Deliberately not "Crab is wrong". A failure here may only mean the proof
    // search was too weak, so it must not read as a claim about the analysis.
    os << "could not verify  " << r.cfg_name << " : " << r.detail;
    break;
  }
  return os.str();
}

#ifdef CRABBER_WITH_LEAN

namespace {

/** Quote for /bin/sh: wrap in '...', closing and reopening around any quote. */
std::string shellQuote(const std::string &s) {
  std::string out = "'";
  for (char c : s) {
    if (c == '\'') {
      out += "'\\''";
    } else {
      out += c;
    }
  }
  out += "'";
  return out;
}

/** Escape for a Lean string literal. */
std::string leanString(const std::string &s) {
  std::string out = "\"";
  for (char c : s) {
    if (c == '"' || c == '\\') {
      out += '\\';
    }
    out += c;
  }
  out += "\"";
  return out;
}

/**
 * Absolute form of `path`.
 *
 * Load-bearing rather than tidiness: Lean runs with its working directory set
 * to the Lean project, not to wherever crabber was invoked, so a relative path
 * in the generated file would resolve somewhere else or not at all.
 */
std::string absolutePath(const std::string &path) {
  char buf[PATH_MAX];
  if (realpath(path.c_str(), buf) != nullptr) {
    return std::string(buf);
  }
  return path;
}

std::string tempDir() {
  if (const char *t = getenv("TMPDIR")) {
    std::string d(t);
    if (!d.empty() && d.back() == '/') {
      d.pop_back();
    }
    return d;
  }
  return "/tmp";
}

/** The Lean file for one CFG. Everything program-specific is the two strings. */
void writeProofFile(const std::string &path, const std::string &jsonAbs,
                    const std::string &cfgName, unsigned heartbeats) {
  std::ofstream ofs(path);
  ofs << "import CrabberJson.Elab\n"
      << "set_option maxHeartbeats " << heartbeats << "\n"
      << "namespace CrabberJson.Generated\n"
      << "crab_program " << leanString(jsonAbs) << " cfg "
      << leanString(cfgName) << "\n"
      << "crab_verify\n"
      << "end CrabberJson.Generated\n";
}

struct RunOutput {
  int exit_code;
  std::string text;
};

/**
 * Run `lake env lean <file>` with the Lean project as working directory.
 *
 * `lake env` supplies LEAN_PATH for that project without adding the file to its
 * build graph, so nothing is written into the source tree and the file need not
 * live there. Lean writes diagnostics to stdout and lake may write its own
 * noise to stderr, so both are merged and read together.
 */
RunOutput runLean(const std::string &leanFile) {
  const std::string cmd = "cd " + shellQuote(CRABBER_LEAN_PROJECT) + " && " +
                          shellQuote(CRABBER_LAKE) + " env lean " +
                          shellQuote(leanFile) + " 2>&1";

  FILE *pipe = popen(cmd.c_str(), "r");
  if (!pipe) {
    CRAB_ERROR("could not execute ", CRABBER_LAKE);
  }
  std::string text;
  char buf[4096];
  while (std::fgets(buf, sizeof(buf), pipe) != nullptr) {
    text += buf;
  }
  const int status = pclose(pipe);
  const int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  return {code, text};
}

/** First line of Lean's output, trimmed of its file:line:col prefix. */
std::string firstMessage(const std::string &text) {
  std::istringstream is(text);
  std::string line;
  while (std::getline(is, line)) {
    if (line.empty()) {
      continue;
    }
    // Lean prefixes diagnostics with "<path>:<line>:<col>: error: ".
    const std::string marker = "error: ";
    const size_t at = line.find(marker);
    std::string msg = (at != std::string::npos) ? line.substr(at + marker.size())
                                                : line;
    // Lean's message ends in a colon introducing the detail below it. Whether
    // that detail is printed depends on there being a counterexample, so the
    // colon would otherwise dangle.
    if (!msg.empty() && msg.back() == ':') {
      msg.pop_back();
    }
    return msg;
  }
  return "no output";
}

LeanVerdict classify(const RunOutput &out) {
  if (out.exit_code == 0) {
    return LeanVerdict::Proved;
  }
  // The reader names the construct it refuses, which is what lets an
  // unsupported program be reported as out of scope rather than as a failure.
  //
  // This phrase is a contract with the Lean side: every refusal there that means
  // "this program is outside what the semantics models", as opposed to "the
  // document is malformed", spells it out verbatim. Grep for it in
  // lean/CrabberJson/Schema.lean before changing either end.
  if (out.text.find("outside the fragment this library models") !=
      std::string::npos) {
    return LeanVerdict::OutOfScope;
  }
  if (out.text.find("maximum number of heartbeats") != std::string::npos) {
    return LeanVerdict::Exhausted;
  }
  return LeanVerdict::Unproved;
}

/** Replace whole-word occurrences of `from` with `to`. */
std::string replaceWord(std::string s, const std::string &from,
                        const std::string &to) {
  const auto isWordChar = [](char c) {
    return std::isalnum(static_cast<unsigned char>(c)) || c == '_';
  };
  size_t at = 0;
  while ((at = s.find(from, at)) != std::string::npos) {
    const bool leftOk = (at == 0) || !isWordChar(s[at - 1]);
    const size_t after = at + from.size();
    const bool rightOk = (after >= s.size()) || !isWordChar(s[after]);
    if (leftOk && rightOk) {
      s.replace(at, from.size(), to);
      at += to.size();
    } else {
      at = after;
    }
  }
  return s;
}

std::string trim(const std::string &s) {
  size_t b = s.find_first_not_of(" \t");
  if (b == std::string::npos) {
    return "";
  }
  size_t e = s.find_last_not_of(" \t");
  return s.substr(b, e - b + 1);
}

/**
 * The counterexample `omega` reports, restated in the program's variables.
 *
 * Lean prints it against placeholder names with the bindings below:
 *
 *     a possible counterexample may satisfy the constraints
 *       101 <= a <= 200
 *     where
 *      a := sigma.ints "y"
 *
 * which is unreadable next to a CrabIR program. Substituting the bindings turns
 * that into `101 <= y <= 200` -- a statement about the program, which is what
 * makes it worth printing at all.
 *
 * Only the first block is taken. A failing CFG may produce several, and the rest
 * are available through --lean-show-output.
 */
std::string extractCounterexample(const std::string &text) {
  const std::string marker = "a possible counterexample may satisfy the constraints";
  const size_t at = text.find(marker);
  if (at == std::string::npos) {
    return "";
  }
  std::istringstream is(text.substr(at + marker.size()));
  std::string line;

  std::vector<std::string> constraints;
  while (std::getline(is, line)) {
    const std::string t = trim(line);
    if (t.empty()) {
      continue;
    }
    if (t == "where") {
      break;
    }
    // A new diagnostic means the block ended without any bindings.
    if (t.find(": error: ") != std::string::npos) {
      return "";
    }
    constraints.push_back(t);
  }

  // ` a := <expr> "x"` -- the quoted name is the program variable.
  while (std::getline(is, line)) {
    const std::string t = trim(line);
    if (t.empty() || t.find(": error: ") != std::string::npos) {
      break;
    }
    const size_t assign = t.find(":=");
    const size_t open = t.find('"', assign == std::string::npos ? 0 : assign);
    if (assign == std::string::npos || open == std::string::npos) {
      break;
    }
    const size_t close = t.find('"', open + 1);
    if (close == std::string::npos) {
      break;
    }
    const std::string placeholder = trim(t.substr(0, assign));
    const std::string variable = t.substr(open + 1, close - open - 1);
    for (auto &c : constraints) {
      c = replaceWord(c, placeholder, variable);
    }
  }

  std::string out;
  for (auto const &c : constraints) {
    if (!out.empty()) {
      out += ", ";
    }
    out += c;
  }
  return out;
}

/**
 * The construct the reader refused, pulled out of its (deliberately long)
 * explanation so the report stays one line per CFG.
 */
std::string refusedConstruct(const std::string &text) {
  const std::string marker = "statement kind '";
  const size_t at = text.find(marker);
  if (at == std::string::npos) {
    return "uses a construct the Lean semantics does not model";
  }
  const size_t start = at + marker.size();
  const size_t end = text.find('\'', start);
  if (end == std::string::npos) {
    return "uses a construct the Lean semantics does not model";
  }
  return "uses " + text.substr(start, end - start) +
         ", which the Lean semantics does not model";
}

} // namespace

std::vector<LeanResult> verifyWithLean(const std::string &jsonPath,
                                       const CrabIrBuilder &crabIR,
                                       const LeanVerifyOpts &opts) {
  std::vector<LeanResult> results;
  const std::string jsonAbs = absolutePath(jsonPath);
  const std::string dir = tempDir();
  const long pid = static_cast<long>(getpid());

  auto &cg = const_cast<CrabIrBuilder &>(crabIR).getCallGraph();

  // Only the roots of the call graph -- the CFGs nothing calls.
  //
  // A callee's invariants are *conditional on its callers*: Crab's top-down
  // inter-procedural analysis derives them from the call sites, so `inc`'s entry
  // invariant may be `a >= 5` purely because `main` happens to call it that way.
  // The theorem Lean proves quantifies over every initial state, which is a
  // strictly stronger claim than Crab made, so a callee checked in isolation
  // fails for a reason that says nothing about the analysis. Verifying roots
  // keeps the question asked the same as the question answered.
  auto entries = cg.entries();
  if (entries.empty()) {
    // Every CFG has a caller, so the call graph is one or more cycles with no
    // way in. Crab's own analyzer treats all nodes as entries in that case;
    // matching it keeps the two sides describing the same runs.
    auto p = cg.nodes();
    entries.insert(entries.end(), p.first, p.second);
  }

  unsigned index = 0;
  for (auto n : entries) {
    auto cfg_ref = n.get_cfg();
    if (!cfg_ref.has_func_decl()) {
      continue;
    }
    const std::string name = cfg_ref.get_func_decl().get_func_name();

    std::ostringstream fileName;
    fileName << dir << "/crabber-lean-" << pid << "-" << index++ << ".lean";
    const std::string leanFile = fileName.str();

    writeProofFile(leanFile, jsonAbs, name, opts.heartbeats);
    const RunOutput out = runLean(leanFile);

    LeanResult r;
    r.cfg_name = name;
    r.verdict = classify(out);
    r.output = out.text;
    if (r.verdict == LeanVerdict::OutOfScope) {
      r.detail = refusedConstruct(out.text);
    } else if (r.verdict != LeanVerdict::Proved) {
      r.detail = firstMessage(out.text);
      r.counterexample = extractCounterexample(out.text);
    }

    // Reporting belongs to the caller, which knows about the JSON as well; all
    // this decides is whether the file survives.
    if (opts.keep_temp) {
      r.lean_file = leanFile;
    } else {
      std::remove(leanFile.c_str());
    }
    results.push_back(r);
  }

  // Anything the analysis covered but this check did not, named so the gap is
  // visible in the report rather than inferred from an absence.
  for (auto n : boost::make_iterator_range(cg.nodes())) {
    auto cfg_ref = n.get_cfg();
    if (!cfg_ref.has_func_decl()) {
      continue;
    }
    const std::string name = cfg_ref.get_func_decl().get_func_name();
    bool checked = false;
    for (auto const &r : results) {
      if (r.cfg_name == name) {
        checked = true;
        break;
      }
    }
    if (!checked) {
      LeanResult r;
      r.cfg_name = name;
      r.verdict = LeanVerdict::Skipped;
      results.push_back(r);
    }
  }
  return results;
}

#else // !CRABBER_WITH_LEAN

std::vector<LeanResult> verifyWithLean(const std::string &, const CrabIrBuilder &,
                                       const LeanVerifyOpts &) {
  return {};
}

#endif

} // namespace crabber
