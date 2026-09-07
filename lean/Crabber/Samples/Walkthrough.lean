import Crabber.Samples.Test1Bar
/-
# Crabber.Walkthrough — `Test1Bar` proved again, one step at a time

`Test1Bar.lean` proves each block with `by crab_vc`, a single macro.  That
is what you want in a *generated* file, and useless for learning: stepping into
it shows the goal before and `True` after, with nothing in between.

Here the macro is **unrolled**, so you can watch the machinery run.

## How to use it

1. Open the InfoView: command palette → **"Lean 4: Infoview: Toggle"** (⌃⇧↩).
2. Put the cursor at the **end of a tactic line** to see the state *after* that
   tactic.  Arrow down one line at a time.
3. Hover any identifier for its docstring; **F12** jumps to its definition.

**Start with block `start` below.**  It is the only one whose goal fits on a
screen at every stage.

Everything here is an `example` (an anonymous theorem), so nothing clashes with
`Test1Bar.lean` and nothing depends on it.

This file is **not** imported by `Crabber.lean` and is not part of the committed
library — it is a local teaching copy.  So `lake build` does *not* check it.
After changing anything in the library, check it by hand:

    lake env lean Crabber/Samples/Walkthrough.lean
-/

namespace Crabber
namespace Walkthrough

open Test1Bar

set_option linter.unusedSimpArgs false

/-! ## Block `start` — `y := 0`, one successor `loop`

**What we must show.**  Crab claims nothing at `start` (⊤) and claims
`0 ≤ y ≤ 9` at `loop`.  So: after running `y := 0` from *any* state, the result
must satisfy `0 ≤ y ≤ 9`.  Since `y` is 0 afterwards, that is `0 ≤ 0 ≤ 9`.

Each line below is annotated with the goal it *produces*.  Follow along in the
InfoView. -/
example : VC prog inv "start" := by
  -- Goal:  ⊢ VC prog inv "start"
  --
  -- `VC` is a `def`, so `intro` sees through it without any unfolding step:
  -- it is *definitionally* `∀ σ, ⟦inv "start"⟧ σ → wp … σ`.
  -- The underscore in `_hpre` says "I know this is unused" — and it is:
  -- Crab claims ⊤ at the entry, so the hypothesis carries no information.
  intro σ _hpre
  -- σ : State
  -- _hpre : ⟦inv "start"⟧ σ
  -- ⊢ wp (prog.body "start") (fun τ => ∀ B' ∈ prog.succ "start", ⟦inv B'⟧ τ) σ

  -- Look up the block in the CFG: what are its statements, and its successors?
  simp only [prog, bodyOf, succOf]
  -- ⊢ wp [Stmt.assign "y" { terms := [], const := 0 }]
  --      (fun τ => ∀ B' ∈ ["loop"], ⟦inv B'⟧ τ) σ

  -- **The substitution step.**  `wp` walks the body backwards.  The assignment
  -- becomes `σ.set "y" (…)`: no quantifier is introduced, the state is simply
  -- rewritten.  Forward reasoning would have needed `∃ y_old` here instead.
  simp only [wp, wpStmt]
  -- ⊢ ∀ B' ∈ ["loop"], ⟦inv B'⟧ (σ.set "y" ({ terms := [], const := 0 }.eval σ))

  -- Discharge the successor quantifier.  `simp only [List.mem_singleton]` turns
  -- `B' ∈ ["loop"]` into `B' = "loop"`; `rintro B' rfl` then introduces `B'`
  -- and *substitutes* it away using that equation.  (`rfl` inside `rintro` means
  -- "this hypothesis is an equation — use it to rewrite".)
  --
  -- Do this BEFORE unfolding `inv`: while `B'` is still a variable, `inv B'`
  -- cannot reduce, and unfolding it would dump the entire `match` into the goal.
  simp only [List.mem_singleton]
  rintro B' rfl
  -- ⊢ ⟦inv "loop"⟧ (σ.set "y" ({ terms := [], const := 0 }.eval σ))

  -- Now the label is a literal, so Crab's invariant for it can be looked up.
  -- This is the exported data: `-1·y ≤ -0` and `1·y ≤ 9`.
  simp only [inv, yGeq, yLeq]
  -- ⊢ ⟦[[{op := le, terms := [(-1, "y")], const := -0},
  --      {op := le, terms := [(1, "y")],  const := 9}]]⟧ (σ.set "y" …)

  -- `⟦·⟧` is ⋁⋀: "some disjunct, all of whose constraints hold".
  simp only [Assn.holds, Conj.holds]
  -- ⊢ ∃ k, k ∈ [[…, …]] ∧ ∀ c ∈ k, c.holds (σ.set "y" …)

  -- Give the constraints their arithmetic meaning: `LinCon.holds` matches on
  -- the operator, `LinExp.eval` folds `Σ coef * σ(var) + const`.
  simp only [LinCon.holds, LinCon.lhs, LinExp.eval]
  -- Same shape, but `c.holds` has become a `match c.op with | le => … ≤ …`.

  -- Finish: pick the single disjunct, evaluate the two folds, and fire
  -- `State.set_same` to turn `(σ.set "y" 0).ints "y"` into `0`.  What is left is
  -- `0 ≤ 0 ∧ 0 ≤ 9`, which `simp` closes by computation — no `omega` needed.
  simp

