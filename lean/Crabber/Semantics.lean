import Crabber.Assn
/-
# Crabber.Semantics — what a CrabIR program *does*

**Trusted.** Nothing in this file is proved, because these definitions *are* our
claim about the meaning of CrabIR. If `Exec` is wrong, everything downstream is
proved about the wrong machine. The probe suite of small CrabIR programs run
against the real analyser is the mitigation: each measured fact there is
something this file must match.

Two of those facts are visible in the code below:

  * **Integers are mathematical integers.** There is no wrapping anywhere;
    `x:i8 := 127; x := x+1` gives 128, and truncating casts are the identity.
  * **`assert` is check-then-assume.** `StmtExec.assert` requires the condition
    to hold, so a failing assert has no successor state at all: execution simply
    cannot continue past it. This is what makes Crab's downstream invariants
    correct, and it means invariants describe only those executions in which
    every assert so far has passed.
-/

namespace Crabber

/-! ## One statement -/

/-- `StmtExec s σ σ'` — "statement `s` can take state σ to state σ'".

    A *relation*, not a function, because `havoc` is nondeterministic: from one
    σ there are infinitely many σ'. Declaring it `inductive` means these four
    constructors are the **only** ways a step can happen, which is what lets a
    proof do case analysis on it. -/
inductive StmtExec : Stmt → State → State → Prop where
  -- Integer statements.
  /-- Assignment overwrites `x` with the value of `e` in the *current* state. -/
  | assign {σ : State} {x : Var} {e : LinExp} :
      StmtExec (.assign x e) σ (σ.set x (e.eval σ))
  /-- `havoc(x)` may write *any* integer. The constructor takes `v` as an
      argument, so there is one step for each choice — this is where the
      nondeterminism literally lives. -/
  | havoc {σ : State} {x : Var} (v : Int) :
      StmtExec (.havoc x) σ (σ.set x v)
  /-- `assume(c)` leaves the state alone, but only steps at all when `c` holds:
      the hypothesis `c.holds σ` is a *premise* of the constructor. -/
  | assume {σ : State} {c : LinCon} (h : c.holds σ) :
      StmtExec (.assume c) σ σ
  /-- `assert(c)` behaves identically to `assume` *as a transition*. The
      difference is not here but in the weakest-precondition calculus, which
      additionally demands a proof of `c`. Filtering here is what makes the
      invariants after an assert correct; obligating there is what makes the
      assert mean something. -/
  | assert {σ : State} {c : LinCon} (h : c.holds σ) :
      StmtExec (.assert c) σ σ

  -- Boolean statements. Nothing new happens here: each is an update, a filter,
  -- or both, exactly as above, but against the boolean store.
  /-- `x := c` evaluates the *integer* constraint and records the answer.
      `LinCon.check` is the `Bool`-valued reading of `LinCon.holds`; that they
      agree is `LinCon.check_eq_true`, and it is the only fact anything uses. -/
  | boolAssignCst {σ : State} {x : Var} {c : LinCon} :
      StmtExec (.boolAssignCst x c) σ (σ.setBool x (c.check σ))
  /-- `x := y`, or `x := not y` when `negated`. `xor n` is the identity for
      `n = false` and negation for `n = true`, which is exactly the flag's
      meaning — so one clause covers both forms with no `if`. -/
  | boolAssignVar {σ : State} {x y : Var} {n : Bool} :
      StmtExec (.boolAssignVar x y n) σ (σ.setBool x (n ^^ σ.bools y))
  /-- `x := y op z`. -/
  | boolBinop {σ : State} {x y z : Var} {op : BoolOp} :
      StmtExec (.boolBinop x op y z) σ (σ.setBool x (op.apply (σ.bools y) (σ.bools z)))
  /-- `assume(y)` / `assume(not y)`: the state is unchanged, and the step exists
      only when the boolean holds — the premise is what does the filtering, just
      as in the integer `assume`. -/
  | boolAssume {σ : State} {y : Var} {n : Bool} (h : (n ^^ σ.bools y) = true) :
      StmtExec (.boolAssume y n) σ σ
  /-- `assert(y)` — again identical to `assume` as a transition; the obligation
      is added by the weakest-precondition calculus, not here. -/
  | boolAssert {σ : State} {y : Var} (h : σ.bools y = true) :
      StmtExec (.boolAssert y) σ σ
  /-- `x := if c then l else r`. -/
  | boolSelect {σ : State} {x c l r : Var} :
      StmtExec (.boolSelect x c l r) σ
        (σ.setBool x (if σ.bools c then σ.bools l else σ.bools r))

/-! ## A whole block body -/

/-- `Exec ss σ σ'` — "the statement list `ss` can take σ to σ'".

    The straight-line composition of `StmtExec`. A block body has no control
    flow inside it — conditionals were compiled into separate edge blocks
    carrying the guards — so a list is the whole story. -/
