#pragma once

#include <crab/checkers/base_property.hpp> // checks_db
#include <crab/support/os.hpp>
#include <crab_tests/crabir.hpp>
#include <crab_tests/crabir_builder.hpp>
#include <crab_tests/domains.hpp>
#include <memory>

namespace crab_tests {

struct CrabIrAnalyzerOpts {
  AbstractDomain::Type domain;
  unsigned widening_delay;
  unsigned descending_iters;
  unsigned thresholds_size;
  bool run_checker;
  bool print_invariants;
  bool print_invariants_to_dot;

  CrabIrAnalyzerOpts()
      : domain(AbstractDomain::ZONES),
	widening_delay(2), descending_iters(1), thresholds_size(0),
	run_checker(true),
	print_invariants(false),
	print_invariants_to_dot(false){}
  
  void write(crab::crab_os &o) const;
};

class CrabIrAnalyzerImpl;

class CrabIrAnalyzer {
  std::unique_ptr<CrabIrAnalyzerImpl> m_impl;

public:
  CrabIrAnalyzer(CrabIrBuilder &crabIR, const CrabIrAnalyzerOpts &opts);
  CrabIrAnalyzer(const CrabIrAnalyzer &other) = delete;
  CrabIrAnalyzer &operator==(const CrabIrAnalyzer &other) = delete;
  ~CrabIrAnalyzer();
  const CrabIrAnalyzerOpts &getOpts() const;
  void analyze();
  crab_abstract_domain getPreInvariant(const std::string &cfg_name,
                                       const cfg::label_t &block_name) const;
  crab_abstract_domain getPostInvariant(const std::string &cfg_name,
                                        const cfg::label_t &block_name) const;
  const crab::checker::checks_db &getChecks() const;
  void write(crab::crab_os &o) const;
  void write_to_dot() const;  
};

} // end namespace crab_tests
