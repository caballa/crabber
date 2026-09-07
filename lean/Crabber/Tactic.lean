import Crabber.Attr
import Crabber.VC
/-
# Crabber.Tactic — `crab_vc`, the per-block automation

**Untrusted.** A tactic is a *metaprogram that runs in the elaborator and
constructs a proof term*; the term is what gets stored and checked by the
kernel. So `crab_vc` can be as unprincipled as convenient: the worst a bug can
do is fail to find a proof, or produce one the kernel rejects — a build error,
never a false theorem. That is why the tactic owes no correctness argument.
-/

namespace Crabber

/-- **`crab_vc` — discharge one block's verification condition.**

    In English: *unfold everything until the goal is linear integer arithmetic,
    then call `omega`.*

    The pipeline:

    1. `intro σ hpre` — `VC` is a `def`, so it unfolds definitionally as `intro`
       looks at the goal; no explicit unfolding step is needed. Take the state
       arbitrary, assume the invariant at the block's entry.
    2. `simp` with the `crab` set — this does four things at once:
         * unfolds the program and the annotation, so the block's concrete
           statement list and successor list appear;
         * unfolds the weakest-precondition calculus over that list, pushing the
           postcondition backwards — assignments become state updates, `assume`s
           become arrows;
         * rewrites `(σ.set "y" v).ints "y"` to `v`, which is where substitution
           actually happens;
         * unfolds the meaning function on both the hypothesis and the goal,
           turning invariant *data* into arithmetic, and collapses the bounded
           quantifier over successors into a plain conjunction.
    3. `omega` on whatever is left — quantifier-free linear integer arithmetic.

    `all_goals omega` rather than `omega` so that a goal `simp` already closed
    (for instance a block whose successors carry no constraints) is not an error.

    **Where this will fail** — all of it out of scope for the numeric fragment,
    and all of it producing "could not prove", never a wrong answer:
      * non-linear statements (`x := y*z`, `y/z`): `omega` decides Presburger
        arithmetic, and multiplication of variables is outside it. The rounding
        behaviour of Crab's four division operators is not even fixed yet.
      * disjunctive invariants from the powerset domains: `simp` turns them into
        `∨` hypotheses, and the cost is (disjuncts in the precondition) ×
        (disjuncts in the postcondition) `omega` calls.
      * programs over many variables, where the rewrite for *unrelated* writes
        must discharge string disequalities to see through them. -/
macro "crab_vc" : tactic =>
  `(tactic| (
      intro σ hpre
      simp [crab, table, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs,
            LinExp.eval, Assn.top, Assn.bot] at hpre ⊢
      all_goals omega))

end Crabber
