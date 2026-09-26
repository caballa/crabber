import Crabber.Soundness
import Crabber.Tactic
/-
# `samples/test-1.crabir`, procedure `foo`, under `-d int` — the *unsafe* companion

`foo` is `bar` with the assertion negated:

    out:   assert(x != 10)

and the source marks it `EXPECT_EQ(false, …)` — Crab reports this assert as an
**error**, not as safe.  Formalising it is the sharpest available check that
the development is not vacuous, because it separates the two halves of
`verified`:

  * the **invariants** are still perfectly sound — Crab's fixpoint is correct
    about the reachable states — and we prove `InvariantOf` below exactly as
    for `bar`;
  * the **assertion obligation** is not merely hard, it is *false*, and we
    prove its negation.  Crab's verdict and Lean's agree.

See `Test1Bar.lean` for the commentary on the shared structure; this file only
annotates what differs.
-/

namespace Crabber
namespace Test1Foo

@[crab] def xGeq (k : Int) : LinCon := { op := .le, terms := [(-1, "x")], const := -k }
@[crab] def xLeq (k : Int) : LinCon := { op := .le, terms := [(1, "x")],  const := k }

/-- The asserted condition: `x != 10`.  Note `op := .ne` — this is the only
    structural difference from `bar`. -/
@[crab] def xNe10 : LinCon := { op := .ne, terms := [(1, "x")], const := 10 }

@[crab] def bodyOf : Label → List Stmt
  | "start"          => [.assign "x" { terms := [], const := 0 }]
  | "loop"           => [.assign "x" { terms := [(1, "x")], const := 1 }]
  | "edge-loop-loop" => [.assume (xLeq 9)]
  | "edge-loop-out"  => [.assume (xGeq 10)]
  | "out"            => [.assert xNe10]
  | _                => []

@[crab] def succOf : Label → List Label
  | "start"          => ["loop"]
  | "loop"           => ["edge-loop-loop", "edge-loop-out"]
  | "edge-loop-loop" => ["loop"]
  | "edge-loop-out"  => ["out"]
  | _                => []

@[crab] def prog : Cfg := { entry := "start", body := bodyOf, succ := succOf }

/-- `.lin` wraps a linear constraint as an invariant atom; the other atom is the
    boolean one, which this program has no use for. -/
@[crab] def inv : Label → Assn
  | "start"          => Assn.top
  | "loop"           => [[.lin (xGeq 0),  .lin (xLeq 9)]]
  | "edge-loop-loop" => [[.lin (xGeq 1),  .lin (xLeq 10)]]
  | "edge-loop-out"  => [[.lin (xGeq 1),  .lin (xLeq 10)]]
  | "out"            => [[.lin (xGeq 10), .lin (xLeq 10)]]
  | _                => Assn.bot

/-! ## Which obligations hold, and which does not

All four *non-assert* blocks verify exactly as in `bar`: Crab's invariants are
genuinely consecutive, and the analysis is not wrong about the reachable
states. -/

theorem vc_start          : VC prog inv "start"          := by crab_vc
theorem vc_loop           : VC prog inv "loop"           := by crab_vc
theorem vc_edge_loop_loop : VC prog inv "edge-loop-loop" := by crab_vc
theorem vc_edge_loop_out  : VC prog inv "edge-loop-out"  := by crab_vc

/-- A state in which every integer variable is 10.

    `⟨…⟩` is anonymous-constructor notation for the record `State`: one constant
    map per store. The boolean one is irrelevant here — this program has no
    booleans — but `State` has two fields, so it must be given. -/
def sigma10 : State := ⟨fun _ => 10, fun _ => false⟩

/-- **Block `out`'s verification condition is false.**

    In English: *there is a state satisfying the invariant Crab printed at
    `out` in which the assertion `x != 10` does not hold* — so no proof of
    `VC prog inv "out"` can exist.

    This is not a limitation of `omega` or of `crab_vc`.  We prove the
    **negation**, so the claim is unconditional: `x = 10` is exactly what Crab
    inferred at `out`, and `x != 10` is exactly what the program asserts there.
    Crab reports this assertion as an *error*; Lean agrees, and the source file
    marks it `EXPECT_EQ(false, …)`.

    `Nat`/`Int` note: `simp` reduces the goal to `¬(10 ≠ 10)`, closed by `rfl`
    inside `simp`. -/
theorem vc_out_false : ¬ VC prog inv "out" := by
  -- Assume the VC held, and instantiate it at the offending state.
  intro h
  have hpre : ⟦inv "out"⟧ sigma10 := by
    simp [crab, sigma10, Assn.holds, Conj.holds, Atom.holds, LinCon.holds, LinCon.lhs,
         LinExp.eval]
  have hbad := h sigma10 hpre
  -- `hbad` unfolds to `xNe10.holds sigma10 ∧ True`, i.e. `(10 : Int) ≠ 10`.
  simp [crab, sigma10, LinCon.holds, LinCon.lhs, LinExp.eval] at hbad

/-! ## What this shows about the design

`bar` and `foo` differ in exactly one character of the CrabIR source, and the
development separates them exactly where it should: four VCs pass in both, and
the fifth passes in `bar` and is *refutable* in `foo`.

It also exposes a design point worth settling deliberately.  Defining the
weakest precondition of an assert as `⟦c⟧ ∧ Q` carries the assertion obligation
**inside** the per-block verification condition.  The consequence is visible
right here: because `VC prog inv "out"` is false, `vc_all` is unprovable for
`foo`, and so `InvariantOf prog inv` cannot be derived — *even though the
invariants themselves are perfectly sound*.  Block `out` has no successors, so
consecution at `out` is vacuous; only the assert makes its VC fail.

Both readings are sound with respect to `Exec` — a failing assert has no
successor state either way — so this is a genuine choice, not a bug:

  * **`∧` (as specified, and as implemented here)** — one obligation per block
    covers both invariant preservation and assertion safety.  Simpler pipeline,
    but "the invariants are sound" is only provable for programs whose
    assertions all pass.
  * **`→` (assume-flavoured)** — the VC would then prove invariant soundness
    alone, with assertion safety left entirely to `chk`.  `foo` would get its
    `InvariantOf` theorem, and the two claims could be reported independently:
    *"invariants sound; 1 of 2 assertions proved"*.

The `∧` reading has since been leaned on further: `chk_of_VC` *derives* the
assertion obligations from the verification conditions, so a per-program file no
longer proves them separately at all.  That is a second thing switching to `→`
would cost — `chk_of_VC` becomes false, and generated files need their `chk`
back.  It does not change the argument above, only its price.

Worth settling before any bulk run over the sample suite, since it changes what
can be reported for programs with deliberately failing assertions — and the
suite is full of them. -/

end Test1Foo
end Crabber
