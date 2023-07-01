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
#include <crab/domains/value_partitioning_domain.hpp>
#include <crab/domains/wrapped_interval_domain.hpp>

namespace crab_tests {

using namespace cfg;
using namespace crab::domains;
using namespace ikos;

/** Domain combinators **/
  
#define BASE(DOM) base_ ## DOM
// Term functor domain 
#define TERM_FUN(DOM) \
  term_domain<term::TDomInfo<number_t, varname_t, DOM>>
// Reduced product of boolean domain with numerical domain
#define BOOL_NUM(DOM) flat_boolean_numerical_domain<DOM>
// Array functor domain where the parameter domain is DOM
#define ARRAY_FUN(DOM) array_adaptive_domain<DOM>
// Region functor domain -- the root of the hierarchy of domains.
#define RGN_FUN(DOM) region_domain<RegionParams<DOM>>
// Naive powerset construction
#define POWERSET(DOM) powerset_domain<DOM>
// Value partitioning
#define VAL_PARTITIONING(DOM) product_value_partitioning_domain<DOM>
// Lookahead widening
#define LOOKAHEAD_WIDENING(DOM) lookahead_widening_domain<DOM>

template<class BaseAbsDom>
struct RegionParams {
   using number_t = number_t;
   using varname_t = varname_t;
   using varname_allocator_t = varname_t::variable_factory_t;  
   using base_abstract_domain_t = BaseAbsDom;
   using base_varname_t = typename BaseAbsDom::varname_t;
};
using dbm_graph_t = DBM_impl::DefaultParams<number_t, DBM_impl::GraphRep::adapt_ss>;


/** Base domains **/

// Octagons  
using BASE(soct_domain_t) = split_oct_domain<number_t, varname_t, dbm_graph_t>;
using soct_domain_t = ARRAY_FUN(BOOL_NUM(BASE(soct_domain_t)));  
#ifdef HAVE_APRON
using BASE(oct_apron_domain_t) = apron_domain<number_t, varname_t, APRON_OCT>;
using oct_apron_domain_t = ARRAY_FUN(BOOL_NUM(BASE(oct_apron_domain_t)));
#elif defined(HAVE_ELINA)
using BASE(oct_elina_domain_t) = elina_domain<number_t, varname_t, ELINA_OCT>;
using oct_elina_domain_t = ARRAY_FUN(BOOL_NUM(BASE(oct_elina_domain_t)));  
#endif
// intervals
using BASE(interval_domain_t) = interval_domain<number_t, varname_t>;
using interval_domain_t = ARRAY_FUN(BOOL_NUM(BASE(interval_domain_t)));
using BASE(interval_domain_t) = interval_domain<number_t, varname_t>;
using set_interval_domain_t = POWERSET(ARRAY_FUN(BOOL_NUM(BASE(interval_domain_t))));
using val_partition_interval_domain_t = VAL_PARTITIONING(ARRAY_FUN(BOOL_NUM(BASE(interval_domain_t))));
using boxes_domain_t = boxes_domain<number_t, varname_t>;  
// polyhedra
#ifdef HAVE_APRON
using BASE(pk_apron_domain_t) = apron_domain<number_t, varname_t, APRON_PK>;
using pk_apron_domain_t = ARRAY_FUN(BOOL_NUM(BASE(pk_apron_domain_t))); 
#elif defined(HAVE_ELINA)
using BASE(pk_elina_domain_t) = elina_domain<number_t, varname_t, ELINA_PK>;
using pk_elina_domain_t = ARRAY_FUN(BOOL_NUM(BASE(pk_elina_domain_t)));  
#endif
#ifdef HAVE_PPLITE
using BASE(poly_pplite_domain_t) = apron_domain<number_t, varname_t, APRON_PPLITE_POLY>;
using poly_pplite_domain_t = ARRAY_FUN(BOOL_NUM(BASE(poly_pplite_domain_t)));
using set_poly_pplite_domain_t = apron_domain<number_t, varname_t, APRON_PPLITE_PSET>; 
#endif 
// zones
using BASE(sdbm_domain_t) = split_dbm_domain<number_t, varname_t, dbm_graph_t>;
using sdbm_domain_t =  ARRAY_FUN(BOOL_NUM(BASE(sdbm_domain_t)));  
using val_partition_sdbm_domain_t = VAL_PARTITIONING(ARRAY_FUN(BOOL_NUM(BASE(sdbm_domain_t))));
// fixed tvpi
#ifdef HAVE_APRON  
using BASE(fixed_tvpi_domain_t) = fixed_tvpi_domain<oct_apron_domain_t>;
#elif defined(HAVE_ELINA)
using BASE(fixed_tvpi_domain_t) = fixed_tvpi_domain<oct_elina_domain_t>;
#else
using BASE(fixed_tvpi_domain_t) = fixed_tvpi_domain<soct_domain_t>;  
#endif   
using fixed_tvpi_domain_t = ARRAY_FUN(BOOL_NUM(BASE(fixed_tvpi_domain_t)));  
// symbolic terms
using terms_interval_domain_t =  ARRAY_FUN(BOOL_NUM(TERM_FUN(interval_domain_t)));
} // namespace crab_tests