/-! ## The same proof, instrumented with `trace_state`

If the InfoView keeps showing "Goals accomplished!", your cursor is past the end
of the proof — it always reports the state *at the cursor*.  This copy avoids
the problem entirely: `trace_state` **prints** the goal as a message, so all
eight states appear in the InfoView's *Messages* section (and in the Problems
panel) no matter where the cursor sits.

Click anywhere in this example and read the messages top to bottom.  Delete the
`trace_state` lines once cursor-stepping feels natural — it is the better tool
for real work, because it shows the state interactively rather than as a dump. -/
example : VC prog inv "start" := by
  trace_state                          -- ⊢ VC prog inv "start"
  intro σ _hpre
  trace_state                          -- the ∀σ and the hypothesis appear
  simp only [prog, bodyOf, succOf]
  trace_state                          -- the block's statements and successors
  simp only [wp, wpStmt]
  trace_state                          -- σ.set "y" … appears: substitution
  simp only [List.mem_singleton]
  rintro B' rfl
  trace_state                          -- B' is now the literal "loop"
  simp only [inv, yGeq, yLeq]
  trace_state                          -- Crab's exported constraints, as data
  simp only [Assn.holds, Conj.holds]
  trace_state                          -- ⋁⋀ becomes ∃/∀ over lists
  simp only [LinCon.holds, LinCon.lhs, LinExp.eval]
  trace_state                          -- and now it is arithmetic
  simp

/-! ## Block `loop` — `y := y + 1`, **two** successors

The interesting one.  This time we reduce the *hypothesis* first, so you can
read what Crab claims at the block entry before looking at the goal.

The `rintro B' (rfl | rfl)` splits into **two goals**, one per successor.  That
is the point of the VC: the body must establish every successor's invariant,
because which edge gets taken is not decided until the guard runs, inside the
edge block. -/
example : VC prog inv "loop" := by
  intro σ hpre
  -- Reduce the precondition to arithmetic: `hpre : 0 ≤ σ.ints "y" ≤ 9`.
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs,
             LinExp.eval] at hpre
  simp at hpre
  -- Now the goal, same recipe as `start`.
  simp only [prog, bodyOf, succOf]
  simp only [wp, wpStmt]
  simp only [List.mem_cons, List.mem_singleton, List.not_mem_nil, or_false]
  -- ⊢ ∀ B', (B' = "edge-loop-loop" ∨ B' = "edge-loop-out") → ⟦inv B'⟧ (σ.set "y" …)
  rintro B' (rfl | rfl)
  · -- successor `edge-loop-loop`: must establish `1 ≤ y ≤ 10`
    simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs, LinExp.eval]
    simp
    -- hpre : 0 ≤ σ.ints "y" ∧ σ.ints "y" ≤ 9
    -- ⊢     1 ≤ σ.ints "y" + 1 ∧ σ.ints "y" + 1 ≤ 10
    omega
  · -- successor `edge-loop-out`: the same invariant, proved again
    simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs, LinExp.eval]
    simp
    omega

/-! ## Block `edge-loop-loop` — `assume(y ≤ 9)`, successor `loop`

Here an **arrow** appears: `wp (assume c) Q = ⟦c⟧ → Q`, so the guard becomes the
antecedent of an implication and `intro hguard` assumes it.

That arrow is the only one in the goal, and it comes from the `assume` in the
*program*.  Nothing here comes from the transition relation — `wp_sound`
consumed all of that once, in `WP.lean`. -/
example : VC prog inv "edge-loop-loop" := by
  intro σ hpre
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs,
             LinExp.eval] at hpre
  simp at hpre
  simp only [prog, bodyOf, succOf]
  simp only [wp, wpStmt]
  -- Give the guard its arithmetic meaning, then assume it.
  simp only [yLeq, LinCon.holds, LinCon.lhs, LinExp.eval]
  simp only [List.foldr]
  intro hguard
  -- hguard : 1 * σ.ints "y" + 0 ≤ 9
  simp only [List.mem_singleton]
  rintro B' rfl
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs, LinExp.eval]
  simp
  omega

