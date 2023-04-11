#include <crab/support/os.hpp>
#include <crab/support/stats.hpp>
#include <crab_tests/domains.hpp>
#include <map>

namespace crab_tests {

class DomainRegistry {
  using domainKey = AbstractDomain::Type;

public:
  using FactoryMap = std::map<domainKey, crab_abstract_domain>;

  template <typename AbsDom> static bool add(domainKey dom_ty) {
    auto &map = getFactoryMap();
    auto dom = DomainRegistry::makeTopDomain<AbsDom>();
    bool res = map.insert({dom_ty, dom}).second;
    crab::CrabStats::reset();
    return res;
  }

  static bool count(domainKey dom_ty) {
    auto &map = getFactoryMap();
    return map.find(dom_ty) != map.end();
  }

  static crab_abstract_domain at(domainKey dom_ty) {
    auto &map = getFactoryMap();
    return map.at(dom_ty);
  }

private:
  static FactoryMap &getFactoryMap() {
    static FactoryMap map;
    return map;
  }

  template <typename AbsDom> static crab_abstract_domain makeTopDomain() {
    AbsDom dom_val;
    crab_abstract_domain res(std::move(dom_val));
    return res;
  }
}; // end class DomainRegistry

#define REGISTER_DOMAIN(domain_enum_val, domain_decl)                          \
  bool domain_decl##_entry =                                                   \
      crab_tests::DomainRegistry::add<domain_decl>(domain_enum_val);

} // end namespace crab_tests
