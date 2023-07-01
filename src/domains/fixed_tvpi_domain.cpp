#include "domain_defs.hpp"
#include "domain_registry.hpp"
#include <crab_tests/domains.hpp>

namespace crab_tests {
REGISTER_DOMAIN(AbstractDomain::FIXED_TVPI, fixed_tvpi_domain_t)
} // end namespace crab_tests