/-! ## Block `edge-loop-out` — `assume(y ≥ 10)`, successor `out`

The same shape with the negated guard.  Watch how the loop exit is *proved*:
from `1 ≤ y ≤ 10` and `y ≥ 10` we get `y = 10`, which is exactly the invariant
Crab printed at `out`.  This VC is why the assertion there can be discharged. -/
example : VC prog inv "edge-loop-out" := by
  intro σ hpre
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs,
             LinExp.eval] at hpre
  simp at hpre
  simp only [prog, bodyOf, succOf]
  simp only [wp, wpStmt]
  simp only [yGeq, LinCon.holds, LinCon.lhs, LinExp.eval]
  simp only [List.foldr]
  intro hguard
  simp only [List.mem_singleton]
  rintro B' rfl
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs, LinExp.eval]
  simp
  omega

/-! ## Block `out` — `assert(y = 10)`, **no** successors

Two degenerate cases at once, both falling out with no special handling:

* `succ "out" = []`, so the postcondition `∀ B' ∈ [], …` is vacuously `True`;
* an assert both obligates and filters, so `wp (assert c) Q = ⟦c⟧ ∧ Q` and an
  `∧` appears rather than an arrow.

`refine ⟨?_, ?_⟩` splits that conjunction into its two halves: the assert's own
obligation, and the (trivial) postcondition.  Note the assert is **not** an
antecedent — an assert we cannot discharge is a failure, not a free pass. -/
example : VC prog inv "out" := by
  intro σ hpre
  simp only [inv, yGeq, yLeq, Assn.holds, Conj.holds, LinCon.holds, LinCon.lhs,
             LinExp.eval] at hpre
  simp at hpre
  -- hpre : σ.ints "y" = 10   (from `10 ≤ y ≤ 10`)
  simp only [prog, bodyOf, succOf]
  simp only [wp, wpStmt]
  refine ⟨?_, ?_⟩
  · -- the assert's obligation: `y = 10`
    simp only [yEq10, LinCon.holds, LinCon.lhs, LinExp.eval]
    simp
    omega
  · -- the postcondition: `∀ B' ∈ [], …`, vacuous
    simp

/-! ## The entry obligation

The other premise of `inductive_sound`.  Crab claims ⊤ at `start`, so this is
immediate — but it is not vacuous in general: a domain that inferred something
at entry would have to justify it against `InitState`. -/
example : ∀ σ : State, InitState prog σ → ⟦inv prog.entry⟧ σ := by
  intro σ _
  simp only [prog, inv, Assn.top]
  simp only [Assn.holds, Conj.holds]
  -- ⊢ ∃ k ∈ [[]], ∀ c ∈ k, …
  -- Supply the witness `[]`; the inner `∀` is then over the empty list.
  exact ⟨[], by simp, by simp⟩

/-! ## The whole program, assembled

`Test1Bar.lean` finishes in one line — `verified prog inv initiation vc_all
chk` — because `verified` chains the meta-theorems for you.  Here that chain is
**pulled apart into named steps**: put the cursor after each `have` and read
what has been established so far.

Read top to bottom as the whole argument:

  `vc_all`             every block's VC holds                     ← arithmetic
  `consecution_of_VC`  therefore the annotation survives a step    ← the adapter
  `inductive_sound`    therefore it holds at every reachable state ← Park induction
  `assert_safe`        therefore no assert can fail                ← the payoff

Note where the seam is: `hcons` is the first statement that mentions `Step`.
Everything above it is arithmetic; everything below is about the transition
system.  That is the automation boundary of the design, visible as one line. -/
example : InvariantOf prog inv ∧ ¬ AssertFails prog := by
  have hvc : ∀ B : Label, VC prog inv B := vc_all
  have hcons : ∀ (L : Label) (σ : State) (L' : Label) (σ' : State),
      ⟦inv L⟧ σ → Step prog (L, σ) (L', σ') → ⟦inv L'⟧ σ' :=
    consecution_of_VC prog inv hvc
  have hinv : InvariantOf prog inv :=
    inductive_sound prog inv initiation hcons
  have hsafe : ¬ AssertFails prog :=
    assert_safe prog inv hinv chk
  exact ⟨hinv, hsafe⟩

end Walkthrough
end Crabber
