import Crabber.WP
/-
# Crabber.VC — the per-block obligation, and the adapter to consecution

This file is the seam of the whole development. Above it everything is about the
transition system; below it everything is arithmetic. Both theorems are proved
**once**, for every program and every annotation — no generated file ever redoes
this work.
-/

namespace Crabber

/-- **`VC P I B` — the verification condition for block `B`.**

    In English: *assume the invariant Crab claims at `B`'s entry; then running
    `B`'s straight-line body must land in a state satisfying the invariant Crab
    claims at the entry of **every** successor of `B`.*

    Note this is a `def` returning `Prop`, not a `theorem`: it **asserts
    nothing**. It is a statement *schema* indexed by a block — a function from
    labels to statements. `VC prog inv "loop"` is a `Prop`; a separate `theorem`
    supplies its proof. (`Monotone f` and `Function.Injective f` are the same
    idiom.)

    Naming it earns three specific things:
      1. it can be **quantified over** — `consecution_of_VC` below takes
         `∀ B, VC P I B` as a hypothesis, which is unsayable without a name;
      2. it gives the automation a single fixed **head symbol** to unfold;
      3. it lets `VC_of_unknown` prove a whole class of blocks at once.

    Two details of the postcondition:
      * `∀ B' ∈ P.succ B, …` is a **bounded quantifier**, not a folded
        conjunction over a list. Then "instantiate at the successor actually
        taken" is plain function application in `consecution_of_VC`, and a block
        with no successors degenerates to `True` for free.
      * putting the successor quantifier *inside* the VC is what makes the
        obligations **per-block** rather than per-edge: `n` blocks, `n`
        obligations, whatever the edge count.

    Degenerate cases fall out with no special handling. A block Crab marked
    unreachable gets `False` as its invariant, so its own obligation holds
    vacuously and the burden shifts to its predecessors, which must then show it
    cannot be entered — exactly the claim Crab is making there. -/
def VC (P : Cfg) (I : Label → Assn) (B : Label) : Prop :=
  ∀ σ : State, ⟦I B⟧ σ → wp (P.body B) (fun τ => ∀ B' ∈ P.succ B, ⟦I B'⟧ τ) σ

/-- **Labels naming no block are free.**

    `∀ B, VC P I B` ranges over *every* `String`, not just the block names of
    `P`, because labels are strings. Since `Cfg.body` and `Cfg.succ` are total
    functions defaulting to `[]`, all those labels have an empty body and no
    successors, and their obligation is trivial: `wp [] Q = Q`, and the
    postcondition is a vacuous bounded quantifier.

    Proving it here once is what keeps the per-program bundle finite. -/
theorem VC_of_unknown (P : Cfg) (I : Label → Assn) (B : Label)
    (hb : P.body B = []) (hs : P.succ B = []) : VC P I B := by
  -- Take the state and discard the invariant hypothesis (`_` names it away).
  intro σ _
  -- Rewriting with `hb` empties the body, so `wp` is the identity; rewriting
  -- with `hs` empties the successor list, so the goal is `∀ B' ∈ [], …`.
  simp [hb, hs]

/-- A label absent from the table gets the default.

    The companion to `table`'s definition, and what makes the bundling lemma
    below program-independent. -/
theorem table_not_mem {α : Type} (dflt : α) (tbl : List (Label × α)) (B : Label)
    (h : B ∉ tbl.map Prod.fst) : table dflt tbl B = dflt := by
  induction tbl with
  | nil => rfl
  | cons p rest ih =>
      obtain ⟨k, v⟩ := p
      -- `B` is neither this key nor any key in the rest.
      simp only [List.map_cons, List.mem_cons, not_or] at h
      simp [table, h.1, ih h.2]

/-- **Bundling the per-block obligations into the one `consecution_of_VC` wants.**

    `∀ B, VC P I B` quantifies over every `String`, but a program has finitely
    many blocks. This splits that quantifier once and for all: a label either
    names a block, and is covered by the finitely many obligations proved for
    the program, or it does not, and `VC_of_unknown` applies.

    Proving it here is what keeps a generated file free of the `by_cases` chain
    over label literals that a hand-written one needs. The generated file
    supplies its list of labels and one `crab_vc` per block; the case analysis
    joining them is this lemma, written once. -/
