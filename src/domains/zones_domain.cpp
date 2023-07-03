#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crabber/domains.hpp>

namespace crabber {  
REGISTER_DOMAIN(AbstractDomain::ZONES, sdbm_domain_t)
REGISTER_DOMAIN(AbstractDomain::VAL_PARTITION_ZONES, val_partition_sdbm_domain_t)
} // end namespace crabber
