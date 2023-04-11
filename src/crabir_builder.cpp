#include <crab_tests/crabir.hpp>
#include <crab_tests/crabir_builder.hpp>
#include <crab_tests/parser.hpp>

namespace crab_tests {

using namespace cfg;
using namespace callgraph;

class CrabIrBuilderImpl {
  std::istream &m_is;
  CrabIrBuilderOpts m_opts;
  variable_factory_t m_vfac;
  std::vector<std::unique_ptr<cfg_t>> m_cfgs;
  std::unique_ptr<callgraph_t> m_callgraph;
  std::unique_ptr<std::map<unsigned, expected_result>> m_expected_results;

  void parse();

public:
  CrabIrBuilderImpl(std::istream &is, const CrabIrBuilderOpts &opts);
  CrabIrBuilderImpl(const CrabIrBuilderImpl &other) = delete;
  CrabIrBuilderImpl &operator==(const CrabIrBuilderImpl &other) = delete;
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
    : m_impl(new CrabIrBuilderImpl(is, opts)) {}

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
    cfg_refs.push_back(cfg_ref_t(*cfg));
  }
  m_callgraph = std::unique_ptr<callgraph_t>(new callgraph_t(cfg_refs));
}

const CrabIrBuilderOpts &CrabIrBuilderImpl::getOpts() const { return m_opts; }

bool CrabIrBuilderImpl::hasCFG(const std::string &name) const {
  for (unsigned i = 0, sz = m_cfgs.size(); i < sz; ++i) {
    if (m_cfgs[i]->has_func_decl()) {
      auto fdecl = m_cfgs[i]->get_func_decl();
      if (fdecl.get_func_name() == name) {
        return true;
      }
    }
  }
  return false;
}

// Each call to getCFG should be preceded by a call to hasCFG.
// Thus, it will iterate over m_cfgs twice. It's not efficient but simple/clean.
// Since we don't expect too many CFGs it should be okay.
cfg_t &CrabIrBuilderImpl::getCFG(const std::string &name) {
  for (unsigned i = 0, sz = m_cfgs.size(); i < sz; ++i) {
    if (m_cfgs[i]->has_func_decl()) {
      auto fdecl = m_cfgs[i]->get_func_decl();
      if (fdecl.get_func_name() == name) {
        return *(m_cfgs[i]);
      }
    }
  }
  CRAB_ERROR("getCFG can be only called if hasCFG returns true");
}

const cfg_t &CrabIrBuilderImpl::getCFG(const std::string &name) const {
  for (unsigned i = 0, sz = m_cfgs.size(); i < sz; ++i) {
    if (m_cfgs[i]->has_func_decl()) {
      auto fdecl = m_cfgs[i]->get_func_decl();
      if (fdecl.get_func_name() == name) {
        return *(m_cfgs[i]);
      }
    }
  }
  CRAB_ERROR("getCFG can be only called if hasCFG returns true");
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
  o << "No options\n";
}

} // end namespace crab_tests