inductive Exec : List Stmt → State → State → Prop where
  /-- The empty body changes nothing. -/
  | nil {σ : State} : Exec [] σ σ
  /-- Run the head, then the tail, through some intermediate state σ'. -/
  | cons {s : Stmt} {ss : List Stmt} {σ σ' σ'' : State} :
      StmtExec s σ σ' → Exec ss σ' σ'' → Exec (s :: ss) σ σ''

/-! ## The transition system -/

/-- A configuration: which block we are at the top of, and the current state. -/
abbrev Config := Label × State

/-- `Step P c c'` — one move of the machine: run a whole block, then jump to one
    of its successors.

    Kept as a plain `def` unfolding to a **conjunction**, so that the adapter
    lemma in `VC.lean` can split it with `obtain ⟨_, _⟩`. That shape is
    provisional: once procedure calls are added the machine gains a stack,
    `Step` becomes an inductive, and that `obtain` becomes a `cases`. The
    adapter lemma is the only place that would have to change. -/
def Step (P : Cfg) (c c' : Config) : Prop :=
  c'.1 ∈ P.succ c.1 ∧ Exec (P.body c.1) c.2 c'.2

/-- Which states a program may start in.

    Crab assumes nothing about the values of variables on entry, so every state
    is an initial state. This is a definition rather than a `Cfg` field because
    it is a property of the analysis setup, not of the graph. Giving it a name
    means that when input parameters with preconditions are added, only this
    changes. -/
def InitState (_P : Cfg) (_σ : State) : Prop := True

/-- `Reachable P c` — the configurations the machine can actually get into.

    This is the **least fixed point** of the operator described by the two
    constructors: `init` seeds it with the entry configurations, `step` closes it
    under `Step`. In Lean, `inductive` *is* how you write a least fixed point —
    the constructors say the set is closed under the rules, and the
    automatically generated recursor (`Reachable.rec`) says it is the *smallest*
    such set. That recursor is the induction principle used by `inductive_sound`
    in `Soundness.lean`, and it is exactly the fixpoint-induction rule: the least
    fixed point is contained in anything the operator maps into itself.

    Note what `Reachable` inherits from `Exec`: since a failing `assert` has no
    `StmtExec` step, no configuration *past* a violated assert is reachable.
    Invariants therefore describe assert-passing executions only, which is what
    Crab computes. -/
inductive Reachable (P : Cfg) : Config → Prop where
  /-- Any state, at the entry block, is reachable. -/
  | init {σ : State} (h : InitState P σ) : Reachable P (P.entry, σ)
  /-- Reachability is closed under `Step`. -/
  | step {c c' : Config} (hc : Reachable P c) (hs : Step P c c') : Reachable P c'

/-! ## What it means for an assertion to fail -/

/-- `s.obligation σ` — what `s` demands of the state it is reached in.

    Every statement has one; for all but the two asserts it is `True`. Naming it
    is what lets "an assertion fails" be stated once, over an arbitrary
    statement, instead of once per kind of assert.

    That generalisation is forced rather than tidy. Written against
    `Stmt.assert` alone, `AssertFails` would be *vacuously* unsatisfiable for a
    program whose only assertions are boolean — the theorem would still read
    "no assertion can fail" while quantifying over none of them. Every
    assert-like construct still to come (division by zero, array bounds,
    `select`'s guard) is one clause here and nothing else anywhere.

    `True` for the ordinary statements is not a placeholder: it is the claim
    that they can be reached in any state whatsoever, which is exactly right.

    **Every constructor is listed, rather than a `_ => True` catch-all.** This
    is a trusted definition, and a catch-all would silently give `True` to the
    next statement added to `Stmt` — `select` with its division guard, or an
    array load needing a bounds check. Those would then be *unobligated*, and
    `¬ AssertFails` would quietly stop covering them while still reading as
    though it did. Spelling the cases out turns that into a missing-cases error
    at the one place where the question has to be answered. -/
def Stmt.obligation : Stmt → State → Prop
  | .assert c           => fun σ => c.holds σ
  | .boolAssert y       => fun σ => σ.bools y = true
  | .assign _ _         => fun _ => True
  | .havoc _            => fun _ => True
  | .assume _           => fun _ => True
  | .boolAssignCst _ _  => fun _ => True
  | .boolAssignVar _ _ _ => fun _ => True
  | .boolBinop _ _ _ _  => fun _ => True
  | .boolAssume _ _     => fun _ => True
  | .boolSelect _ _ _ _ => fun _ => True

/-- `AssertFails P` — some execution reaches a statement whose obligation is
    false at that point.

    Spelled out concretely: there is a reachable configuration `(L, σ)`, the body
    of `L` splits as `pre ++ s :: post`, running `pre` from σ can reach τ, and
    `s`'s obligation fails at τ.

    `∃ L σ pre s post τ, …` chains six existentials; `∧` chains the four
    conditions. `List.append` is written `++`. Quantifying over the way the body
    splits is what makes "a statement occurring somewhere in the block" precise —
    the append equation *is* its index. Positions holding an ordinary statement
    contribute nothing, since `¬ True` is false. -/
def AssertFails (P : Cfg) : Prop :=
  ∃ (L : Label) (σ : State) (pre : List Stmt) (s : Stmt)
    (post : List Stmt) (τ : State),
      Reachable P (L, σ) ∧
      P.body L = pre ++ s :: post ∧
      Exec pre σ τ ∧
      ¬ s.obligation τ

end Crabber
