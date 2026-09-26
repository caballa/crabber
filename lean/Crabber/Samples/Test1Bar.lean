import Crabber.Soundness
import Crabber.Tactic
/-
# `samples/test-1.crabir`, procedure `bar`, under `-d int`

This is the **per-program** artifact — the only part that will eventually be
machine generated, from the two JSON documents:

    crabber samples/test-1.crabir -d int --cfg-to-json -
    crabber samples/test-1.crabir -d int --print-invariants-to-json -

The source program is a counting loop:

    start: y := 0            goto loop
    loop:  y := y + 1        if (y <= 9) goto loop else goto out
    out:   assert(y == 10)

Note the CFG below is the one **Crab analysed**, not the source text: the
conditional has been compiled into the two `edge-loop-*` blocks that carry the
guards.  That is why the export walks the analyser's final graph — a
transcription of the source would not line up with the invariant labels.

Everything here is data plus `by crab_vc`.  There is no reasoning about `Step`,
`Reachable`, or induction anywhere in this file; all of that lives once in
`Crabber/Soundness.lean` and `Crabber/VC.lean`.
-/

namespace Crabber
namespace Test1Bar

/-! ## The program (from `--cfg-to-json`)

`@[crab]` puts each definition in the simp set `crab_vc` unfolds. -/

/-- `y ≥ k`, exported by Crab in normalised form as `-1·y ≤ -k`. -/
@[crab] def yGeq (k : Int) : LinCon := { op := .le, terms := [(-1, "y")], const := -k }

/-- `y ≤ k`, exported as `1·y ≤ k`. -/
@[crab] def yLeq (k : Int) : LinCon := { op := .le, terms := [(1, "y")], const := k }

/-- `y = 10` — the asserted condition in block `out`. -/
@[crab] def yEq10 : LinCon := { op := .eq, terms := [(1, "y")], const := 10 }

/-- Block bodies.  The final `_ => []` is what makes this a *total* function,
    as `Cfg` requires: every label naming no block gets an empty body. -/
@[crab] def bodyOf : Label → List Stmt
  | "start"          => [.assign "y" { terms := [], const := 0 }]
  | "loop"           => [.assign "y" { terms := [(1, "y")], const := 1 }]
  | "edge-loop-loop" => [.assume (yLeq 9)]
  | "edge-loop-out"  => [.assume (yGeq 10)]
  | "out"            => [.assert yEq10]
  | _                => []

/-- Successor lists, likewise total. -/
@[crab] def succOf : Label → List Label
  | "start"          => ["loop"]
  | "loop"           => ["edge-loop-loop", "edge-loop-out"]
  | "edge-loop-loop" => ["loop"]
  | "edge-loop-out"  => ["out"]
  | _                => []

/-- The CFG. -/
@[crab] def prog : Cfg := { entry := "start", body := bodyOf, succ := succOf }

/-! ## The invariants (from `--print-invariants-to-json`)

Transcribed verbatim from the JSON.  Crab's `int` domain found, for procedure `bar`:

| block            | exported constraints          | i.e.      |
|------------------|-------------------------------|-----------|
| `start`          | `{"kind":"true"}`             | ⊤         |
| `loop`           | `-y ≤ 0`, `y ≤ 9`             | 0 ≤ y ≤ 9 |
| `edge-loop-loop` | `-y ≤ -1`, `y ≤ 10`           | 1 ≤ y ≤ 10|
| `edge-loop-out`  | `-y ≤ -1`, `y ≤ 10`           | 1 ≤ y ≤ 10|
| `out`            | `-y ≤ -10`, `y ≤ 10`          | y = 10    |
-/

/-- The annotation.  Unknown labels get `Assn.bot`: they are unreachable, and
    the lemma covering unnamed labels proves their obligation without looking
    at the invariant at all. -/
@[crab] def inv : Label → Assn
  | "start"          => Assn.top
  | "loop"           => [[.lin (yGeq 0),  .lin (yLeq 9)]]
  | "edge-loop-loop" => [[.lin (yGeq 1),  .lin (yLeq 10)]]
  | "edge-loop-out"  => [[.lin (yGeq 1),  .lin (yLeq 10)]]
  | "out"            => [[.lin (yGeq 10), .lin (yLeq 10)]]
  | _                => Assn.bot

/-! ## One verification condition per block

Each `theorem` below has a *type* which is an instance of the `VC` schema, and
a *proof* which is one tactic call.  Written out, the obligations are:

  start          ∀ σ, True          →  0 ≤ 0 ≤ 9                  (after y := 0)
  loop           ∀ σ, 0 ≤ y ≤ 9     →  1 ≤ y+1 ≤ 10               (after y := y+1)
  edge-loop-loop ∀ σ, 1 ≤ y ≤ 10    →  (y ≤ 9  → 0 ≤ y ≤ 9)
  edge-loop-out  ∀ σ, 1 ≤ y ≤ 10    →  (y ≥ 10 → 10 ≤ y ≤ 10)
  out            ∀ σ, 10 ≤ y ≤ 10   →  (y = 10 ∧ True)

