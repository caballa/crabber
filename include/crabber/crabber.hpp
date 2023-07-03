#pragma once

#include <crabber/analyzer.hpp>
#include <crabber/crabir_builder.hpp>
#include <istream>
#include <string>

namespace crabber {
struct TestResult {
  unsigned expected_ok;
  unsigned unexpected_ok;
  unsigned expected_failure;
  unsigned unexpected_failure;
  std::string msg;
};

TestResult run_program(std::istream &is, const CrabIrBuilderOpts &irOpts,
                       const CrabIrAnalyzerOpts &anaOpts);
} // end namespace crabber
