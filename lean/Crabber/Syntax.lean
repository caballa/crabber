/-
# Crabber.Syntax — the deeply embedded CrabIR program

"Deeply embedded" means a CrabIR program is *data* in Lean: an ordinary
inductive datatype we can pattern-match on, not a Lean program. That is what
lets the weakest-precondition calculus walk over a block body, and what lets a
frontend emit a program as a plain term.

Everything here mirrors the JSON that `crabber --cfg-to-json` produces.
-/

namespace Crabber

/-- A block name.

    Plain `String`, matching Crab's own labels. That includes the blocks Crab
    synthesises rather than the ones you wrote: a conditional is compiled into
    dedicated `edge-<src>-<dst>` blocks carrying the guard, and an artificial
    `___exit` block may be added. We model the graph Crab *analysed*, so those
    names have to be representable.

    Strings were chosen over a per-program enumeration so that one `Cfg` type
    serves every program. The worry was that looking a label up would then be
    expensive to reduce; in practice `simp` handles literal string matches
    without difficulty.

    `abbrev` (rather than `def`) makes this a *reducible* alias: Lean unfolds it
    silently, so a `Label` is interchangeable with a `String` everywhere. -/
abbrev Label := String

/-- A variable name. CrabIR is strongly typed with disjoint namespaces for
    integers, booleans and arrays, so a name alone identifies a variable and no
    sum type of values is needed.

    That disjointness is what lets `State` hold one map per type and index all of
    them by the same `Var`: a name occurring in a boolean statement is a boolean
    variable, and the integer map's answer for it is never consulted. -/
abbrev Var := String

/-! ## Linear expressions

Crab's export gives every assignment right-hand side as a linear expression:
a list of (coefficient, variable) pairs plus a constant. So

    y := y + 1     is     terms = [(1, "y")], const = 1
-/

/-- A linear expression `Σ (coef * var) + const` over the integers.

    `structure` declares a record: one constructor (`LinExp.mk`) and one
    projection per field (`e.terms`, `e.const`). `deriving Repr` asks Lean to
    generate a printer, which is what makes `#eval` able to display one — handy
    when debugging a transcription. -/
structure LinExp where
  terms : List (Int × Var)
  const : Int
  deriving Repr

/-! ## Linear constraints

Crab normalises every constraint to `<terms> <op> <const>` and tags it with the
type of its variables, which is `math_int` for every integer crabber builds:
the surface language dropped its width annotations, and the parser now produces
Crab's `MATH_INT_TYPE` exclusively. So the semantics here is over unbounded
`Int`, and there is no width to record.

Crab itself has not lost its fixed-width integers, so this is a fact about what
crabber feeds the analyser, not about what Crab can express. It remains an
assumption rather than a modelling convenience: every abstract domain crabber
can run interprets values over ℤ, which is why the widths were dropped in the
first place. A wrapping semantics would be a separate development, under which
some of Crab's results would be expected to fail. -/

/-- The comparison operators Crab can emit: `<=`, `<`, `=`, `!=`.

    `inductive` declares a datatype by listing *all* the ways to build one.
    These four constructors are the only `CmpOp`s that exist, which is what
    makes a `match` over them exhaustive. -/
inductive CmpOp where
  | le | lt | eq | ne
  deriving Repr, DecidableEq

/-- A single linear constraint `Σ (coef * var)  op  const`.

    **Integer-typed, always.** The export tags every constraint with a type, and
    a bool-tagged one is not one of these: it is a claim about a boolean
    variable, and lives in the assertion language as its own atom (see
    `Assn.lean`). Nothing in a `LinCon` ever reads the boolean store, which is
    what keeps `LinCon.lhs` — and therefore every goal `omega` is handed —
    purely integer arithmetic. -/
structure LinCon where
  op    : CmpOp
  terms : List (Int × Var)
  const : Int
  deriving Repr

/-! ## Boolean operators

The three Crab emits, under the names its export uses. `xor` rather than
"not-equal" because that is the operator's name in CrabIR; `not` is not here,
because Crab has no unary boolean statement — a negation is carried as the
`negated` flag on `bool_assign_var`, and `b := not(c)` in the surface syntax
compiles to exactly that. -/

