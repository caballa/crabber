#pragma once

/**
 * Normalization of inferred invariants, for people reading them.
 *
 * Crab's domains report what they inferred as a `linear_constraint_system`, and
 * its printer is faithful rather than kind: the octagon domain says
 *
 *   -n <= -1; n-i <= 0; -n-i <= -2; -i <= -1; -n+i <= 0; -s <= -1
 *
 * when what it means is
 *
 *   n >= 1, i >= 1, s >= 1;  n = i;  n + i >= 2
 *
 * Both describe the same set of states. The second is the one a reader can
 * check against their intent, and producing it is all this module does.
 *
 * ## Why there are two layers
 *
 * A `linear_constraint` is a `linear_expression` plus one of four kinds --
 * EQUALITY, DISEQUATION, INEQUALITY, STRICT_INEQUALITY -- so every constraint
 * is structurally `expr op 0` with `op` drawn from `{=, !=, <=, <}`. There is no
 * `>=`, no constraint with terms on both sides, and no chained `lo <= e <= hi`.
 * That is not an oversight; a one-sided form with a fixed relation is what makes
 * the domains' arithmetic uniform.
 *
 * It does mean the rewrites split in two, and the split is forced by the
 * representation rather than chosen:
 *
 *   **Layer 1** maps a constraint system to an equivalent constraint system.
 *   Everything it does stays inside `expr op 0`, so its result is still a
 *   `linear_constraint_system` and can go anywhere one can -- including the JSON
 *   export, with no change to that document's shape.
 *
 *   **Layer 2** renders constraints as text. Orienting `-n <= -1` as `n >= 1`,
 *   splitting `-n+i <= 0` into `i <= n`, and chaining two bounds into
 *   `1 <= x <= 8` all produce forms no `linear_constraint` can hold, so they
 *   produce a string instead.
 *
 * The split lands almost exactly on the risk boundary, which is the reason to
 * keep it visible. Layer 1 rewrites claims: a bug there means a reported
 * invariant is not the one inferred. Layer 2 only chooses how to spell a claim,
 * so it cannot be unsound -- the worst it can be is ugly.
 *
 * That asymmetry is what makes layer 1 worth checking and layer 2 not worth
 * checking. Layer 1's output is a constraint system, so `--verify-with-lean` can
 * be handed the normalized form and the raw form and asked whether each entails
 * the other; `omega` decides it outright. Layer 2 never reaches Lean, and there
 * is nothing for a proof to say about it.
 *
 * ## What layer 1 does
 *
 * - Pairs `e <= 0` and `-e <= 0` become `e = 0`. Crab's own
 *   `linear_constraint_system::normalize()` already does this, so it is called
 *   rather than reimplemented; it also picks the sign for a unary equality.
 * - Coefficients are divided through by their GCD, but only when it divides the
 *   constant exactly, which keeps the step an equivalence.
 * - Tautologies are dropped, and one contradiction collapses the system.
 * - Exact duplicates go, as does the weaker of two bounds on the same
 *   expression. Only syntactic redundancy: no entailment check, so nothing is
 *   hidden on the strength of a solver's say-so.
 * - Constraints are ordered for reading -- bounds first, then equalities, then
 *   the rest.
 *
 * Integer tightening (`2x <= 3` becomes `x <= 1`) is deliberately absent. It is
 * sound over the integers these variables range over, but it is not an
 * equivalence, so admitting it would cost exactly the `raw <=> normalized` check
 * that makes layer 1 trustworthy. If it is ever wanted it needs its own option
 * and a one-directional check.
 *
 * ## What layer 2 does
 *
 * - Terms are split by the sign of their coefficient, positives on the left and
 *   negated negatives on the right, with the constant going wherever it stays
 *   non-negative; if the left side empties, the sides swap and the relation
 *   flips. Sign orientation is not a separate rule -- it is this rule when there
 *   are no positive coefficients.
 * - `1*x` prints as `x`.
 * - Opposite bounds on one expression chain into `lo <= e <= hi`.
 *
 * ## One domain cannot take part
 *
 * `dis-int` has no `to_disjunctive_linear_constraint_system` -- Crab raises
 * `CRAB_ERROR` for it -- so there is no constraint system to normalize and
 * callers must fall back to printing the domain itself. `supportsNormalization`
 * answers that question so the fallback is a decision rather than a crash.
 *
 * Every other domain's constraint system carries its full content, including the
 * ones whose own printers show more structure: the term domain emits the
 * equalities implied by two variables sharing a term, and the
 * value-partitioning domains emit the constraints of each partition.
 */

#include <crabber/crabir.hpp>
#include <crabber/domains.hpp>

#include <crab/types/linear_constraints.hpp>

#include <string>

namespace crabber {

using linear_constraint_system_t =
    ikos::linear_constraint_system<cfg::number_t, cfg::varname_t>;
using disjunctive_linear_constraint_system_t =
    ikos::disjunctive_linear_constraint_system<cfg::number_t, cfg::varname_t>;

/* ---- Layer 1: constraint system in, equivalent constraint system out ---- */

/** Rewrite a conjunction into an equivalent, tidier one. */
linear_constraint_system_t normalize(const linear_constraint_system_t &csts);

/** Rewrite each disjunct. A disjunct that normalizes to `true` makes the whole
 *  disjunction `true`, which is why this is not a plain map over disjuncts. */
disjunctive_linear_constraint_system_t
normalize(const disjunctive_linear_constraint_system_t &csts);

/* ---- Layer 2: constraint system in, text out ---- */

/** Render one conjunction. Does not normalize first: pass it the output of
 *  `normalize` when that is wanted, so the two layers stay separable. */
std::string render(const linear_constraint_system_t &csts);

/** Render a disjunction, as its disjuncts joined by `or`. */
std::string render(const disjunctive_linear_constraint_system_t &csts);

/** Whether `dom` can produce a constraint system at all. False only for
 *  `dis-int`; a caller seeing false must print the domain itself instead. */
bool supportsNormalization(const AbstractDomain::Type &dom);

/**
 * A domain's invariant, rendered normalized when it is streamed.
 *
 * `crab::cfg::cfg_to_dot` is templated on the invariant type and only ever
 * streams it, so standing in a type whose `operator<<` renders normalized text
 * gets normalized invariants into the dot without touching Crab.
 */
class NormalizedInvariant {
  crab_abstract_domain m_dom;
  bool m_normalize;

public:
  NormalizedInvariant(crab_abstract_domain dom, bool normalize)
      : m_dom(dom), m_normalize(normalize) {}

  void write(crab::crab_os &o) const;
};

inline crab::crab_os &operator<<(crab::crab_os &o,
                                 const NormalizedInvariant &inv) {
  inv.write(o);
  return o;
}

} // end namespace crabber
