import Crabber.Semantics
/-
# Crabber.WP — the weakest-precondition calculus

**Not trusted.** `wp` is an ordinary Lean function and `wp_sound` is an ordinary
theorem; a bug here cannot make a false invariant provable, only make a true one
unprovable. That freedom is why we may pick whichever calculus automates best.

Three were available, and backward reasoning wins on goal shape:

  * **Relational** — `∀ σ σ', ⟦I B⟧ σ → Exec (body B) σ σ' → ⟦I B'⟧ σ'`. Needs no
    calculus and no soundness lemma at all, but leaves an existentially
    quantified intermediate state per statement, and the goal shape depends on
    the order in which `Exec` is inverted.
  * **Forward (strongest postcondition)** — matches the direction the analyser
    itself runs, which would make a failed obligation easy to compare against
    Crab's computed state. But assignment has to existentially quantify the
    overwritten value, so goals accumulate quantifiers.
  * **Backward (weakest precondition)** — assignment is substitution, which
    introduces nothing; `assume` becomes an implication; only `havoc` introduces
    a quantifier, and over an integer rather than over states. Goals come out as
    quantifier-free linear integer arithmetic, which `omega` decides.

The postcondition here is a Lean predicate (`State → Prop`) rather than a
formula in the assertion language. That spares us defining capture-avoiding
substitution and proving its lemmas. The cost is that `wp` cannot be *computed*
with — a `∀ v : Int` postcondition is a perfectly good proposition and
completely unevaluable — so this calculus cannot be compiled into a checker that
runs somewhere without a Lean elaborator. Doing that would need a second `wp`
mapping data to data, plus a decidable entailment test proved sound.
-/

namespace Crabber

/-- `wpStmt s Q` — the weakest precondition of a single statement.

    Read each clause as: "for `Q` to hold *after* `s`, what must hold before?"

    * `assign` — `Q` must hold of the updated state. This is substitution:
      nothing is quantified, the state is just rewritten.
    * `havoc`  — `Q` must hold *whatever* value lands in `x`, so a `∀`. The
      adversary picks `v`; we must survive all of them.
    * `assume` — we may assume `c`, so it becomes the *antecedent* of an
      implication. Everything is easier if `c` is false.
    * `assert` — check **and** assume. The `∧` is the proof obligation (we owe
      `c`); it is *not* an antecedent, because an assert we cannot discharge is
      a failure, not a free pass.

    `@[simp]` generates one equation lemma per clause, so `simp` unfolds this
    automatically on a concrete statement. -/
@[simp] def wpStmt (s : Stmt) (Q : State → Prop) : State → Prop :=
  match s with
  | .assign x e => fun σ => Q (σ.set x (e.eval σ))
  | .havoc x    => fun σ => ∀ v : Int, Q (σ.set x v)
  | .assume c   => fun σ => c.holds σ → Q σ
  | .assert c   => fun σ => c.holds σ ∧ Q σ

/-- `wp ss Q` — the weakest precondition of a statement *list*.

    Defined by structural recursion, threading the postcondition **backwards**
    through the body: the last statement is processed first. `wp [] Q = Q` is the
    base case — an empty body demands exactly what you wanted afterwards. -/
@[simp] def wp : List Stmt → (State → Prop) → State → Prop
  | [],      Q => Q
  | s :: ss, Q => wpStmt s (wp ss Q)

/-- **Single-statement soundness.** If the weakest precondition of `s` for `Q`
    holds before, and `s` really steps σ to σ', then `Q` holds after.

    The proof is one case per `StmtExec` constructor, and each case is a single
    term — which is the point: `wpStmt` was *defined* to make these match. -/
theorem wpStmt_sound {s : Stmt} {Q : State → Prop} {σ σ' : State}
    (hwp : wpStmt s Q σ) (hex : StmtExec s σ σ') : Q σ' := by
  -- `cases hex` splits on how the step was built. In each branch Lean also
  -- rewrites `s` and `σ'` to the constructor's shape, so `hwp` refines too.
  cases hex with
  | assign      => exact hwp          -- hwp : Q (σ.set x (e.eval σ)); that *is* the goal
  | havoc v     => exact hwp v        -- hwp : ∀ v, Q (σ.set x v); instantiate at the v chosen
  | assume h    => exact hwp h        -- hwp : c.holds σ → Q σ; feed it the assume's premise
  | assert h    => exact hwp.2        -- hwp : c.holds σ ∧ Q σ; `.2` is the right conjunct

/-- **`wp_sound` — the soundness of the calculus.** The lemma that discharges the
    `Exec` premise, once and for all.

    In English: if the weakest precondition of a block body for `Q` holds in σ,
    and the body can execute from σ to σ', then `Q` holds in σ'.

    Everything about the transition relation is consumed *here*. After this
    point, every arrow appearing in a verification condition comes from an
    `assume` in the program, never from `Exec`.

    The argument order — weakest precondition first, execution second — is what
    reads best at the one place that calls it, the adapter lemma in `VC.lean`.
    The induction is on the `Exec` derivation either way. -/
theorem wp_sound {ss : List Stmt} {Q : State → Prop} {σ σ' : State}
    (hwp : wp ss Q σ) (hex : Exec ss σ σ') : Q σ' := by
  -- Induct on the *derivation* of `Exec ss σ σ'`: one case per constructor.
  induction hex with
  | nil =>
      -- Body was empty, so σ' = σ and `wp [] Q = Q`: `hwp` is literally the goal.
      exact hwp
  | cons hstep _hrest ih =>
      -- Body was `s :: ss`. `hwp : wpStmt s (wp ss Q) σ`.
      -- Push it through the first statement to get `wp ss Q` at the
      -- intermediate state, then hand that to the induction hypothesis.
      exact ih (wpStmt_sound hwp hstep)

end Crabber
