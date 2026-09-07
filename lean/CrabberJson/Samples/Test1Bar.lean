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

At every assert in every block, the invariant at that block's entry must imply
the asserted condition after the statements preceding it. The quantifiers range
over all labels and all ways of splitting a body as `pre ++ assert c :: post`,
so most of the work is showing no such split exists outside block `out`. -/

theorem chk : ∀ (L : Label) (pre : List Stmt) (c : LinCon) (post : List Stmt),
    prog.body L = pre ++ Stmt.assert c :: post →
    ∀ σ : State, ⟦inv L⟧ σ → wp pre (fun τ => c.holds τ) σ := by
  intro L pre c post hsplit σ hI
  by_cases hm : L ∈ labels
  · simp only [labels, List.mem_cons, List.not_mem_nil, or_false] at hm
    rcases hm with rfl | rfl | rfl | rfl | rfl
    -- The blocks are in the order the export lists them, which is the order
    -- `labels` records: edge-loop-loop, edge-loop-out, loop, out, start. Four of
    -- them contain no `assert`, so the split is impossible.
    · simp [prog, bodyTable, table] at hsplit; cases pre <;> simp_all
    · simp [prog, bodyTable, table] at hsplit; cases pre <;> simp_all
    · simp [prog, bodyTable, table] at hsplit; cases pre <;> simp_all
    -- Block `out`: the only real case, and `pre` must be empty.
    · simp [prog, bodyTable, table] at hsplit
      cases pre with
      | nil =>
          -- `hsplit` becomes "the asserted constraint is `c`, and nothing
          -- follows it".
          simp at hsplit
          obtain ⟨hc, -⟩ := hsplit
          subst hc
          simp [inv, invTable, table, Assn.holds, Conj.holds, LinCon.holds,
                LinCon.lhs, LinExp.eval] at hI ⊢
          omega
      | cons p ps => simp at hsplit
    · simp [prog, bodyTable, table] at hsplit; cases pre <;> simp_all
  -- A label naming no block has an empty body, which contains no assert.
  · have hb : prog.body L = [] := by
      show table [] bodyTable L = []
      exact table_not_mem [] bodyTable L (body_keys ▸ hm)
    rw [hb] at hsplit
    cases pre <;> simp at hsplit

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
  verified prog inv initiation vc_all chk

end Test1Bar
end CrabberJson
