#pragma once

/**
 * JSON export of the analyzed program and of the invariants inferred for it.
 *
 * Two CLI options, mirroring the existing `--cfg-to-dot` /
 * `--print-invariants-to-dot` pair, but producing something to compute with
 * rather than something to look at:
 *
 *   --cfg-to-json              the CFG as Crab holds it in memory
 *   --print-invariants-to-json that same CFG, with every block additionally
 *                              carrying the invariant that holds on entry to it
 *
 * Each document stands alone: an invariant is written next to the statements it
 * describes, so nothing has to be matched up across files. `--cfg-to-json` is
 * the strict subset, for when the CFG is wanted without running an analysis.
 *
 * The serialization of Crab's own types lives in Crab (`crab/cfg/cfg_to_json.hpp`,
 * `crab/types/linear_constraints_to_json.hpp`); what is here is the surrounding
 * document: which CFGs, which blocks, and the header describing the run that
 * produced it.
 *
 * Two rules drive the design. Export the CFG Crab analyzes, never the source
 * text: Crab lowers conditionals into `edge-<src>-<dst>` blocks, adds a
 * synthetic `___exit`, and `--simplify-cfg` rewrites the graph further. And
 * never silently drop anything -- an unhandled statement kind raises
 * `CRAB_ERROR` rather than being skipped, since a document missing a statement
 * describes a different program than the one Crab analyzed.
 */

#include <crab/support/os.hpp>
#include <crabber/analyzer.hpp>
#include <crabber/crabir_builder.hpp>

#include <string>

namespace crabber {

/**
 * Write every CFG of the program, as Crab holds it after building and
 * simplification.
 */
void writeCFGsToJson(crab::crab_os &os, const CrabIrBuilder &crabIR,
                     const CrabIrBuilderOpts &irOpts);

/**
 * Write every CFG with, on each block, the invariant holding on entry to it,
 * plus the assertion outcomes recorded by the checker.
 *
 * `analyze()` must have been called on `analyzer` first.
 */
void writeInvariantsToJson(crab::crab_os &os, const CrabIrBuilder &crabIR,
                           const CrabIrAnalyzer &analyzer,
                           const CrabIrBuilderOpts &irOpts,
                           const CrabIrAnalyzerOpts &anaOpts);

} // end namespace crabber
