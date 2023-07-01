#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crab_tests/domains.hpp>

namespace crab_tests {  
REGISTER_DOMAIN(AbstractDomain::ZONES, sdbm_domain_t)
REGISTER_DOMAIN(AbstractDomain::VAL_PARTITION_ZONES, val_partition_sdbm_domain_t)
} // end namespace crab_tests
