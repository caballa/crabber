#pragma once

#include <crab_tests/crabir.hpp>
#include <crab/domains/generic_abstract_domain.hpp>

namespace crab_tests {
namespace AbstractDomain {
class Type {
private:
  uint16_t m_value;
  const char *m_name;
  const char *m_description;

public:
  constexpr Type(uint16_t value, const char *name, const char *description)
      : m_value(value), m_name(name), m_description(description) {}
  constexpr Type()
      : m_value(1), m_name("intervals"), m_description("intervals") {}
  ~Type() = default;
  constexpr operator uint16_t() const { return m_value; }
  constexpr uint16_t value() const { return m_value; }
  const char *name() const { return m_name; }
  const char *desc() const { return m_description; }
};
constexpr Type INTERVALS(1, "int", "Classical intervals");
constexpr Type ZONES(2, "zones",
                     "Zones domain using DBMs in Split Normal Form");
constexpr Type OCTAGONS(3, "octagons",
                        "Octagons domain using DBMs in Split Normal Form");
constexpr Type PK(4, "pk", "Polyhedra domain from Apron or Elina");
constexpr Type PK_PPLITE(5, "pk-pplite", "Polyhedra domain from PPLite");
constexpr std::array<Type, 5> List = {INTERVALS, ZONES, OCTAGONS, PK,
                                      PK_PPLITE};
} // end namespace AbstractDomain

using crab_abstract_domain =
    crab::domains::abstract_domain_ref<cfg::variable_t>;
} // namespace crab_tests
