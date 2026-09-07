import Crabber.Syntax
/-
# Crabber.State — concrete states, and the meaning of expressions in one

**Trusted.** Nothing here is proved, because these definitions *are* the claim
about what CrabIR means. A bug here would let us "prove" a false invariant.
-/

namespace Crabber

/-- A concrete machine state.

    A record of *total* maps. Two consequences worth spelling out, because both
    are load-bearing:

    * **Total, not partial.** There is no `Option`, so no case analysis for
      "variable not yet assigned" ever appears in a proof. An unread variable
      simply has some unknown value, which matches how Crab sees it: a variable
      absent from the abstract domain is unconstrained.
    * **`Var → Int`, a function.** Not a finite map. We never need to enumerate
      the domain, and updating is just building a new function.

    Only integers appear. A full treatment would carry boolean and array maps
    too; those are left out until the representation question for booleans is
    settled (see the note on statements in `Syntax.lean`). -/
structure State where
  ints : Var → Int

/-- `σ.set x v` is σ with `x` remapped to `v`, everything else untouched.

    Written out by hand rather than imported from a library. It is three lines,
    it lets us state exactly the two rewriting rules below — which is all the
    automation ever uses — and it keeps this development free of any dependency
    beyond Lean core. -/
def State.set (σ : State) (x : Var) (v : Int) : State :=
  { ints := fun y => if y = x then v else σ.ints y }

/-- Reading back the variable you just wrote gives the written value.

    `@[simp]` registers this with the simplifier, so `simp` rewrites
    `(σ.set "y" 0).ints "y"` to `0` automatically. Together with the next lemma
    this is the entire interface to `State.set`: no proof ever has to unfold the
    `if`. -/
@[simp] theorem State.set_same (σ : State) (x : Var) (v : Int) :
    (σ.set x v).ints x = v := by
  -- `simp [State.set]` unfolds the definition; the `if y = x` then has both
  -- sides literally `x`, so the condition is `x = x`, which `simp` closes.
  simp [State.set]

/-- Reading a *different* variable is unaffected by the write. -/
@[simp] theorem State.set_other (σ : State) (x y : Var) (v : Int) (h : y ≠ x) :
    (σ.set x v).ints y = σ.ints y := by
  simp [State.set, h]

/-! ## Meaning of expressions and constraints

These two functions are where syntax becomes arithmetic. `LinExp.eval` returns
an `Int` (a computation); `LinCon.holds` returns a `Prop` (a claim). -/

/-- The value of a linear expression in a state: `Σ coefᵢ * σ(varᵢ) + const`.

    `foldr f init` walks the list right-to-left; starting from `e.const` and
    adding `coef * value` for each term gives exactly the sum above. -/
def LinExp.eval (e : LinExp) (σ : State) : Int :=
  e.terms.foldr (fun t acc => t.1 * σ.ints t.2 + acc) e.const

/-- The left-hand side of a constraint, evaluated: just the `Σ coefᵢ * varᵢ`
    part, with no constant. -/
def LinCon.lhs (c : LinCon) (σ : State) : Int :=
  ({ terms := c.terms, const := 0 } : LinExp).eval σ

/-- What it means for a constraint to hold in a state.

    Note the return type is `Prop`, not `Bool`: this is a *proposition* about σ,
    the thing `omega` will eventually be asked to prove.

    A `Bool`-valued version would be needed to *run* this check as compiled code
    — for instance to ship an invariant checker to a browser — and that is a
    genuinely different design, because a decidable version of implication
    between assertions has to be written and proved sound by hand. This
    development takes the other route: proofs are found at development time by
    tactics, and the kernel checks them. -/
def LinCon.holds (c : LinCon) (σ : State) : Prop :=
  match c.op with
  | .le => c.lhs σ ≤ c.const
  | .lt => c.lhs σ < c.const
  | .eq => c.lhs σ = c.const
  | .ne => c.lhs σ ≠ c.const

end Crabber
