#pragma once

#include <crab/cfg/basic_block_traits.hpp>
#include <crab/cfg/cfg.hpp>
#include <crab/cg/cg.hpp>
#include <crab/config.h>
#include <crab/support/debug.hpp>
#include <crab/types/varname_factory.hpp>

#include <string>

namespace crab_tests {
namespace cfg {
using variable_factory_t = crab::var_factory_impl::str_variable_factory;
using varname_t = typename variable_factory_t::varname_t;
using label_t = std::string;
using number_t = ikos::z_number;
using variable_t = crab::variable<number_t, varname_t>;
using cfg_t = crab::cfg::cfg<label_t, varname_t, number_t>;
using cfg_ref_t = crab::cfg::cfg_ref<cfg_t>;
using block_t = cfg_t::basic_block_t;
using variable_or_constant_t = crab::variable_or_constant<number_t, varname_t>;
using linear_expression_t = ikos::linear_expression<number_t, varname_t>;
using linear_constraint_t = ikos::linear_constraint<number_t, varname_t>;
using function_declaration_t = crab::cfg::function_decl<number_t, varname_t>;
} // namespace cfg

namespace callgraph {
using callgraph_t = crab::cg::call_graph<cfg::cfg_ref_t>;
} // namespace callgraph
} // end namespace crab_tests

namespace crab {
template <> class variable_name_traits<std::string> {
public:
  static std::string to_string(std::string varname) { return varname; }
};

template <> class basic_block_traits<crab_tests::cfg::block_t> {
public:
  static std::string to_string(const typename crab_tests::cfg::label_t &bbl) {
    return bbl;
  }
};
} // namespace crab
