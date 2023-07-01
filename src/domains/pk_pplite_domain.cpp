#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crab_tests/domains.hpp>

namespace crab_tests {
#ifdef HAVE_PPLITE
REGISTER_DOMAIN(AbstractDomain::PK_PPLITE, poly_pplite_domain_t)
REGISTER_DOMAIN(AbstractDomain::SET_PK_PPLITE, set_poly_pplite_domain_t)
#endif 
} // end namespace crab_tests
