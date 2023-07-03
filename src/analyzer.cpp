#include "domains/domain_registry.hpp"
#include <crabber/analyzer.hpp>
#include <crabber/crabir_builder.hpp>
#include <crabber/domains.hpp>

#include <crab/analysis/inter/inter_params.hpp>
#include <crab/analysis/inter/top_down_inter_analyzer.hpp>
#include <crab/cfg/cfg_to_dot.hpp>
#include <crab/cg/cg.hpp>
#include <crab/cg/cg_bgl.hpp>
#include <crab/support/debug.hpp>
#include <crab/support/os.hpp>

#include <memory>
#include <unordered_set>

namespace crabber {

using namespace cfg;
using namespace callgraph;

class CrabIrAnalyzerImpl {
  using inter_params_t =
      ::crab::analyzer::inter_analyzer_parameters<callgraph_t>;
  using inter_analyzer_t =
      ::crab::analyzer::top_down_inter_analyzer<callgraph_t,
                                                crab_abstract_domain>;
  using checks_db_t = ::crab::checker::checks_db;

  CrabIrBuilder &m_crabIR;
  const CrabIrAnalyzerOpts &m_opts;
  std::unique_ptr<inter_analyzer_t> m_crabAnalyzer;
  checks_db_t m_checks;

public:
  CrabIrAnalyzerImpl(CrabIrBuilder &crabIR, const CrabIrAnalyzerOpts &opts)
      : m_crabIR(crabIR), m_opts(opts), m_crabAnalyzer(nullptr) {}

  const CrabIrAnalyzerOpts &getOpts() const { return m_opts; }
  void analyze();

  crab_abstract_domain getPreInvariant(const std::string &cfg_name,
                                       const label_t &block_name) const;

  crab_abstract_domain getPostInvariant(const std::string &cfg_name,
                                        const label_t &block_name) const;

  const crab::checker::checks_db &getChecks() const;

