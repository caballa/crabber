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

    **One map per type, all indexed by the same `Var`.** CrabIR's namespaces are
    disjoint, so a name occurring in a boolean statement is a boolean variable and
    `ints` is simply never asked about it. Booleans are `Bool`, not integers
    confined to `{0,1}` — the argument is in `Syntax.lean`, and the consequence
    visible here is that no well-formedness side condition relates the two maps.
    They are independent, which is why writing one never disturbs the other.

    An array map is still absent, and will be the next field. -/
structure State where
  ints  : Var → Int
  bools : Var → Bool

/-- `σ.set x v` is σ with the *integer* `x` remapped to `v`, everything else
    untouched.

    Written out by hand rather than imported from a library. It is three lines,
    it lets us state exactly the rewriting rules below — which is all the
    automation ever uses — and it keeps this development free of any dependency
    beyond Lean core.

    `{ σ with … }` is record-update notation: it copies every field not mentioned,
    so the boolean store comes through unchanged. -/
def State.set (σ : State) (x : Var) (v : Int) : State :=
  { σ with ints := fun y => if y = x then v else σ.ints y }

/-- `σ.setBool x b` is σ with the *boolean* `x` remapped to `b`. -/
def State.setBool (σ : State) (x : Var) (b : Bool) : State :=
  { σ with bools := fun y => if y = x then b else σ.bools y }

/-- Reading back the variable you just wrote gives the written value.

    `@[simp]` registers this with the simplifier, so `simp` rewrites
    `(σ.set "y" 0).ints "y"` to `0` automatically. Together with the three lemmas
    below this is the entire interface to the update functions: no proof ever has
    to unfold the `if`. -/
@[simp] theorem State.set_same (σ : State) (x : Var) (v : Int) :
    (σ.set x v).ints x = v := by
  -- `simp [State.set]` unfolds the definition; the `if y = x` then has both
  -- sides literally `x`, so the condition is `x = x`, which `simp` closes.
  simp [State.set]

/-- Reading a *different* variable is unaffected by the write. -/
@[simp] theorem State.set_other (σ : State) (x y : Var) (v : Int) (h : y ≠ x) :
    (σ.set x v).ints y = σ.ints y := by
  simp [State.set, h]

/-- The boolean counterpart of `set_same`. -/
@[simp] theorem State.setBool_same (σ : State) (x : Var) (b : Bool) :
    (σ.setBool x b).bools x = b := by
  simp [State.setBool]

/-- The boolean counterpart of `set_other`. -/
@[simp] theorem State.setBool_other (σ : State) (x y : Var) (b : Bool) (h : y ≠ x) :
    (σ.setBool x b).bools y = σ.bools y := by
  simp [State.setBool, h]

/-! ### The two stores do not interfere

Both of these are true by `rfl` — `State.set` is a record update that does not
mention `bools`, so the projection reduces without any rewriting at all. They are
`@[simp]` lemmas anyway, and not because `simp` could not manage otherwise: they
are what lets an integer assignment be *skipped over* by a boolean goal without
first unfolding `State.set` and re-deriving a disequality on names. With them,
`(σ.set "y" 3).bools "b"` becomes `σ.bools "b"` in one step, whatever the names
are — and unlike `set_other` there is no side condition, because the
interference is impossible rather than merely absent. -/

@[simp] theorem State.set_bools (σ : State) (x : Var) (v : Int) (y : Var) :
    (σ.set x v).bools y = σ.bools y := rfl

@[simp] theorem State.setBool_ints (σ : State) (x : Var) (b : Bool) (y : Var) :
    (σ.setBool x b).ints y = σ.ints y := rfl

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

/-! ### The one place a constraint must be a `Bool`

`b := (x == 10)` writes a *value* into the boolean store, so it needs a `Bool`,
not the `Prop` above. The two are related by `check_eq_true` below, which is the
only bridge between them and the only lemma the automation uses.

Written out rather than obtained as `decide (c.holds σ)` through a `Decidable`
instance. Both compute the same answer, but a derived instance is a term the
simplifier has to unfold through a `match` on the operator before anything can
happen, whereas the equation lemmas of this `def` fire directly. Since every
goal about a boolean assignment goes through it, predictability wins. -/

/-- Whether a constraint holds, as a `Bool`. -/
def LinCon.check (c : LinCon) (σ : State) : Bool :=
  match c.op with
  | .le => c.lhs σ ≤ c.const
  | .lt => c.lhs σ < c.const
  | .eq => c.lhs σ = c.const
  | .ne => c.lhs σ ≠ c.const

/-- The bridge: computing `true` and holding are the same thing.

    `@[simp]` in this direction — `check … = true` rewrites to `holds` — because
    goals arrive with the `Bool` (it came out of the state) and `omega` wants the
    `Prop`. -/
@[simp] theorem LinCon.check_eq_true (c : LinCon) (σ : State) :
    c.check σ = true ↔ c.holds σ := by
  -- One case per operator; in each, `simp` reduces the decidable comparison
  -- coerced to `Bool` back to the proposition it decides.
  cases h : c.op <;> simp [LinCon.check, LinCon.holds, h]

/-- The negative half. Needed as its own lemma, not derivable by `simp` from the
    one above: `b = false` is not syntactically the negation of `b = true`, and
    Crab exports `b0 = 0` as readily as `b0 = 1`. -/
@[simp] theorem LinCon.check_eq_false (c : LinCon) (σ : State) :
    c.check σ = false ↔ ¬ c.holds σ := by
  cases h : c.op <;> simp [LinCon.check, LinCon.holds, h]

end Crabber
