#pragma once
/**
 * Ask the Lean development to prove the exported invariants sound.
 *
 * `--print-invariants-to-json` writes a document holding the analyzed CFG and,
 * for every block, the invariant Crab inferred for it. That document is the
 * only thing that crosses between the two sides: this code writes it, Lean
 * reads it, and nothing about the program travels any other way.
 *
 * What happens per CFG is that a two-line Lean file is written,
 *
 *     crab_program "<absolute path to the document>" cfg "<name>"
 *     crab_verify
 *
 * and checked with `lake env lean`. The first line reads the document while the
 * file is being elaborated and installs the program and the invariants as Lean
 * data; the second generates the proof obligations and discharges them. Success
 * means Lean's kernel accepted a proof that every reachable state satisfies the
 * invariant Crab printed for its block, and that no assertion can fail.
 *
 * What this does *not* do is make crabber's report trustworthy on its own.
 * Printing "proved" only says Lean was run and agreed; a bug here could print
 * it without running anything. The claim rests on the Lean development, and
 * anyone who wants to rely on it should run `lake build` themselves.
 *
 * Nor is a failure evidence that Crab is wrong. Lean's arithmetic may simply be
 * too weak, the program may use constructs the Lean semantics does not model,
 * or an assertion may be one Crab itself could not prove. The verdicts below
 * keep those apart, and the wording of each is chosen so that a negative result
 * never reads as a claim about Crab.
 *
 * Available only when the build was configured with a path to `lake` (see
 * `LAKE_EXECUTABLE` in CMakeLists.txt). Without it `leanAvailable()` is false
 * and the option reports how to enable it.
 */

#include <string>
#include <vector>

namespace crabber {

class CrabIrBuilder;

struct LeanVerifyOpts {
  /** Run the check after the analysis. */
  bool enabled = false;
  /**
   * Elaboration budget, as Lean heartbeats rather than seconds.
   *
   * A wall-clock timeout would make the outcome depend on how loaded the
   * machine is, so the same program could verify on one run and "fail" on the
   * next. Heartbeats are deterministic, and exhausting them is reported by Lean
   * as an ordinary diagnostic, which is why `Exhausted` can be told apart from
   * a proof that genuinely did not go through.
   */
  unsigned heartbeats = 400000;
  /**
   * Keep the exported JSON and the generated Lean file, and report where they
   * are.
   *
   * This is the whole debugging story for a CFG that does not go through. The
   * two files are exactly what Lean saw, so re-running the printed command
   * reproduces the failure with nothing in between -- and the Lean file can
   * then be edited, its tactics taken apart, and the failing goal inspected in
   * an editor.
   */
  bool keep_temp = false;
  /** Print Lean's complete output for a CFG that was not proved. */
  bool show_output = false;
};

enum class LeanVerdict {
  /** Lean proved the invariants sound and every assertion unfailable. */
  Proved,
  /** The program uses a construct the Lean semantics does not model. */
  OutOfScope,
  /** Lean did not find a proof. Not a claim that Crab is wrong. */
  Unproved,
  /** The elaboration budget ran out before Lean finished. */
  Exhausted,
  /**
   * Not a root of the call graph, so not checked.
   *
   * Reported rather than passed over in silence: a CFG present in the file and
   * absent from the results would otherwise look like an oversight.
   */
  Skipped,
};

struct LeanResult {
  std::string cfg_name;
  LeanVerdict verdict;
  /** Lean's own first line of output, kept for the unproved cases. */
  std::string detail;
  /** Everything Lean printed. Empty when it printed nothing. */
  std::string output;
  /**
   * The counterexample the arithmetic decision procedure reported, if it did,
   * rewritten in terms of the program's own variables.
   *
   * Not a counterexample to the invariant: it describes an assignment the proof
   * search could not rule out, which may well be unreachable. It is a pointer to
   * where the reasoning ran out, and usually the fastest way to see whether the
   * gap is a missing fact or a genuinely weak invariant.
   */
  std::string counterexample;
  /** Where the generated Lean file was left, when it was kept. */
  std::string lean_file;
};

/** Whether this build can call Lean at all. */
bool leanAvailable();

/** The Lean development this build was configured against. */
std::string leanProjectDir();

/** The command that re-runs one kept Lean file by hand. */
std::string leanReproduceCommand(const std::string &leanFile);

/** Why not, when it cannot -- suitable for showing to a user. */
std::string leanUnavailableReason();

/**
 * Check every CFG in `jsonPath`, which must be a document written by
 * `--print-invariants-to-json`. One result per CFG, in the order the call graph
 * gives them.
 */
std::vector<LeanResult> verifyWithLean(const std::string &jsonPath,
                                       const CrabIrBuilder &crabIR,
                                       const LeanVerifyOpts &opts);

/** One line describing a result, for the report. */
std::string describe(const LeanResult &r);

} // namespace crabber
