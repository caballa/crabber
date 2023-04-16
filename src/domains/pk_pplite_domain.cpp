#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crab_tests/domains.hpp>

namespace crab_tests {
#ifdef HAVE_APRON  
REGISTER_DOMAIN(AbstractDomain::PK_PPLITE, poly_pplite_domain_t)
#endif 
} // end namespace crab_tests
