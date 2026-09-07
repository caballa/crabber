import Crabber.State
/-
# Crabber.Assn — invariants as data, and what they mean

The assertion language is a **disjunction of conjunctions of linear
constraints** — exactly what every Crab abstract domain can export, via its
"convert to a disjunctive linear constraint system" operation. Keeping it as
*data* rather than as a Lean predicate matters for two reasons: it arrives from
a parser, and we want to print it back verbatim when a proof obligation fails.

**Trusted.** The meaning function below is our claim about what Crab's exported
constraints mean.
-/

namespace Crabber

/-- A conjunction of linear constraints: one "disjunct" in the export. -/
abbrev Conj := List LinCon

/-- An invariant: a disjunction of conjunctions, read as "or of ands". -/
abbrev Assn := List Conj

/-- A conjunction holds when *every* constraint in it holds.

    `∀ c ∈ k, …` is Lean's bounded quantifier, sugar for `∀ c, c ∈ k → …`.
    Writing it this way rather than folding `∧` over the list is what makes the
    degenerate cases below come out right with no special handling. -/
def Conj.holds (k : Conj) (σ : State) : Prop := ∀ c ∈ k, c.holds σ

/-- An invariant holds when *some* disjunct holds. -/
def Assn.holds (A : Assn) (σ : State) : Prop := ∃ k ∈ A, Conj.holds k σ

/-- Notation `⟦A⟧ σ` — "state σ satisfies invariant A".

    The bridge from invariant *data* to an actual proposition about a state. -/
notation:max "⟦" A "⟧" => Assn.holds A

/-! ## The two degenerate invariants

Crab's JSON marks "everything" and "nothing" explicitly, because an empty list
is ambiguous on the wire. In Lean no such ambiguity exists — the list encoding
gives both, and each falls out of the definitions above with no special case. -/

/-- Bottom: the invariant of an unreachable block. Crab prints these rather than
    omitting them, so that a block being unreachable is a claim we can check.
    No disjuncts, so `∃ k ∈ [], …` is false. -/
def Assn.bot : Assn := []

/-- Top: no information. One disjunct, itself empty, so `∃ k ∈ [[]], ∀ c ∈ [], …`
    reduces to `∀ c ∈ [], …`, vacuously true. -/
def Assn.top : Assn := [[]]

/-- Bottom really is unsatisfiable.

    Stated so that the reasoning about unreachable blocks is a fact in Lean
    rather than a comment: a block Crab marked unreachable gets `False` as its
    invariant, so its own proof obligation holds vacuously and the burden shifts
    to its *predecessors*, which must then show the block cannot be entered —
    which is exactly the claim Crab is making there. -/
theorem Assn.not_holds_bot (σ : State) : ¬ ⟦Assn.bot⟧ σ := by
  -- `rintro` introduces the hypothesis and destructs it in one step:
  -- a proof of `∃ k ∈ [], …` would have to supply a member of `[]`.
  rintro ⟨k, hk, -⟩
  -- `simp at hk` reduces `k ∈ []` to `False`, closing the goal.
  simp [Assn.bot] at hk

/-- Top really is satisfied by every state. -/
theorem Assn.holds_top (σ : State) : ⟦Assn.top⟧ σ := by
  -- Provide the witness `[]` for the existential; the inner `∀ c ∈ []` is then
  -- vacuous. `⟨_, _, _⟩` is anonymous-constructor notation: it builds the
  -- ∃-proof from its parts.
  exact ⟨[], by simp [Assn.top], by simp [Conj.holds]⟩

end Crabber
