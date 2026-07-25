#include <crabber/crabir.hpp>
#include <crabber/crabir_builder.hpp>
#include <crabber/parser.hpp>
#include <crab/cfg/cfg_to_dot.hpp>

namespace crabber {

using namespace cfg;
using namespace callgraph;

class CrabIrBuilderImpl {
  std::istream &m_is;
  CrabIrBuilderOpts m_opts;
  variable_factory_t m_vfac;
  std::vector<std::unique_ptr<cfg_t>> m_cfgs;
  // Maps each cfg's function name to its cfg, so hasCFG/getCFG are O(log n)
  // lookups instead of linear scans over m_cfgs. The pointers are owned by
  // m_cfgs and stay valid because cfgs are never removed after parsing.
  std::map<std::string, cfg_t *> m_cfg_map;
  std::unique_ptr<callgraph_t> m_callgraph;
  std::unique_ptr<std::map<unsigned, expected_result>> m_expected_results;

  void parse();

public:
  CrabIrBuilderImpl(std::istream &is, const CrabIrBuilderOpts &opts);
  CrabIrBuilderImpl(const CrabIrBuilderImpl &other) = delete;
  CrabIrBuilderImpl &operator=(const CrabIrBuilderImpl &other) = delete;
  ~CrabIrBuilderImpl();
  const CrabIrBuilderOpts &getOpts() const;
  bool hasCFG(const std::string &name) const;
  cfg_t &getCFG(const std::string &name);
  const cfg_t &getCFG(const std::string &name) const;
  const callgraph_t &getCallGraph() const;
  callgraph_t &getCallGraph();
  const std::map<unsigned, expected_result> &getExpectedResults() const;
};

CrabIrBuilder::CrabIrBuilder(std::istream &is, const CrabIrBuilderOpts &opts)
    : m_impl(std::make_unique<CrabIrBuilderImpl>(is, opts)) {}

CrabIrBuilder::~CrabIrBuilder() {}

const CrabIrBuilderOpts &CrabIrBuilder::getOpts() const {
  return m_impl->getOpts();
}

bool CrabIrBuilder::hasCFG(const std::string &name) const {
  return m_impl->hasCFG(name);
}

cfg_t &CrabIrBuilder::getCFG(const std::string &name) {
  return m_impl->getCFG(name);
}

const cfg_t &CrabIrBuilder::getCFG(const std::string &name) const {
  return m_impl->getCFG(name);
}

const callgraph_t &CrabIrBuilder::getCallGraph() const {
  return m_impl->getCallGraph();
}

callgraph_t &CrabIrBuilder::getCallGraph() { return m_impl->getCallGraph(); }

const std::map<unsigned, expected_result> &
CrabIrBuilder::getExpectedResults() const {
  return m_impl->getExpectedResults();
}

/// Actual implementation starts here

CrabIrBuilderImpl::CrabIrBuilderImpl(std::istream &is,
                                     const CrabIrBuilderOpts &opts)
    : m_is(is), m_opts(opts), m_callgraph(nullptr),
      m_expected_results(nullptr) {
  parse();
}

CrabIrBuilderImpl::~CrabIrBuilderImpl() {}
  
void CrabIrBuilderImpl::parse() {
  auto p = parse_crabir(m_is, m_vfac);
  m_cfgs = std::move(p.first);
  m_expected_results = std::move(p.second);
  std::vector<cfg_ref_t> cfg_refs;
  for (auto &cfg : m_cfgs) {
    if (m_opts.simplify_cfg) {
      cfg->simplify();
    }
    if (m_opts.cfg_to_dot) {
      cfg_to_dot(*cfg);
    }
    if (cfg->has_func_decl()) {
      m_cfg_map[cfg->get_func_decl().get_func_name()] = cfg.get();
    }
    cfg_refs.push_back(cfg_ref_t(*cfg));
  }
  m_callgraph = std::make_unique<callgraph_t>(cfg_refs);
}

const CrabIrBuilderOpts &CrabIrBuilderImpl::getOpts() const { return m_opts; }

bool CrabIrBuilderImpl::hasCFG(const std::string &name) const {
  return m_cfg_map.find(name) != m_cfg_map.end();
}

cfg_t &CrabIrBuilderImpl::getCFG(const std::string &name) {
  auto it = m_cfg_map.find(name);
  if (it == m_cfg_map.end()) {
    CRAB_ERROR("getCFG can be only called if hasCFG returns true");
  }
  return *(it->second);
}

const cfg_t &CrabIrBuilderImpl::getCFG(const std::string &name) const {
  auto it = m_cfg_map.find(name);
  if (it == m_cfg_map.end()) {
    CRAB_ERROR("getCFG can be only called if hasCFG returns true");
  }
  return *(it->second);
}

const callgraph_t &CrabIrBuilderImpl::getCallGraph() const {
  return *m_callgraph;
}

callgraph_t &CrabIrBuilderImpl::getCallGraph() { return *m_callgraph; }

const std::map<unsigned, expected_result> &
CrabIrBuilderImpl::getExpectedResults() const {
  return *m_expected_results;
}

void CrabIrBuilderOpts::write(crab::crab_os &o) const {
  o << "=== CrabIR builder options === \n";
  o << "Simplify cfg: " << simplify_cfg << "\n";
  o << "Print cfg to dot format: " << cfg_to_dot << "\n";
}

} // end namespace crabber
