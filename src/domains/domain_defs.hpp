#pragma once

#include <crab_tests/crabir.hpp>

#include <crab/domains/array_adaptive.hpp>
#include <crab/domains/flat_boolean_domain.hpp>
#include <crab/domains/region_domain.hpp>
#include <crab/domains/powerset_domain.hpp>
#include <crab/domains/term_equiv.hpp>
#include <crab/domains/lookahead_widening_domain.hpp>
#include <crab/domains/generic_abstract_domain.hpp>

#include <crab/domains/apron_domains.hpp>
#include <crab/domains/boxes.hpp>
#include <crab/domains/combined_domains.hpp>
#include <crab/domains/combined_congruences.hpp>
#include <crab/domains/elina_domains.hpp>
#include <crab/domains/fixed_tvpi_domain.hpp>
#include <crab/domains/intervals.hpp>
#include <crab/domains/split_dbm.hpp>
#include <crab/domains/split_oct.hpp>
#include <crab/domains/wrapped_interval_domain.hpp>

namespace crab_tests {

using namespace cfg;
using namespace crab::domains;
using namespace ikos;
  
#define BASE(DOM) base_ ## DOM
// Term functor domain 
#define TERM_FUN(DOM) \
  term_domain<term::TDomInfo<number_t, varname_t, DOM>>
// Reduced product of boolean domain with numerical domain
#define BOOL_NUM(DOM) flat_boolean_numerical_domain<DOM>
// Array functor domain where the parameter domain is DOM
#define ARRAY_FUN(DOM) array_adapt_domain<DOM>
// Region functor domain -- the root of the hierarchy of domains.
#define RGN_FUN(DOM) region_domain<RegionParams<DOM>>
// Powerset construction
#define POWERSET(DOM) powerset_domain<DOM>
// Lookahead widening
#define LOOKAHEAD_WIDENING(DOM) lookahead_widening_domain<DOM>

/*===================================================================*/
// Numerical domains over integers
/*===================================================================*/
using BASE(interval_domain_t) = interval_domain<number_t, varname_t>;
using interval_domain_t = BOOL_NUM(BASE(interval_domain_t));
using dbm_graph_t = DBM_impl::DefaultParams<number_t, DBM_impl::GraphRep::adapt_ss>;  
using BASE(sdbm_domain_t) = split_dbm_domain<number_t, varname_t, dbm_graph_t>;
using sdbm_domain_t =  BOOL_NUM(BASE(sdbm_domain_t));  
using BASE(soct_domain_t) = split_oct_domain<number_t, varname_t, dbm_graph_t>;
using soct_domain_t = BOOL_NUM(BASE(soct_domain_t));  
using BASE(pk_apron_domain_t) = apron_domain<number_t, varname_t, APRON_PK>;
using pk_apron_domain_t = BOOL_NUM(BASE(pk_apron_domain_t));
using BASE(pk_elina_domain_t) = elina_domain<number_t, varname_t, ELINA_PK>;
using pk_elina_domain_t = BOOL_NUM(BASE(pk_elina_domain_t));  
using BASE(poly_pplite_domain_t) = apron_domain<number_t, varname_t, APRON_PPLITE_POLY>;
using poly_pplite_domain_t = BOOL_NUM(BASE(poly_pplite_domain_t));  
  
/*
using congruences_domain_t = numerical_congruence_domain<interval_domain_t>;
using boxes_domain_t = boxes_domain<number_t, varname_t>;
using oct_apron_domain_t = apron_domain<number_t, varname_t, APRON_OCT>;
using fpoly_pplite_domain_t = apron_domain<number_t, varname_t, APRON_PPLITE_FPOLY>;
using pset_pplite_domain_t = apron_domain<number_t, varname_t, APRON_PPLITE_PSET>;
using oct_elina_domain_t = elina_domain<number_t, varname_t, ELINA_OCT>;
using fixed_tvpi_domain_t = fixed_tvpi_domain<soct_domain_t>;
using wrapped_interval_domain_t = wrapped_interval_domain<number_t, varname_t>;
*/

/*===================================================================*/
// Region domain
/*===================================================================*/
/////using var_allocator = crab::var_factory_impl::str_var_alloc_col;
// template<class BaseAbsDom>
// struct RegionParams {
//   using number_t = number_t;
//   using varname_t = varname_t;
//   using varname_allocator_t = crab::var_factory_impl::str_var_alloc_col;  
//   using base_abstract_domain_t = BaseAbsDom;
//   using base_varname_t = typename BaseAbsDom::varname_t;
// };
  
// using rgn_aa_int_params_t = TestRegionParams<
//   array_adaptive_domain<
//     interval_domain<number_t, typename var_allocator::varname_t>>>;
// using rgn_int_params_t = TestRegionParams<
//   interval_domain<number_t, typename var_allocator::varname_t>>;
// using rgn_bool_int_params_t = TestRegionParams<
//   flat_boolean_numerical_domain<
//     interval_domain<number_t, typename var_allocator::varname_t>>>;
// using rgn_sdbm_params_t = TestRegionParams<
//   split_dbm_domain<number_t, typename var_allocator::varname_t, dbm_graph_t>>;
// using rgn_constant_params_t = TestRegionParams<
//   constant_domain<number_t, typename var_allocator::varname_t>>;
// using rgn_sign_params_t = TestRegionParams<
//   sign_domain<number_t, typename var_allocator::varname_t>>;
// using rgn_sign_cst_params_t = TestRegionParams<
//   sign_constant_domain<number_t, typename var_allocator::varname_t>>;  
// using rgn_int_t = region_domain<rgn_int_params_t>;
// using rgn_bool_int_t = region_domain<rgn_bool_int_params_t>;
// using rgn_sdbm_t = region_domain<rgn_sdbm_params_t>;
// using rgn_aa_int_t = region_domain<rgn_aa_int_params_t>;
// using rgn_constant_t = region_domain<rgn_constant_params_t>;
// using rgn_sign_t = region_domain<rgn_sign_params_t>;
// using rgn_sign_constant_t = region_domain<rgn_sign_cst_params_t>;
  
} // namespace crab_tests
