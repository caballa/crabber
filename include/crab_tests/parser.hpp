#pragma once

#include <crab_tests/crabir.hpp>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Utilities for parsing that can be used by other projects

namespace crab_tests {
enum class expected_result { OK, FAILED };
  
cfg::linear_expression_t parse_linear_expression(const std::string &exp,
                                                 cfg::variable_factory_t &vfac,
                                                 crab::variable_type ty,
                                                 unsigned line_number);

cfg::linear_constraint_t parse_linear_constraint(const std::string &cst,
                                                 cfg::variable_factory_t &vfac,
                                                 crab::variable_type ty,
                                                 unsigned line_number);

void parse_instruction(const std::string &instruction, unsigned line_number,
                       cfg::block_t &b, cfg::variable_factory_t &vfac,
                       cfg::cfg_t &cfg, unsigned &assertion_counter,
                       std::map<unsigned, expected_result> &res);

std::pair<std::vector<std::unique_ptr<cfg::cfg_t>>,
          std::unique_ptr<std::map<unsigned, expected_result>>>
parse_crabir(std::istream &is, cfg::variable_factory_t &vfac);
} // end namespace crab_tests
