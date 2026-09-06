#include <crabber/json_export.hpp>

#include <crab/cfg/cfg_to_json.hpp>
#include <crab/support/json.hpp>
#include <crab/types/linear_constraints_to_json.hpp>

#include <boost/range/iterator_range.hpp>

namespace crabber {

using namespace cfg;
using namespace callgraph;

/**
 * Version of the document shape. Bump on any incompatible change; a consumer
 * should refuse a version it does not know.
 */
static const unsigned JSON_SCHEMA_VERSION = 1;

/** The header shared by both documents. */
static void writeHeader(crab::json::writer &w, const char *kind,
                        const CrabIrBuilderOpts &irOpts) {
  w.kv_unsigned("schema", JSON_SCHEMA_VERSION);
  w.kv_string("kind", kind);
  w.key("source");
  w.begin_object(true /*compact*/);
  if (irOpts.source_name.empty()) {
    w.kv_null("name");
  } else {
    w.kv_string("name", irOpts.source_name);
  }
  w.end_object();
  w.key("options");
  w.begin_object(true /*compact*/);
  w.kv_bool("simplify_cfg", irOpts.simplify_cfg);
  w.end_object();
}

void writeCFGsToJson(crab::crab_os &os, const CrabIrBuilder &crabIR,
                     const CrabIrBuilderOpts &irOpts) {
  crab::json::writer w(os);
  w.begin_object();
  writeHeader(w, "cfg", irOpts);
  w.key("cfgs");
  w.begin_array();
  auto &cg = const_cast<CrabIrBuilder &>(crabIR).getCallGraph();
  for (auto n : boost::make_iterator_range(cg.nodes())) {
    cfg_ref_t cfg_ref = n.get_cfg();
    crab::cfg::cfg_to_json(cfg_ref, w);
  }
  w.end_array();
  w.end_object();
  w.finish();
}

static const char *checkResultName(crab::checker::check_kind k) {
  switch (k) {
  case crab::checker::check_kind::CRAB_SAFE:
    return "safe";
  case crab::checker::check_kind::CRAB_ERR:
    return "error";
  case crab::checker::check_kind::CRAB_WARN:
    return "warning";
  case crab::checker::check_kind::CRAB_UNREACH:
    return "unreachable";
  }
  CRAB_ERROR("json_export: unexpected check kind");
}

void writeInvariantsToJson(crab::crab_os &os, const CrabIrBuilder &crabIR,
                           const CrabIrAnalyzer &analyzer,
                           const CrabIrBuilderOpts &irOpts,
                           const CrabIrAnalyzerOpts &anaOpts) {
  crab::json::writer w(os);
  w.begin_object();
  writeHeader(w, "invariants", irOpts);

  w.key("analysis");
  w.begin_object();
  w.kv_string("domain", anaOpts.domain.name());
  w.kv_unsigned("widening_delay", anaOpts.widening_delay);
  w.kv_unsigned("descending_iters", anaOpts.descending_iters);
  w.kv_unsigned("thresholds", anaOpts.thresholds_size);
  w.kv_bool("checker", anaOpts.run_checker);
  w.end_object();

  // The whole CFG, with each block carrying the invariant that holds on entry
  // to it, written by the same code that serves --cfg-to-json: one copy of the
  // block shape means the two documents cannot drift.
  w.key("cfgs");
  w.begin_array();
  auto &cg = const_cast<CrabIrBuilder &>(crabIR).getCallGraph();
  for (auto n : boost::make_iterator_range(cg.nodes())) {
    cfg_ref_t cfg_ref = n.get_cfg();
    if (!cfg_ref.has_func_decl()) {
      CRAB_ERROR("json_export: CFG without a function declaration");
    }
    std::string cfg_name = cfg_ref.get_func_decl().get_func_name();
    // cfg_to_json emits every block, not only those reachable from the entry,
    // so an unreachable block is reported as bottom rather than going missing.
    crab::cfg::cfg_to_json(
        cfg_ref, w,
        [&analyzer, &cfg_name](const label_t &label, crab::json::writer &bw) {
          bw.key("invariant");
          crab_abstract_domain inv = analyzer.getPreInvariant(cfg_name, label);
          crab::json::write(bw, inv.to_disjunctive_linear_constraint_system());
        });
  }
  w.end_array();

  // Assertion outcomes, carrying the same debug info as the "loc" of the
  // assert statements above, whose "id" identifies the assertion.
  w.key("checks");
  w.begin_array();
  for (auto const &kv : analyzer.getChecks().get_all_checks()) {
    auto const &dbg = kv.first;
    for (auto const &result : kv.second) {
      w.begin_object(true /*compact*/);
      w.kv_string("file", dbg.get_file());
      w.kv_int("line", dbg.get_line());
      w.kv_int("col", dbg.get_column());
      w.kv_int("id", dbg.get_id());
      w.kv_string("result", checkResultName(result));
      w.end_object();
    }
  }
  w.end_array();

  w.end_object();
  w.finish();
}

} // end namespace crabber
