#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crabber/domains.hpp>

namespace crabber {
REGISTER_DOMAIN(AbstractDomain::OCTAGONS_SNF, soct_domain_t)

#ifdef HAVE_APRON
REGISTER_DOMAIN(AbstractDomain::OCTAGONS, oct_apron_domain_t)
#elif defined(HAVE_ELINA)
REGISTER_DOMAIN(AbstractDomain::OCTAGONS, oct_elina_domain_t)
#endif
} // end namespace crabber
