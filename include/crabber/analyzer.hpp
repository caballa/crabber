#pragma once

#include <crab/checkers/base_property.hpp> // checks_db
#include <crab/support/os.hpp>
#include <crabber/crabir.hpp>
#include <crabber/crabir_builder.hpp>
#include <crabber/domains.hpp>
#include <memory>

namespace crabber {

struct CrabIrAnalyzerOpts {
  AbstractDomain::Type domain;
  unsigned widening_delay;
  unsigned descending_iters;
  unsigned thresholds_size;
  bool run_checker;
  bool print_invariants;
  bool print_invariants_to_dot;
  /// Path to write the invariants in JSON format ("" disables it, "-" is
  /// stdout).
  std::string print_invariants_to_json;
  /// Rewrite inferred invariants into an equivalent, more readable form before
  /// reporting them (see crabber/normalize.hpp). Ignored for the domains that
  /// cannot produce a constraint system.
  bool normalize;

  CrabIrAnalyzerOpts()
      : domain(AbstractDomain::ZONES),
	widening_delay(2), descending_iters(1), thresholds_size(0),
	run_checker(true),
	print_invariants(false),
	print_invariants_to_dot(false),
	normalize(true){}
  
  void write(crab::crab_os &o) const;
};

class CrabIrAnalyzerImpl;

class CrabIrAnalyzer {
  std::unique_ptr<CrabIrAnalyzerImpl> m_impl;

public:
  CrabIrAnalyzer(CrabIrBuilder &crabIR, const CrabIrAnalyzerOpts &opts);
  CrabIrAnalyzer(const CrabIrAnalyzer &other) = delete;
  CrabIrAnalyzer &operator=(const CrabIrAnalyzer &other) = delete;
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

} // end namespace crabber
