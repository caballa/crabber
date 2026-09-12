import CrabberJson.Elab
/-
# `samples/test-bool-1.crabir`, proved from the JSON export

The boolean fragment, end to end. Both cfgs of the sample are loaded from Crab's
own export:

    build/crabber samples/test-bool-1.crabir -d int --print-invariants-to-json \
        lean/CrabberJson/Samples/test-bool-1.json

`safe` is the one that verifies. `unsafe` is its companion with the assertion
negated, and its failing block's verification condition is *refuted* below rather
than merely left unproved — the boolean counterpart of `test-1`'s `foo`/`bar`
pair, and the check that this fragment is not vacuous.

## Why this sample rather than `test-6`

`samples/test-6.crabir` also uses booleans, and cannot be checked: it reaches
them through `trunc`, and integer casts are not modelled. `test-bool-1` avoids
casts deliberately, so every statement in it is one the semantics interprets.

## What `safe` exercises

Every boolean statement Crab's parser can emit:

  * `bool_assign_cst` — `b0 := (x == 10)`, the one statement that reads the
    integer store and writes the boolean one;
  * `bool_binop` — all three of `and`, `or`, `xor`;
  * `bool_assign_var` — both polarities, since `b3 := not(b2)` compiles to the
    plain form with `negated` set rather than to a statement of its own;
  * `bool_assume` — a whole block whose only content is `assume(b2)`;
  * `bool_assert` — four of them, in the final block.

`bool_select` is the one member of the group with no coverage here, because
crabber's parser cannot produce one; it arrives only from LLVM-style frontends.

Two of the assertions are worth noting. `b4 := b0 or not(b0 and b1)` is a
tautology, and `b5 := b0 xor not(b0 and b1)` is one too given `b1`; Crab gets
both right, and the proofs go through as ordinary boolean reasoning rather than
through any 0/1 arithmetic — booleans never enter `omega`'s goals at all.
-/

namespace CrabberJson
namespace TestBool1

open Crabber

/-! ## `safe` — the cfg that verifies

Reads the export while this file is elaborated, checks that reading it is
faithful to the document, and defines `bodyTable`, `succTable`, `invTable`,
`labels`, `prog` and `inv`. `crab_verify` then proves the entry obligation and
every block's verification condition, and bundles them.

Nothing here is specific to booleans: the same two lines serve any program in
the modelled fragment. That is the point of the exercise. -/

namespace Safe

crab_program "CrabberJson/Samples/test-bool-1.json" cfg "safe"
crab_verify

/-- **The theorem**, restated under a name that says what it is.

    *The invariants Crab inferred for cfg `safe` are genuine invariants, and none
    of its four boolean assertions can fail.*

    `verified_program` is what `crab_verify` generated; this is an alias, so that
    the claim is greppable and so that a reader arriving at the bottom of the
    file does not have to know the generated name. -/
theorem safe_verified : InvariantOf prog inv ∧ ¬ AssertFails prog :=
  verified_program

end Safe

/-! ## `unsafe` — the cfg whose assertion is false

Same program, asserting `not(y == 10)` where `y` is 10. Crab reports the
assertion as an error, and the source marks it `EXPECT_EQ(false, …)`.

Only `crab_program` is used here: `crab_verify` would fail, because block `end`'s
verification condition is false and no tactic can prove it. Instead the negation
is proved outright, which is a stronger and much more informative statement than
"the tactic did not succeed".

Note what this separates. Crab's *invariants* for `unsafe` are perfectly sound —
it correctly infers `c1 = false` at `end`. It is the *assertion* that fails, and
because `wpStmt` carries an assert's obligation inside its block's verification
condition, that one false assertion is what makes the block's VC unprovable. The
same coupling is discussed at length in `Crabber.Samples.Test1Foo`; this is its
boolean instance. -/

namespace Unsafe

crab_program "CrabberJson/Samples/test-bool-1.json" cfg "unsafe"

/-- A state matching what Crab inferred at `end`: `y = 10`, `c0` true, and every
    other boolean — `c1` among them — false.

    `fun v => v == "c0"` is the boolean store as a predicate on names; `==` is
    `String`'s decidable equality returning `Bool`, which is exactly the type the
    field wants. The integer store is the constant 10, since only `y` is read. -/
def sigmaBad : State := ⟨fun _ => 10, fun v => v == "c0"⟩

/-- **Block `end`'s verification condition is false.**

    In English: *there is a state satisfying the invariant Crab printed at `end`
    in which the asserted boolean `c1` is false* — so no proof of
    `VC prog inv "end"` exists.

    This is not a limitation of `omega` or of `crab_vc`. The invariant Crab
    printed at `end` literally contains `c1 = false`, and the block literally
    asserts `c1`. Crab reports the assertion as an error; Lean agrees. -/
theorem vc_end_false : ¬ VC prog inv "end" := by
  -- Assume the VC held, and instantiate it at the offending state.
  intro h
  have hpre : ⟦inv "end"⟧ sigmaBad := by
    simp [crab, table, sigmaBad, Assn.holds, Conj.holds, Atom.holds,
          LinCon.holds, LinCon.lhs, LinExp.eval]
  -- `h sigmaBad hpre` unfolds to `sigmaBad.bools "c1" = true ∧ True`, and the
  -- left conjunct is `("c1" == "c0") = true`, which reduces to `False`.
  have hbad := h sigmaBad hpre
  simp [crab, table, sigmaBad] at hbad

end Unsafe

end TestBool1
end CrabberJson
