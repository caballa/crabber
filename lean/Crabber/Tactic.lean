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

/-! ## The `crab_meaning` set

Every unfolding on the path from invariant *data* to arithmetic, named once.

`⟦A⟧ σ` is a chain: `Assn.holds` picks a disjunct, `Conj.holds` picks a conjunct,
`Atom.holds` says which store that conjunct reads, and `LinCon.holds`,
`LinCon.lhs` and `LinExp.eval` evaluate it down to a comparison of `Int`s.
`omega` decides the last link and nothing above it, so a proof that stops
partway leaves it staring at an opaque application. `Assn.top` and `Assn.bot`
join them because the chain cannot start on a degenerate invariant until they
are unfolded to their list encodings, and `BoolOp.apply` because the boolean
atoms bottom out there instead.

**This set exists because two proofs need the identical list and drifted apart.**
`crab_vc` below is one consumer; the entry obligation `crab_verify` generates in
`CrabberJson.Elab` is the other. That one carried a hand-copied subset missing
`Atom.holds`, which cost nothing on the interval domain — its entry invariant is
literally `Assn.top`, closed by a different branch — and silently failed every
octagon run, where the domain exports the nullary constraint `{"op": "true"}`
and the entry invariant is `[[0 ≤ 0]]` instead. The obligation reached `omega` as
`(Atom.lin …).holds σ` and it reported "no usable constraints found".

So: add a meaning function here, not at a call site. A new atom kind that is
unfolded in one of the two proofs and not the other reproduces exactly that bug,
and it reproduces it as a *verdict*, never as a wrong answer — which is what
makes it cheap to ship and expensive to find. -/
attribute [crab_meaning]
  Assn.holds Conj.holds Atom.holds
  LinCon.holds LinCon.lhs LinExp.eval
  BoolOp.apply
  Assn.top Assn.bot

/-- **`crab_vc` — discharge one block's verification condition.**

    In English: *unfold everything until the goal is linear integer arithmetic,
    then call `omega`.*

    The pipeline:

    1. `intro σ hpre` — `VC` is a `def`, so it unfolds definitionally as `intro`
       looks at the goal; no explicit unfolding step is needed. Take the state
       arbitrary, assume the invariant at the block's entry.
    2. `simp` with the `crab` and `crab_meaning` sets — this does four things at
       once:
         * unfolds the program and the annotation, so the block's concrete
           statement list and successor list appear;
         * unfolds the weakest-precondition calculus over that list, pushing the
           postcondition backwards — assignments become state updates, `assume`s
           become arrows;
         * rewrites `(σ.set "y" v).ints "y"` to `v`, which is where substitution
           actually happens. Boolean statements go the same way: `setBool_same`
           substitutes, `LinCon.check_eq_true` turns a recorded comparison back
           into the proposition it decided, and `Bool.and_eq_true` and friends
           break the connectives apart, so a boolean assignment leaves *integer*
           arithmetic behind and `omega` never sees a `Bool`;
         * unfolds the meaning function on both the hypothesis and the goal,
           turning invariant *data* into arithmetic, and collapses the bounded
           quantifier over successors into a plain conjunction.
    3. `omega` on whatever is left — quantifier-free linear integer arithmetic.
    4. a `simp_all` pass, then `omega` again, for whatever step 3 could not
       close.

    `all_goals omega` rather than `omega` so that a goal `simp` already closed
    (for instance a block whose successors carry no constraints) is not an error.

    **Why step 4 exists, and why it is not step 2.** A boolean fact can have to
    travel from the *hypothesis* to the goal — a loop carrying a boolean has
    `b = true` in the invariant at both ends and no statement in between, so
    nothing in the goal reduces it away. `simp … at hpre ⊢` cannot do that: it
    simplifies the two independently. `simp_all` can, because it uses hypotheses
    to rewrite the goal.

    So why not `simp_all` throughout? Because it is *not* a superset here:
    replacing step 2 with it loses integer bounds that `omega` needs — `simp_all`
    rewrites hypotheses with each other and can consume one that was carrying a
    bound. Running the narrow pass first and `simp_all` only on the survivors
    keeps every previously-provable goal provable and adds the boolean ones.

    **Where this will fail** — all of it out of scope for the modelled fragment,
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
      simp [crab, table, crab_meaning] at hpre ⊢
      all_goals (try omega)
      all_goals (try simp_all [crab_meaning])
      all_goals omega))

end Crabber