/-- The boolean binary operators Crab can emit: `and`, `or`, `xor`. -/
inductive BoolOp where
  | and | or | xor
  deriving Repr, DecidableEq

/-- What a `BoolOp` computes. Kept next to the syntax rather than in `State`
    because it involves no state: it is the meaning of the operator itself, and
    `Bool`'s own connectives are that meaning. -/
def BoolOp.apply : BoolOp → Bool → Bool → Bool
  | .and => (· && ·)
  | .or  => (· || ·)
  | .xor => (· ^^ ·)

/-! ## Statements

The numeric core, plus the boolean fragment.

The four numeric constructors already exercise every interesting case of the
weakest-precondition calculus — substitution, quantifier introduction,
implication, and proof obligation. The boolean ones add no new case to that
calculus: they are substitution, implication and obligation again, over the
boolean store instead of the integer one, with `boolHavoc` reusing quantifier
introduction and `boolToInt` reusing substitution back into the integer store.

### How the booleans are represented, and why

Crab exports boolean *facts* as 0/1 linear constraints — an invariant contains
`b = 1`, tagged with type `bool` — so an invariant looks like one uniform linear
system. `State` deliberately does **not** follow suit. It carries a separate
`Var → Bool` map, and the assertion language gets a boolean atom of its own.

Measured against the analyser, across `int`, `int-terms`, `int-set`, `zones`,
`oct-snf` and `pk`, a bool-tagged constraint is *always* `1·b = 0` or `1·b = 1`:
never relational, never a non-unit coefficient. Crab's booleans go through a flat
per-variable lattice, so there is no relational information to lose. The uniform
linear encoding therefore buys nothing here, and costs two things:

  * `b2 := b0 and b1` would have to be `min`, or a multiplication, and would drag
    `if … then 1 else 0` terms into every arithmetic goal;
  * nothing would confine a boolean to `{0, 1}`. A havoc'd or never-assigned
    boolean would be an arbitrary integer, so `b or not b` would come out `7` and
    Crab's (correct) `= 1` would be unprovable — unless `State` also carried a
    type environment and `InitState` restricted it.

The objection previously recorded against a separate map was that the meaning
function would then need each variable's type. It does — and the wire format
already supplies it, on every constraint, which is how the reader tells a boolean
atom from a linear one.

Deferred, and named here so the omission is visible rather than silent. The
measure throughout is what a CrabIR program can contain: Crab's IR is larger
than the language crabber parses, and the parts of it no program can reach are
neither modelled nor counted as gaps.

  * `x := y * z` and `x := y / z`, the only two forms crabber emits as a Crab
    `binop`. Multiplying or dividing two *variables* is outside what `omega`
    decides, and the rounding behaviour of Crab's division operators has not
    been pinned down.

    Linear arithmetic is *not* deferred, though the name `binop` suggests
    otherwise: `y + z`, `y - z` and `2*y - 3*z + 1` all reach the export as an
    `assign` carrying a `LinExp`, which is the first constructor below.
  * Procedure calls, which need a call rule and Crab's interprocedural
    summaries; and the array statements, which need select/store reasoning in
    the assertion language.
-/

