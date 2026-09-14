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

    The six boolean clauses introduce no new shape: `boolAssignCst`,
    `boolAssignVar`, `boolBinop` and `boolSelect` are substitution into the
    boolean store, `boolAssume` is an implication, `boolAssert` is a conjunction.
    Every one of them mirrors its `StmtExec` constructor exactly, which is why
    the soundness proof below stays one term per case. Note that no boolean
    statement introduces a quantifier: `havoc` remains the only clause that does,
    and it quantifies over an integer.

    `@[simp]` generates one equation lemma per clause, so `simp` unfolds this
    automatically on a concrete statement. -/
@[simp] def wpStmt (s : Stmt) (Q : State → Prop) : State → Prop :=
  match s with
  | .assign x e => fun σ => Q (σ.set x (e.eval σ))
  | .havoc x    => fun σ => ∀ v : Int, Q (σ.set x v)
  | .assume c   => fun σ => c.holds σ → Q σ
  | .assert c   => fun σ => c.holds σ ∧ Q σ
  | .boolAssignCst x c   => fun σ => Q (σ.setBool x (c.check σ))
  | .boolAssignVar x y n => fun σ => Q (σ.setBool x (n ^^ σ.bools y))
  | .boolBinop x op y z  => fun σ => Q (σ.setBool x (op.apply (σ.bools y) (σ.bools z)))
  | .boolAssume y n      => fun σ => (n ^^ σ.bools y) = true → Q σ
  | .boolAssert y        => fun σ => σ.bools y = true ∧ Q σ
  | .boolSelect x c l r  =>
      fun σ => Q (σ.setBool x (if σ.bools c then σ.bools l else σ.bools r))

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
  -- The boolean half, case for case the same three shapes.
  | boolAssignCst => exact hwp
  | boolAssignVar => exact hwp
  | boolBinop     => exact hwp
  | boolSelect    => exact hwp
  | boolAssume h  => exact hwp h
  | boolAssert h  => exact hwp.2

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

/-! ## Extracting the assertion obligations from a weakest precondition

The three lemmas below exist for one purpose: to prove, once, that a block's
verification condition *already contains* the obligation of every assert in that
block. That makes the `chk` hypothesis of `assert_safe` a consequence of the VCs
rather than something a generated file has to prove for itself — see
`chk_of_VC` in `VC.lean`.

The reason it works is the `∧` in `wpStmt`'s `assert` clause: the obligation sits
in the precondition unconditionally, so it survives being pushed leftwards
through the statements before it. Under the alternative `→` reading discussed in
`Samples/Test1Foo.lean`, `wp_split` would be false and the obligations would have
to be generated separately again. That is the one thing this depends on. -/

/-- **`wpStmt` is monotone in its postcondition.** Ask for less afterwards, and
    you need less beforehand.

    One case per constructor, and each is a single term. The four shapes recur:
    substitution applies `h` to the updated state, `havoc` under the `∀`,
    `assume` under the `→`, `assert` inside the right conjunct. -/
theorem wpStmt_mono {s : Stmt} {Q R : State → Prop} (h : ∀ σ, Q σ → R σ) :
    ∀ σ : State, wpStmt s Q σ → wpStmt s R σ := by
  intro σ hwp
  cases s with
  | assign         => exact h _ hwp
  | havoc          => exact fun v => h _ (hwp v)
  | assume         => exact fun hc => h _ (hwp hc)
  | assert         => exact ⟨hwp.1, h _ hwp.2⟩
  | boolAssignCst  => exact h _ hwp
  | boolAssignVar  => exact h _ hwp
  | boolBinop      => exact h _ hwp
  | boolSelect     => exact h _ hwp
  | boolAssume     => exact fun hc => h _ (hwp hc)
  | boolAssert     => exact ⟨hwp.1, h _ hwp.2⟩

/-- Monotonicity for a whole body, by induction over it. -/
theorem wp_mono {ss : List Stmt} {Q R : State → Prop} (h : ∀ σ, Q σ → R σ) :
    ∀ σ : State, wp ss Q σ → wp ss R σ := by
  induction ss with
  | nil          => exact fun σ hwp => h σ hwp
  | cons _ _ ih  => exact fun σ hwp => wpStmt_mono ih σ hwp

/-- **A weakest precondition entails the first statement's own obligation.**

    `first | exact hwp.1 | exact trivial` rather than a case list: for the two
    asserts `wpStmt` is a conjunction whose left half *is* the obligation, and
    for every other statement the obligation is `True`. The order matters —
    `trivial` would not close an assert's goal, and `.1` does not elaborate
    against the other clauses' shapes. -/
theorem wpStmt_obligation {s : Stmt} {Q : State → Prop} {σ : State}
    (hwp : wpStmt s Q σ) : s.obligation σ := by
  cases s <;> first | exact hwp.1 | exact trivial

/-- **The extraction lemma.** If a body split as `pre ++ s :: post` has a
    weakest precondition, then running just `pre` establishes `s`'s obligation.

    In other words: whatever the block was ultimately asked to achieve, getting
    there entails discharging every assert on the way. Induction on `pre`, with
    monotonicity doing the work of pushing the weakened postcondition back
    through each preceding statement. -/
theorem wp_split (pre : List Stmt) (s : Stmt) (post : List Stmt)
    (Q : State → Prop) :
    ∀ σ : State, wp (pre ++ s :: post) Q σ → wp pre (fun τ => s.obligation τ) σ := by
  induction pre with
  -- `pre` empty: the split's head *is* `s`, so this is `wpStmt_obligation`.
  | nil         => exact fun σ hwp => wpStmt_obligation hwp
  -- `pre = p :: pre'`: both sides start with `wpStmt p`, and the induction
  -- hypothesis is exactly the implication `wpStmt_mono` needs between them.
  | cons _ _ ih => exact fun σ hwp => wpStmt_mono ih σ hwp

end Crabber
