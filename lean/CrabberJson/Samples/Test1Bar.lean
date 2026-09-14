import CrabberJson.Elab
/-
# `samples/test-1.crabir`, cfg `bar`, proved from the JSON export

The same result as the hand-transcribed `Crabber.Samples.Test1Bar`, with the
program and the invariants **read from Crab's export** instead of typed in.

    build/crabber samples/test-1.crabir -d int --print-invariants-to-json \
        lean/CrabberJson/Samples/test-1.json

The source program is a counting loop:

    start: y := 0            goto loop
    loop:  y := y + 1        if (y <= 9) goto loop else goto out
    out:   assert(y == 10)

The CFG below is the one Crab **analysed**, not the source text: the conditional
has been compiled into the two `edge-loop-*` blocks carrying the guards, which is
why the export walks the analyser's final graph.

Everything specific to this program is the one `crab_program` line. What follows
is the same for every program of this shape, which is the point: the per-program
artifact is data, and the proofs below are a fixed recipe.
-/

namespace CrabberJson
namespace Test1Bar

open Crabber

/-! ## The program and the invariants

Reads `CrabberJson/Samples/test-1.json` while this file is elaborated, checks that reading
it is faithful to the document, and defines `bodyTable`, `succTable`,
`invTable`, `labels`, `prog` and `inv`. Nothing became source text on the way. -/

crab_program "CrabberJson/Samples/test-1.json" cfg "bar"

/-! ## The per-block obligations

`vc_all_of_blocks` reduces "every label's obligation holds" to "every label *in
the block list*", which is a finite check. Its two side conditions say the
tables and `labels` agree about which blocks exist — true by construction, since
the loader builds all three from the same list, and provable by `rfl` because
both sides are literals. -/

theorem body_keys : bodyTable.map Prod.fst = labels := rfl
theorem succ_keys : succTable.map Prod.fst = labels := rfl

/-- Every label's verification condition.

    The five blocks are discharged by `crab_vc` — unfold to arithmetic, call
    `omega` — and every other string by `table_not_mem`, which says a label the
    tables do not mention gets the empty body and no successors. -/
theorem vc_all : ∀ B : Label, VC prog inv B := by
  refine vc_all_of_blocks prog inv labels ?_ ?_ ?_
  -- `prog.body` *is* `table [] bodyTable`, but `show` is needed to make the
  -- projection through the structure literal explicit before applying the lemma.
  · intro B h
    show table [] bodyTable B = []
    exact table_not_mem [] bodyTable B (body_keys ▸ h)
  · intro B h
    show table [] succTable B = []
    exact table_not_mem [] succTable B (succ_keys ▸ h)
  · intro B hB
    simp only [labels, List.mem_cons, List.not_mem_nil, or_false] at hB
    rcases hB with rfl | rfl | rfl | rfl | rfl <;> crab_vc

/-! ## The entry obligation -/

/-- Every initial state satisfies the invariant at the entry block. Crab claims
    ⊤ at `start`, so this is immediate — though not vacuous in general. -/
theorem initiation : ∀ σ : State, InitState prog σ → ⟦inv prog.entry⟧ σ := by
  intro σ _
  simp only [prog, inv, invTable, table, if_pos]
  exact Assn.holds_top σ

/-! ## The assertion obligation

At every statement in every block, the invariant at that block's entry must imply
that statement's obligation after the statements preceding it. Where the
statement is not an assert the obligation is `True`.

This used to be the longest proof in the file: a case split over the five
blocks, then an attempt to refute the split `pre ++ s :: post` in each of the
four that contain no assert. All of it was redundant. `wpStmt` puts an assert's
obligation into the precondition as a conjunct, so it is already inside the
verification conditions `vc_all` proved above, and `chk_of_VC` is the general
lemma that takes it back out.

The generated form of this file (`crab_verify`) no longer emits anything here at
all, for the same reason. -/

theorem chk : ∀ (L : Label) (pre : List Stmt) (s : Stmt) (post : List Stmt),
    prog.body L = pre ++ s :: post →
    ∀ σ : State, ⟦inv L⟧ σ → wp pre (fun τ => s.obligation τ) σ :=
  chk_of_VC prog inv vc_all

/-! ## The result -/

/-- **The theorem.**

    *The invariants Crab inferred for cfg `bar` of `samples/test-1.crabir` under
    `-d int` are genuine invariants of the program, and the program's assertion
    can never fail* — with the program and the invariants taken from Crab's own
    JSON export rather than transcribed by hand.

    Trusted for this claim: the Lean semantics of CrabIR, Crab's exporter, and
    the JSON reader — whose faithfulness to the document was checked when this
    file was elaborated. Not trusted, because proved: everything else. -/
theorem bar_verified : InvariantOf prog inv ∧ ¬ AssertFails prog :=
  verified prog inv initiation vc_all

end Test1Bar
end CrabberJson
