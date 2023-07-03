#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crabber/domains.hpp>

namespace crabber {
#ifdef HAVE_LDD   
REGISTER_DOMAIN(AbstractDomain::BOXES, boxes_domain_t)
#endif 
} // end namespace crabber