theorem vc_all_of_blocks (P : Cfg) (I : Label → Assn) (labels : List Label)
    (hbody : ∀ B, B ∉ labels → P.body B = [])
    (hsucc : ∀ B, B ∉ labels → P.succ B = [])
    (h : ∀ B ∈ labels, VC P I B) : ∀ B, VC P I B := by
  intro B
  by_cases hm : B ∈ labels
  · exact h B hm
  · exact VC_of_unknown _ _ _ (hbody B hm) (hsucc B hm)

/-- **`consecution_of_VC` — the adapter lemma.**

    In English: *if every block's verification condition holds, then the
    annotation is preserved by every single step of the machine.*

    This is the bridge between two statement shapes that cannot be bent to meet
    each other. The soundness meta-theorem needs a statement about `Step` —
    right for induction over reachability, opaque to `omega`. What a frontend can
    generate is `VC B` — block-local, quantifier-light arithmetic — right for
    `omega`, useless to the meta-theorem.

    Isolating the bridge in one lemma means:
      * it is **program-independent**, so no generated file re-derives `Step`
        inversion or applies `wp_sound`;
      * it is the **automation boundary**;
      * it **localises the coupling to the semantics** — once procedure calls
        turn `Step` into an inductive with a call stack, this proof is the only
        thing that changes. -/
theorem consecution_of_VC (P : Cfg) (I : Label → Assn) (hvc : ∀ B, VC P I B) :
    ∀ (L : Label) (σ : State) (L' : Label) (σ' : State),
      ⟦I L⟧ σ → Step P (L, σ) (L', σ') → ⟦I L'⟧ σ' := by
  -- `∀` ⇒ take the labels and states arbitrary; `→` ⇒ assume the two premises.
  intro L σ L' σ' h₁ h₂
  -- `Step` is definitionally a conjunction, so we can split it:
  --   hsucc : L' ∈ P.succ L        (L' really is a successor)
  --   hexec : Exec (P.body L) σ σ' (the body really runs σ to σ')
  obtain ⟨hsucc, hexec⟩ := h₂
  -- The block's own verification condition, fed the invariant at L.
  -- This is a statement purely about the *pre*-state σ.
  have hwp := hvc L σ h₁
  -- `wp_sound` trades it, together with the execution, for a statement about
  -- the *post*-state σ'. This is where the `Exec` premise is consumed.
  have hpost := wp_sound hwp hexec
  -- `hpost : ∀ B' ∈ P.succ L, ⟦I B'⟧ σ'`. Applying it to `L'` and the proof
  -- that `L'` is a successor is *literally function application* — the payoff
  -- of using a bounded quantifier rather than a folded conjunction.
  exact hpost L' hsucc

/-- **`chk_of_VC` — the assertion obligations come free with the VCs.**

    In English: *if every block's verification condition holds, then at every
    assert in every block the invariant at that block's entry already implies the
    asserted condition.*

    This is the second hypothesis `assert_safe` wants, and it turns out not to be
    a separate hypothesis at all. `wpStmt` puts an assert's obligation into the
    precondition as a conjunct, so it is inside `VC` already; `wp_split` is the
    lemma that pulls it back out. All that is left here is to rewrite the block's
    body into the split the caller asked about.

    Proving it once, here, is what keeps it out of generated files. Before this
    lemma, a per-program file carried a `chk` theorem of its own — a case split
    over labels, then a statement-by-statement peel of `pre` for each one. That
    script existed only to re-derive, per program, something true of every
    program.

    **What it rests on.** The `∧` in `wpStmt`'s assert clause, and nothing else.
    Under the assume-flavoured `→` reading weighed in `Samples/Test1Foo.lean` the
    obligation would not be in the VC to extract, this lemma would be false, and
    generated files would need their `chk` back. That is the price of the
    simplification, and it is confined to this lemma and `verified`. -/
theorem chk_of_VC (P : Cfg) (I : Label → Assn) (hvc : ∀ B, VC P I B) :
    ∀ (L : Label) (pre : List Stmt) (s : Stmt) (post : List Stmt),
      P.body L = pre ++ s :: post →
      ∀ σ : State, ⟦I L⟧ σ → wp pre (fun τ => s.obligation τ) σ := by
  intro L pre s post hsplit σ hI
  -- The block's own verification condition, fed the invariant at L.
  have hwp := hvc L σ hI
  -- Replace the body by the split the caller named, so `wp_split` applies.
  rw [hsplit] at hwp
  exact wp_split pre s post _ σ hwp

end Crabber