  void write(crab::crab_os &os) const;
  void write_to_dot() const;  
}; // end namespace CrabIrAnalyzerImpl

CrabIrAnalyzer::CrabIrAnalyzer(CrabIrBuilder &crabIR,
                               const CrabIrAnalyzerOpts &opts)
    : m_impl(new CrabIrAnalyzerImpl(crabIR, opts)) {}

CrabIrAnalyzer::~CrabIrAnalyzer() {}

const CrabIrAnalyzerOpts &CrabIrAnalyzer::getOpts() const {
  return m_impl->getOpts();
}

void CrabIrAnalyzer::analyze() { m_impl->analyze(); }

crab_abstract_domain
CrabIrAnalyzer::getPreInvariant(const std::string &cfg_name,
                                const std::string &block_name) const {
  return m_impl->getPreInvariant(cfg_name, block_name);
}

crab_abstract_domain
CrabIrAnalyzer::getPostInvariant(const std::string &cfg_name,
                                 const std::string &block_name) const {
  return m_impl->getPostInvariant(cfg_name, block_name);
}

const crab::checker::checks_db &CrabIrAnalyzer::getChecks() const {
  return m_impl->getChecks();
}

void CrabIrAnalyzer::write(crab::crab_os &os) const { m_impl->write(os); }
void CrabIrAnalyzer::write_to_dot() const { m_impl->write_to_dot(); }  

void CrabIrAnalyzerImpl::analyze() {
  if (DomainRegistry::count(m_opts.domain)) {
    inter_params_t params;
    params.run_checker = m_opts.run_checker;
    params.widening_delay = m_opts.widening_delay;
    params.descending_iters = m_opts.descending_iters;
    params.thresholds_size = m_opts.thresholds_size;
    crab_abstract_domain init = DomainRegistry::at(m_opts.domain);
    m_crabAnalyzer = std::unique_ptr<inter_analyzer_t>(
        new inter_analyzer_t(m_crabIR.getCallGraph(), init, params));
    m_crabAnalyzer->run(init);
    if (m_opts.run_checker) {
      m_checks += m_crabAnalyzer->get_all_checks();
    }
  } else {
    CRAB_ERROR("Abstract domain ", m_opts.domain.name(), " not registered");
  }
}

crab_abstract_domain
CrabIrAnalyzerImpl::getPreInvariant(const std::string &cfg_name,
                                    const label_t &block_name) const {
  if (m_crabIR.hasCFG(cfg_name)) {
    cfg_t &cfg = m_crabIR.getCFG(cfg_name);
    return m_crabAnalyzer->get_pre(cfg, block_name);
  }
  CRAB_ERROR("getPreInvariant cannot find CFG with name ", cfg_name);
}

crab_abstract_domain
CrabIrAnalyzerImpl::getPostInvariant(const std::string &cfg_name,
                                     const label_t &block_name) const {
  if (m_crabIR.hasCFG(cfg_name)) {
    cfg_t &cfg = m_crabIR.getCFG(cfg_name);
    return m_crabAnalyzer->get_post(cfg, block_name);
  }
  CRAB_ERROR("getPostInvariant cannot find CFG with name ", cfg_name);
}

const crab::checker::checks_db &CrabIrAnalyzerImpl::getChecks() const {
  return m_checks;
}

void CrabIrAnalyzerImpl::write(crab::crab_os &os) const {
  if (m_crabAnalyzer) {
    auto &cg = m_crabIR.getCallGraph();

    os << "=== CrabIR ===\n";
    for (auto n : boost::make_iterator_range(cg.nodes())) {
      cfg_ref_t cfg_ref = n.get_cfg();
      os << cfg_ref;
    }
    getOpts().write(os);
    unsigned num_checks = m_checks.get_total_safe() +
                          m_checks.get_total_warning() +
                          m_checks.get_total_error();

    os << "=== Verification results === \n";
    if (num_checks > 0) {
      m_checks.write(os);
    } else {
      os << "No checks\n";
    }
    for (auto n : boost::make_iterator_range(cg.nodes())) {
      cfg_ref_t cfg_ref = n.get_cfg();
      assert(cfg_ref.has_func_decl());
      os << "=== Invariants for " << cfg_ref.get_func_decl().get_func_name()
         << " === \n";
      auto entry = cfg_ref.entry();
      std::vector<label_t> stack;
      std::unordered_set<label_t> visited;
      stack.push_back(entry);
      visited.insert(entry);
      while (!stack.empty()) {
        auto curr = stack.back();
        stack.pop_back();
        auto invariants = m_crabAnalyzer->get_pre(cfg_ref.get(), curr);
        os << curr << ": " << invariants << "\n";
        for (auto succ : cfg_ref.next_nodes(curr)) {
          if (visited.insert(succ).second) {
            stack.push_back(succ);
          }
        }
      }
    }
  }
}


void CrabIrAnalyzerImpl::write_to_dot() const {
  if (m_crabAnalyzer) {
    auto &cg = m_crabIR.getCallGraph();
    for (auto n : boost::make_iterator_range(cg.nodes())) {
      cfg_ref_t cfg_ref = n.get_cfg();
      if (cfg_ref.has_func_decl()) {
	std::string cfg_name = cfg_ref.get_func_decl().get_func_name();
	crab::cfg::cfg_to_dot<cfg_ref_t, crab_abstract_domain>(cfg_ref,
		      [this, &cfg_name](const label_t &label) -> boost::optional<crab_abstract_domain> {
			   return getPreInvariant(cfg_name, label); 
		      },
		      [](const label_t &label) -> boost::optional<crab_abstract_domain> {
			   return boost::none;
		      },
		      m_checks);							       
      }
    }
  }
}
  
void CrabIrAnalyzerOpts::write(crab::crab_os &o) const {
  o << "=== Crab analyzer options === \n";
  o << "Abstract domain : " << domain.name() << "\n";
  o << "Widening delay  : " << widening_delay << "\n";
  o << "Descending iterations : " << descending_iters << "\n";
  o << "Number of widening thresholds : " << thresholds_size << "\n";  
  o << "Run checker     : " << run_checker << "\n";
  o << "Print invariants: " << print_invariants << "\n";
  o << "Print invariants and CFG to dot format: " << print_invariants_to_dot << "\n";  
}

} // end namespace crabber
