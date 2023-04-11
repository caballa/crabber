#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crab/config.h>
#include <crab_tests/domains.hpp>

namespace crab_tests {
#ifdef HAVE_APRON
REGISTER_DOMAIN(AbstractDomain::PK, pk_apron_domain_t)
#elif defined(HAVE_ELINA)
REGISTER_DOMAIN(AbstractDomain::PK, pk_elina_domain_t)
#endif
} // end namespace crab_tests
