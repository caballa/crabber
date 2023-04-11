#pragma once

#include <crab/support/os.hpp>
#include <crab_tests/crabir.hpp>
#include <crab_tests/parser.hpp>
#include <iostream>
#include <memory>

namespace crab_tests {

struct CrabIrBuilderOpts {
  CrabIrBuilderOpts() {}
  void write(crab::crab_os &o) const;
};

class CrabIrBuilderImpl;

class CrabIrBuilder {
  std::unique_ptr<CrabIrBuilderImpl> m_impl;

public:
  CrabIrBuilder(std::istream &is, const CrabIrBuilderOpts &opts);
  CrabIrBuilder(const CrabIrBuilder &other) = delete;
  CrabIrBuilder &operator==(const CrabIrBuilder &other) = delete;
  ~CrabIrBuilder();
  const CrabIrBuilderOpts &getOpts() const;
  bool hasCFG(const std::string &name) const;
  cfg::cfg_t &getCFG(const std::string &name);
  const cfg::cfg_t &getCFG(const std::string &name) const;
  const callgraph::callgraph_t &getCallGraph() const;
  callgraph::callgraph_t &getCallGraph();
  const std::map<unsigned, expected_result> &getExpectedResults() const;
};

} // end namespace crab_tests
