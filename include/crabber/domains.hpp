#pragma once

#include <crabber/crabir.hpp>
#include <crab/domains/generic_abstract_domain.hpp>

namespace crabber {
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

// Base domains  
constexpr Type INTERVALS(1, "int", "Classical intervals");
constexpr Type DIS_INTERVALS(2, "dis-int", "DisInterval domain");
constexpr Type BOXES(3, "boxes", "Disjunctive intervals based on Linear Decision Diagrams");
constexpr Type ZONES(4, "zones", "Zones domain using DBMs in Split Normal Form");
constexpr Type OCTAGONS_SNF(5, "oct-snf","Octagons domain using DBMs in Split Normal Form");
constexpr Type OCTAGONS(6, "oct","Octagons domain from Apron or Elina");
constexpr Type FIXED_TVPI(7, "fixed-tvpi","Fixed TVPI using Octagons");    
constexpr Type PK(8, "pk", "Polyhedra domain from Apron or Elina");
constexpr Type PK_PPLITE(9, "pk-pplite", "Polyhedra domain from PPLite");

// Complex domains
constexpr Type TERMS_INTERVALS(10, "int-terms", "Reduced product of Herbrand terms and intervals");    
constexpr Type SET_INTERVALS(11, "int-set", "Naive powerset of intervals");
constexpr Type VAL_PARTITION_INTERVALS(12, "int-val-part", "Value partitioning of intervals");
constexpr Type SET_PK_PPLITE(13, "pk-pplite-set", "Powerset of pk");    
constexpr Type VAL_PARTITION_ZONES(14, "zones-val-part", "Value partitioning of zones");
  
constexpr std::array<Type, 14>
List = {INTERVALS, DIS_INTERVALS, TERMS_INTERVALS, SET_INTERVALS, VAL_PARTITION_INTERVALS, BOXES,
	ZONES, VAL_PARTITION_ZONES,
	OCTAGONS_SNF, OCTAGONS,
	FIXED_TVPI,
	PK, PK_PPLITE, SET_PK_PPLITE};
} // end namespace AbstractDomain

using crab_abstract_domain =
    crab::domains::abstract_domain_ref<cfg::variable_t>;
} // namespace crabber