`start` and `loop` are deterministic, so the weakest precondition is pure
substitution and no quantifier survives.  The two edge blocks gain exactly one
arrow each, from their `assume`.  `out` has no successors, so its postcondition
is `True` and all that remains is the assert's own obligation — an assert both
checks and filters, so it contributes a conjunct rather than an antecedent. -/

theorem vc_start          : VC prog inv "start"          := by crab_vc
theorem vc_loop           : VC prog inv "loop"           := by crab_vc
theorem vc_edge_loop_loop : VC prog inv "edge-loop-loop" := by crab_vc
theorem vc_edge_loop_out  : VC prog inv "edge-loop-out"  := by crab_vc
theorem vc_out            : VC prog inv "out"            := by crab_vc

/-! ## Bundling the VCs

`consecution_of_VC` wants `∀ B, VC prog inv B` — over *every* string.  The five
theorems above cover the named blocks; `VC_of_unknown` covers all the rest at
once.  The case analysis that joins them is mechanical, which is the point: it
is generated, not designed. -/

/-- Every label is one of the five blocks, or names no block at all.

    `by_cases h : B = "start"` splits on a decidable proposition, giving the
    `h` branch and the `¬h` branch.  In the final branch the five negated
    equations sit in the context, and `simp` discharges the side conditions of
    `bodyOf`'s and `succOf`'s catch-all equations from them automatically. -/
theorem label_cases (B : Label) :
    B = "start" ∨ B = "loop" ∨ B = "edge-loop-loop" ∨ B = "edge-loop-out"
      ∨ B = "out" ∨ (prog.body B = [] ∧ prog.succ B = []) := by
  by_cases h1 : B = "start";          · exact .inl h1
  by_cases h2 : B = "loop";           · exact .inr (.inl h2)
  by_cases h3 : B = "edge-loop-loop"; · exact .inr (.inr (.inl h3))
  by_cases h4 : B = "edge-loop-out";  · exact .inr (.inr (.inr (.inl h4)))
  by_cases h5 : B = "out";            · exact .inr (.inr (.inr (.inr (.inl h5))))
  exact .inr (.inr (.inr (.inr (.inr
    ⟨by simp [prog, bodyOf], by simp [prog, succOf]⟩))))

/-- **Every** label's verification condition holds.

    `rcases … with rfl | rfl | …` destructs the disjunction, and each `rfl`
    *substitutes* the equation — so in the first branch the goal literally
    becomes `VC prog inv "start"`, which `vc_start` proves. -/
theorem vc_all (B : Label) : VC prog inv B := by
  rcases label_cases B with rfl | rfl | rfl | rfl | rfl | ⟨hb, hs⟩
  · exact vc_start
  · exact vc_loop
  · exact vc_edge_loop_loop
  · exact vc_edge_loop_out
  · exact vc_out
  · exact VC_of_unknown _ _ _ hb hs

/-! ## The entry obligation -/

/-- Every initial state satisfies the invariant at the entry block.

    Crab claims ⊤ at `start`, so this is immediate — but it is not vacuous in
    general: a domain that inferred something at entry would have to justify it
    against `InitState`. -/
theorem initiation : ∀ σ : State, InitState prog σ → ⟦inv prog.entry⟧ σ := by
  intro σ _
  exact Assn.holds_top σ

/-! ## The assertion obligation -/

/-- At every statement in every block, the block's invariant implies that
    statement's obligation after running the statements before it.

    **One line, and that is the point.** This used to be the longest proof in
    the file: a case split over all six label cases, then — for each — an attempt
    to refute the split `pre ++ s :: post` statement by statement, with only
    block `out` surviving to say anything.

    None of that was necessary. `wpStmt` puts an assert's obligation into the
    precondition as a conjunct, so it is already inside `VC prog inv "out"`,
    which `vc_all` proved above; `chk_of_VC` is the general lemma that takes it
    back out. The work is real, it just is not per-program.

    Kept as a named theorem rather than inlined into `bar_verified` because
    `Walkthrough.lean` refers to it when pulling the chain apart, and because
    naming it keeps the four premises of the argument visible in one file. -/
theorem chk : ∀ (L : Label) (pre : List Stmt) (s : Stmt) (post : List Stmt),
    prog.body L = pre ++ s :: post →
    ∀ σ : State, ⟦inv L⟧ σ → wp pre (fun τ => s.obligation τ) σ :=
  chk_of_VC prog inv vc_all

/-! ## The result -/

/-- **The theorem.**

    In English: *the invariants Crab inferred for procedure `bar` of
    `samples/test-1.crabir` under `-d int` are genuine invariants of the
    program, and the program's assertion can never fail.*

    Read the two halves as:
      * `InvariantOf prog inv` — every state reachable at a block satisfies the
        invariant Crab printed there;
      * `¬ AssertFails prog` — no execution reaches `assert(y == 10)` with `y`
        different from 10.  Crab reported this assert **safe**; this is the
        machine-checked confirmation.

    Trusted for this claim: the Lean semantics of CrabIR (`Semantics.lean` and
    `State.lean`), the transcription of the program above, and Crab's invariant
    export.  Not trusted, because proved: everything else. -/
theorem bar_verified : InvariantOf prog inv ∧ ¬ AssertFails prog :=
  verified prog inv initiation vc_all

end Test1Bar
end Crabber
