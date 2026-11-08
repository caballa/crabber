#include <crabber/normalize.hpp>

#include <crab/support/os.hpp>

#include <algorithm>
#include <map>
#include <vector>

namespace crabber {

using namespace cfg;

namespace {

/** Iteration over a `linear_expression` yields (coefficient, variable). */
using component_t = std::pair<number_t, variable_t>;

std::string toStr(const variable_t &v) {
  crab::crab_string_os o;
  o << v;
  return o.str();
}

/* ======================= Layer 1 ======================= */

/**
 * Divide a constraint through by the GCD of its coefficients.
 *
 * Only when the GCD divides the constant too. `2x + 4y = 6` becomes
 * `x + 2y = 3`, but `2x <= 3` is left alone: rewriting it to `x <= 1` is
 * tightening, which holds over the integers but is not the equivalence this
 * layer promises.
 */
linear_constraint_t divideByGcd(const linear_constraint_t &c) {
  const linear_expression_t &e = c.expression();
  number_t g(0);
  for (auto const &t : e) {
    // gcd is always non-negative, whatever the signs of the operands.
    g = g.gcd(t.first);
  }
  if (g <= number_t(1)) {
    return c;
  }
  const number_t k = e.constant();
  if (k % g != number_t(0)) {
    return c;
  }
  linear_expression_t out(k / g);
  for (auto const &t : e) {
    out = out + (t.first / g) * t.second;
  }
  return linear_constraint_t(out, c.kind());
}

/**
 * The non-constant part of an expression, with its leading coefficient made
 * positive, and whether that required negating it.
 *
 * This is what lets `x <= 9` and `-x <= -1` be recognised as bounds on the same
 * expression: they differ only in which direction they bound it. Variables are
 * held in an ordered map, so "leading" is well defined and the same expression
 * always canonicalises the same way.
 */
std::pair<std::vector<component_t>, bool>
canonicalTerms(const linear_expression_t &e) {
  std::vector<component_t> ts;
  for (auto const &t : e) {
    ts.push_back(t);
  }
  const bool negated = !ts.empty() && ts.front().first < number_t(0);
  if (negated) {
    for (auto &t : ts) {
      t.first = -t.first;
    }
  }
  return {ts, negated};
}

std::string termsKey(const std::vector<component_t> &ts) {
  std::string k;
  for (auto const &t : ts) {
    k += t.first.get_str() + "*" + toStr(t.second) + "+";
  }
  return k;
}

linear_expression_t buildExpr(const std::vector<component_t> &ts,
                              const number_t &cst, bool negateTerms) {
  linear_expression_t e(cst);
  for (auto const &t : ts) {
    e = e + (negateTerms ? -t.first : t.first) * t.second;
  }
  return e;
}

/** The tightest bounds seen on one expression. */
struct Bounds {
  std::vector<component_t> terms;
  bool hasLo = false, hasHi = false;
  number_t lo{0}, hi{0};
  bool loStrict = false, hiStrict = false;
  unsigned first = 0; // first appearance, so output order is stable
};

/** Keep the tighter of two upper bounds; at equal value, strict is tighter. */
void tightenHi(Bounds &b, const number_t &v, bool strict) {
  if (!b.hasHi || v < b.hi || (v == b.hi && strict && !b.hiStrict)) {
    b.hasHi = true;
    b.hi = v;
    b.hiStrict = strict;
  }
}

void tightenLo(Bounds &b, const number_t &v, bool strict) {
  if (!b.hasLo || v > b.lo || (v == b.lo && strict && !b.loStrict)) {
    b.hasLo = true;
    b.lo = v;
    b.loStrict = strict;
  }
}

/** Where a constraint sorts: single-variable facts first, then equalities
    between expressions, then everything relational. */
unsigned rankOf(const linear_constraint_t &c) {
  const std::size_t n = c.expression().size();
  if (n <= 1) {
    return 0;
  }
  return c.is_equality() ? 1 : 2;
}

} // end anonymous namespace

linear_constraint_system_t normalize(const linear_constraint_system_t &in) {
  // Pairs `e <= 0` and `-e <= 0` become `e = 0`. Crab already does this, and
  // also settles the sign of a unary equality, so it is not redone here.
  const linear_constraint_system_t merged = in.normalize();

  std::map<std::string, Bounds> bounds;
  std::vector<linear_constraint_t> others;
  unsigned seen = 0;

  for (auto const &raw : merged) {
    if (raw.is_tautology()) {
      continue;
    }
    if (raw.is_contradiction()) {
      // One unsatisfiable conjunct makes the conjunction unsatisfiable, and
      // saying so once is clearer than printing the conjunct that proves it.
      return linear_constraint_system_t(linear_constraint_t::get_false());
    }
    const linear_constraint_t c = divideByGcd(raw);
    const bool isIneq = c.is_inequality() || c.is_strict_inequality();
    if (!isIneq || c.expression().size() == 0) {
      others.push_back(c);
      continue;
    }
    // `t + k op 0` bounds the canonical form of `t`; which side it bounds
    // depends on whether canonicalising had to negate it.
    auto canon = canonicalTerms(c.expression());
    const std::string key = termsKey(canon.first);
    auto it = bounds.find(key);
    if (it == bounds.end()) {
      Bounds fresh;
      fresh.terms = canon.first;
      fresh.first = seen++;
      it = bounds.emplace(key, std::move(fresh)).first;
    }
    const number_t k = c.expression().constant();
    const bool strict = c.is_strict_inequality();
    if (canon.second) {
      tightenLo(it->second, k, strict); // -t + k op 0  <=>  t >= k
    } else {
      tightenHi(it->second, -k, strict); //  t + k op 0  <=>  t <= -k
    }
  }

  // Rebuild. Each surviving bound goes back as a constraint of its own:
  // chaining the two into `lo <= t <= hi` is a rendering choice, and a
  // `linear_constraint` cannot hold it anyway.
  std::vector<linear_constraint_t> rebuilt;
  std::vector<const Bounds *> ordered;
  for (auto const &kv : bounds) {
    ordered.push_back(&kv.second);
  }
  std::sort(ordered.begin(), ordered.end(),
            [](const Bounds *a, const Bounds *b) { return a->first < b->first; });
  for (const Bounds *b : ordered) {
    if (b->hasLo) {
      rebuilt.push_back(linear_constraint_t(
          buildExpr(b->terms, b->lo, /*negateTerms=*/true),
          b->loStrict ? linear_constraint_t::STRICT_INEQUALITY
                      : linear_constraint_t::INEQUALITY));
    }
    if (b->hasHi) {
      rebuilt.push_back(linear_constraint_t(
          buildExpr(b->terms, -b->hi, /*negateTerms=*/false),
          b->hiStrict ? linear_constraint_t::STRICT_INEQUALITY
                      : linear_constraint_t::INEQUALITY));
    }
  }
  rebuilt.insert(rebuilt.end(), others.begin(), others.end());

  // Order for reading. `stable_sort` so constraints of equal rank keep the
  // order they were inferred in rather than an arbitrary one.
  std::stable_sort(rebuilt.begin(), rebuilt.end(),
                   [](const linear_constraint_t &a,
                      const linear_constraint_t &b) {
                     const unsigned ra = rankOf(a), rb = rankOf(b);
                     if (ra != rb) {
                       return ra < rb;
                     }
                     return a.expression().size() < b.expression().size();
                   });

  linear_constraint_system_t out;
  for (auto const &c : rebuilt) {
    out += c; // += already drops an exact duplicate
  }
  return out;
}

disjunctive_linear_constraint_system_t
normalize(const disjunctive_linear_constraint_system_t &in) {
  if (in.is_false() || in.is_true()) {
    return in;
  }
  disjunctive_linear_constraint_system_t out(/*is_false=*/true);
  for (auto const &disjunct : in) {
    const linear_constraint_system_t n = normalize(disjunct);
    if (n.is_true()) {
      // One disjunct holding everywhere makes the disjunction hold everywhere.
      // `+= true` is an error on this type, so this has to return rather than
      // accumulate.
      return disjunctive_linear_constraint_system_t(/*is_false=*/false);
    }
    if (n.is_false()) {
      continue; // contributes nothing to a disjunction
    }
    out += n;
  }
  return out;
}

/* ======================= Layer 2 ======================= */

namespace {

std::string numToString(const number_t &n) { return n.get_str(); }

/** `Σ aᵢ·xᵢ` with every coefficient positive, eliding a coefficient of 1. */
std::string termsToString(const std::vector<component_t> &ts) {
  std::string s;
  for (std::size_t i = 0; i < ts.size(); ++i) {
    if (i) {
      s += " + ";
    }
    if (ts[i].first == number_t(1)) {
      s += toStr(ts[i].second);
    } else {
      s += numToString(ts[i].first) + "*" + toStr(ts[i].second);
    }
  }
  return s;
}

/** One side of a relation: some terms plus a constant, either possibly empty. */
std::string sideToString(const std::vector<component_t> &ts,
                         const number_t &cst) {
  if (ts.empty()) {
    return numToString(cst);
  }
  std::string s = termsToString(ts);
  if (cst > number_t(0)) {
    s += " + " + numToString(cst);
  } else if (cst < number_t(0)) {
    s += " - " + numToString(-cst);
  }
  return s;
}

const char *relSymbol(linear_constraint_t::kind_t kind, bool flip) {
  switch (kind) {
  case linear_constraint_t::INEQUALITY:
    return flip ? " >= " : " <= ";
  case linear_constraint_t::STRICT_INEQUALITY:
    return flip ? " > " : " < ";
  case linear_constraint_t::EQUALITY:
    return " = ";
  default:
    return " != ";
  }
}

/**
 * Render one constraint by splitting its terms across the relation.
 *
 * `expr op 0` with `expr = P - N + k` is the same claim as `P op N - k`, so the
 * positive coefficients go left and the negated negative ones right. When there
 * are no positive coefficients the left side would be bare constant, so the
 * sides swap and the relation flips -- which is how `-n <= -1` comes out as
 * `n >= 1`. Sign orientation is not a separate rule; it is this one.
 */
std::string renderOne(const linear_constraint_t &c) {
  if (c.is_tautology()) {
    return "true";
  }
  if (c.is_contradiction()) {
    return "false";
  }
  std::vector<component_t> pos, neg;
  for (auto const &t : c.expression()) {
    if (t.first > number_t(0)) {
      pos.push_back(t);
    } else {
      neg.push_back({-t.first, t.second});
    }
  }
  const number_t k = c.expression().constant();
  if (!pos.empty()) {
    return termsToString(pos) + relSymbol(c.kind(), /*flip=*/false) +
           sideToString(neg, -k);
  }
  return termsToString(neg) + relSymbol(c.kind(), /*flip=*/true) +
         numToString(k);
}

} // end anonymous namespace

std::string render(const linear_constraint_system_t &csts) {
  if (csts.is_false()) {
    return "false";
  }
  if (csts.is_true()) {
    return "true";
  }

  // Opposite bounds on one expression chain into `lo <= t <= hi`. Collected
  // first so the two constraints that chain are not also printed separately.
  std::map<std::string, Bounds> bounds;
  std::vector<std::string> parts;
  std::vector<std::string> pending; // keys, in the order their bound appeared

  for (auto const &c : csts) {
    const bool isIneq = c.is_inequality() || c.is_strict_inequality();
    if (!isIneq || c.expression().size() == 0) {
      continue;
    }
    auto canon = canonicalTerms(c.expression());
    const std::string key = termsKey(canon.first);
    auto it = bounds.find(key);
    if (it == bounds.end()) {
      Bounds fresh;
      fresh.terms = canon.first;
      it = bounds.emplace(key, std::move(fresh)).first;
    }
    const number_t k = c.expression().constant();
    const bool strict = c.is_strict_inequality();
    if (canon.second) {
      tightenLo(it->second, k, strict);
    } else {
      tightenHi(it->second, -k, strict);
    }
  }

  for (auto const &c : csts) {
    const bool isIneq = c.is_inequality() || c.is_strict_inequality();
    if (isIneq && c.expression().size() > 0) {
      auto canon = canonicalTerms(c.expression());
      const std::string key = termsKey(canon.first);
      const Bounds &b = bounds.at(key);
      if (b.hasLo && b.hasHi) {
        // Emit the chain once, at the first of the two constraints.
        if (std::find(pending.begin(), pending.end(), key) == pending.end()) {
          pending.push_back(key);
          parts.push_back(numToString(b.lo) + (b.loStrict ? " < " : " <= ") +
                          termsToString(b.terms) +
                          (b.hiStrict ? " < " : " <= ") + numToString(b.hi));
        }
        continue;
      }
    }
    parts.push_back(renderOne(c));
  }

  std::string out = "{";
  for (std::size_t i = 0; i < parts.size(); ++i) {
    if (i) {
      out += "; ";
    }
    out += parts[i];
  }
  return out + "}";
}

std::string render(const disjunctive_linear_constraint_system_t &csts) {
  if (csts.is_false()) {
    return "false";
  }
  if (csts.is_true()) {
    return "true";
  }
  std::string out;
  bool first = true;
  for (auto const &disjunct : csts) {
    if (!first) {
      out += " or ";
    }
    first = false;
    out += render(disjunct);
  }
  return out;
}

bool supportsNormalization(const AbstractDomain::Type &dom) {
  // dis_intervals has no to_disjunctive_linear_constraint_system: Crab raises
  // CRAB_ERROR rather than returning one, so there is nothing to normalize.
  return dom.value() != AbstractDomain::DIS_INTERVALS.value();
}

void NormalizedInvariant::write(crab::crab_os &o) const {
  if (!m_normalize) {
    o << m_dom;
    return;
  }
  o << render(normalize(m_dom.to_disjunctive_linear_constraint_system()));
}

} // end namespace crabber