/-- A CrabIR statement. -/
inductive Stmt where
  /-- `x := e` — assignment of a linear expression. -/
  | assign (x : Var) (e : LinExp)
  /-- `havoc(x)` — `x` becomes an arbitrary integer. -/
  | havoc  (x : Var)
  /-- `assume(c)` — execution continues only if `c` holds. -/
  | assume (c : LinCon)
  /-- `assert(c)` — a proof obligation *and* a filter on the state. Measured
      against the real analyser, Crab treats an assert as check-then-assume:
      after `havoc(x); assert(x >= 10)` the next block's invariant is
      `x ∈ [10, +∞]`, even though the assert itself only produces a warning. -/
  | assert (c : LinCon)
  /-- `x := c` — the boolean `x` records whether the *integer* constraint `c`
      holds. This is the only statement that crosses between the two stores, and
      it crosses one way: it reads the integer state and writes the boolean one.

      `c` is a `LinCon`, so integer-typed: the only constraint kind a CrabIR
      program can put here. -/
  | boolAssignCst (x : Var) (c : LinCon)
  /-- `x := y` or `x := not y`, according to `negated`. Crab has no separate
      negation statement: the surface `b := not(c)` compiles to this with the
      flag set. -/
  | boolAssignVar (x : Var) (y : Var) (negated : Bool)
  /-- `x := y op z` for `op` one of `and`, `or`, `xor`. -/
  | boolBinop (x : Var) (op : BoolOp) (y : Var) (z : Var)
  /-- `assume(y)`, or `assume(not y)` when `negated`. Execution continues only
      when the boolean holds. -/
  | boolAssume (y : Var) (negated : Bool)
  /-- `assert(y)` — check-then-assume, exactly as the integer `assert`. There is
      no `negated` flag: the export does not carry one for boolean asserts. -/
  | boolAssert (y : Var)
  /-- `havoc(b:bool)` — `x` becomes an arbitrary boolean.

      Separate from `havoc` rather than a type-tagged version of it, because the
      two write different stores and `State` keeps those apart. It is the
      boolean fragment's only source of nondeterminism, and the second clause in
      the whole calculus to introduce a quantifier — but over `Bool`, which has
      two inhabitants, so `simp` finishes what `omega` would not even be handed. -/
  | boolHavoc (x : Var)
  /-- `x := bool_to_int(b)` — the integer `x` becomes 1 when `b` holds and 0
      when it does not.

      The mirror of `boolAssignCst`: that one reads the integer store and writes
      the boolean one, this one goes the other way, and between them they are the
      only traffic between the two. Crab represents it as a `CAST_ZEXT` whose
      source is boolean, and `flat_boolean_domain` gives it exactly this meaning
      — `true ↦ 1`, `false ↦ 0`.

      There is no cast the other way, in the language or here: `b := x != 0`
      already turns an integer into a Boolean, and that is a `boolAssignCst`. -/
  | boolToInt (x : Var) (b : Var)
  deriving Repr

/-! ## Control-flow graphs -/

/-- Turn an association list into a **total** function, answering `dflt` for any
    label the list does not mention.

    This is how a machine-generated program supplies its blocks: the frontend
    splices in a list of (label, value) pairs, and this builds the total function
    `Cfg` requires. Writing the function out as a chain of literal cases would do
    just as well; a list keeps the generated term small and uniform.

    The comparison is `l = k`, propositional equality decided by `String.decEq`,
    and that choice is load-bearing rather than incidental. The obvious
    alternative is `List.lookup`, which compares with `BEq`. Both compute the
    same answers, but proofs need the *other* direction too: showing that a label
    naming no block gets the default, from hypotheses of the form `¬ B = "loop"`.
    With `=` the simplifier rewrites the `if` with such a hypothesis directly;
    with `==` it cannot, and the unknown-label case — which the bundling lemma
    for every generated program depends on — does not go through. -/
def table {α : Type} (dflt : α) : List (Label × α) → Label → α
  | [],             _ => dflt
  | (k, v) :: rest, l => if l = k then v else table dflt rest l

/-- A CFG: an entry label, and two *total* functions giving each label its
    block body and its successors.

    Totality is a deliberate choice. The soundness argument needs "every block's
    verification condition holds", quantified over every `String` — including
    ones that name no block. Making `body` and `succ` total, defaulting to `[]`,
    means that case is discharged once and for all by a single lemma rather than
    needing a side condition at every use. It also matches the treatment of
    states, whose variable maps are total for the same reason.

    Note the CFG we model is the one Crab *analysed*, not the source text: it
    contains the synthesised edge blocks that carry compiled-away guards, and
    may have been simplified further. A transcription of the source would not
    line up with the labels the invariants are attached to. -/
structure Cfg where
  entry : Label
  body  : Label → List Stmt
  succ  : Label → List Label

end Crabber
