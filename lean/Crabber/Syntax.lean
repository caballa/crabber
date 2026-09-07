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
    sum type of values is needed. -/
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
type of its variables. We deliberately drop the bitwidth: measured against the
real analyser, Crab's integers behave as mathematical integers, not machine
words — `x:i8 := 127; x := x+1` yields `x == 128`, not `-128`, and a truncating
cast from `i32` to `i16` leaves the value unchanged. So the semantics here is
over unbounded `Int`, and a width would be recorded but never used.

That is a genuine assumption about what CrabIR means, not a modelling
convenience. A wrapping semantics would be a separate development, under which
some of Crab's results would be expected to fail. -/

/-- The comparison operators Crab can emit: `<=`, `<`, `=`, `!=`.

    `inductive` declares a datatype by listing *all* the ways to build one.
    These four constructors are the only `CmpOp`s that exist, which is what
    makes a `match` over them exhaustive. -/
inductive CmpOp where
  | le | lt | eq | ne
  deriving Repr, DecidableEq

/-- A single linear constraint `Σ (coef * var)  op  const`. -/
structure LinCon where
  op    : CmpOp
  terms : List (Int × Var)
  const : Int
  deriving Repr

/-! ## Statements

The numeric core. Deliberately small: these four constructors are exactly what
the first sample program needs, and they already exercise every interesting case
of the weakest-precondition calculus — substitution, quantifier introduction,
implication, and proof obligation.

Deferred, and named here so the omission is visible rather than silent:

  * Boolean statements (`bool_assign_cst`, `bool_binop`, `bool_assume`, …).
    Crab exports booleans as 0/1 linear constraints, so an invariant is one
    uniform linear system; but whether `State` should follow suit (booleans as
    0/1 integers, which makes `b2 := b0 and b1` non-linear) or keep a separate
    boolean map (clean, but the meaning function then needs each variable's
    type) is undecided. Adding a half-answer here would prejudge it.
  * `select`, `cast`, `unreachable`, and the non-linear binary operators.
    Multiplication and division of variables are outside what `omega` decides,
    and the exact rounding behaviour of Crab's four division operators —
    signed and unsigned quotient and remainder are distinct in the export — has
    not been pinned down.
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
