#pragma once

#include <crab_tests/analyzer.hpp>
#include <crab_tests/crabir_builder.hpp>
#include <istream>
#include <string>

namespace crab_tests {
struct TestResult {
  unsigned expected_ok;
  unsigned unexpected_ok;
  unsigned expected_failure;
  unsigned unexpected_failure;
  std::string msg;
};

TestResult run_test(std::istream &is, const CrabIrBuilderOpts &irOpts,
                    const CrabIrAnalyzerOpts &anaOpts);
} // end namespace crab_tests
