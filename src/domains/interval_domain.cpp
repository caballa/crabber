#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crabber/domains.hpp>

namespace crabber {  
REGISTER_DOMAIN(AbstractDomain::INTERVALS, interval_domain_t)
REGISTER_DOMAIN(AbstractDomain::SET_INTERVALS, set_interval_domain_t)
REGISTER_DOMAIN(AbstractDomain::VAL_PARTITION_INTERVALS, val_partition_interval_domain_t)
} // end namespace crabber
