import Crabber.VC
/-
# Crabber.Soundness — the two meta-theorems

Proved once, program-independently. This is the heart of the project:
everything after it is plumbing and automation.
-/

namespace Crabber

/-- `InvariantOf P I` — "`I` really is an invariant of `P`": every reachable
    configuration satisfies the annotation at its own label. This is the property
    `inductive_sound` delivers and `assert_safe` consumes. -/
def InvariantOf (P : Cfg) (I : Label → Assn) : Prop :=
  ∀ c : Config, Reachable P c → ⟦I c.1⟧ c.2

/-- **`inductive_sound` — the inductive-assertion method.**

    In English: *if the annotation holds when the program starts, and no single
    step can ever break it, then it holds at every state the program can ever
    reach.*

    The two hypotheses are named arguments before the colon, so this theorem is a
    **function**: hand it two proofs, get a proof back.

    What it is, structurally: `Reachable` is the least fixed point of the
    operator its two constructors describe, and this theorem is the *leastness*
    direction instantiated at the annotation. The two hypotheses together say
    precisely that the set of states satisfying the annotation is closed under
    that operator; the conclusion says `Reachable` is contained in it. That is
    fixpoint induction, which is why the proof below is two lines: Lean *hands*
    us the principle as `Reachable`'s recursor, and `induction … with` is sugar
    over it.

    Note what it does **not** claim: nothing about the annotation being strongest
    or precise, and nothing about termination — invariants are safety properties,
    so a non-terminating program satisfies this vacuously. If Crab's output is
    not inductive, the second hypothesis simply will not be provable. -/
theorem inductive_sound (P : Cfg) (I : Label → Assn)
    (initiation : ∀ σ : State, InitState P σ → ⟦I P.entry⟧ σ)
    (consecution : ∀ (L : Label) (σ : State) (L' : Label) (σ' : State),
        ⟦I L⟧ σ → Step P (L, σ) (L', σ') → ⟦I L'⟧ σ') :
    InvariantOf P I := by
  intro c h
  -- Induct on the derivation of `Reachable P c`: exactly two cases, because
  -- `Reachable` has exactly two constructors. They line up one-for-one with the
  -- two hypotheses — that correspondence *is* the inductive-assertion method.
  induction h with
  | init hi =>
      -- The configuration is `(P.entry, σ)`; `initiation` is precisely this.
      exact initiation _ hi
  | step _hc hs ih =>
      -- `ih` is the induction hypothesis: the annotation held at the
      -- predecessor. `hs` says we stepped from there. `consecution` closes it.
      exact consecution _ _ _ _ ih hs

/-- **`assert_safe` — the result users actually care about.**

    In English: *if the annotation is an invariant, and at every statement in
    every block the invariant at that block's entry implies that statement's
    obligation (after running the statements that precede it in the block), then
    no execution of the program ever fails an assert.*

    The `chk` hypothesis quantifies over every way a block body splits as
    `pre ++ s :: post` — the append equation is what makes "a statement occurring
    somewhere in the block" precise. For a block whose assert is first, `pre` is
    `[]` and `wp [] Q = Q`, so the obligation is just "the invariant implies the
    condition"; for a statement that is not an assert the obligation is `True`
    and there is nothing to show.

    Quantifying over an arbitrary statement, rather than over `Stmt.assert c`, is
    what makes this cover the boolean asserts too — and every assert-like
    construct still to come, each of which is a clause in `Stmt.obligation` and
    nothing here.

    `chk` need not be supplied by hand: `chk_of_VC` derives it from the block
    verification conditions, which is how `verified` below obtains it. It stays a
    hypothesis so that this theorem remains true independently of that
    derivation, which depends on how `wpStmt` treats an assert. -/
theorem assert_safe (P : Cfg) (I : Label → Assn)
    (hinv : InvariantOf P I)
    (chk : ∀ (L : Label) (pre : List Stmt) (s : Stmt) (post : List Stmt),
        P.body L = pre ++ s :: post →
        ∀ σ : State, ⟦I L⟧ σ → wp pre (fun τ => s.obligation τ) σ) :
    ¬ AssertFails P := by
  -- `rintro` assumes `AssertFails P` and immediately destructs its six
  -- existentials and four conjuncts into named pieces.
  rintro ⟨L, σ, pre, s, post, τ, hreach, hbody, hexec, hfail⟩
  -- The invariant holds at the reachable configuration we landed on…
  have hI : ⟦I L⟧ σ := hinv (L, σ) hreach
  -- …so by `chk` the weakest precondition of the *prefix* for "s's obligation
  -- holds" is true at σ…
  have hwp := chk L pre s post hbody σ hI
  -- …and `wp_sound`, given that the prefix really ran σ to τ, says the
  -- obligation holds at τ. But `hfail` says it does not. Contradiction.
  exact hfail (wp_sound hwp hexec)

/-- **The bundle a per-program file proves.**

    In English: *given (i) the entry obligation and (ii) every block's
    verification condition, the annotation is a genuine invariant and no
    assertion can fail.*

    This is the single entry point for per-program files: it chains
    `consecution_of_VC`, `chk_of_VC`, `inductive_sound` and `assert_safe` so that
    such a file never mentions `Step`, `Reachable`, or `wp_sound`.

    **Two hypotheses, not three.** The assert obligations used to be a third
    argument, generated per program. They are not, because `wpStmt` already puts
    an assert's obligation inside its block's verification condition, and
    `chk_of_VC` extracts it. A per-program file now supplies only what is
    genuinely program-specific: the entry invariant is satisfied, and each block
    preserves the annotation. -/
theorem verified (P : Cfg) (I : Label → Assn)
    (initiation : ∀ σ : State, InitState P σ → ⟦I P.entry⟧ σ)
    (vcs : ∀ B : Label, VC P I B) :
    InvariantOf P I ∧ ¬ AssertFails P :=
  -- `have` names the intermediate result so both halves can use it; the
  -- anonymous constructor `⟨_, _⟩` builds the conjunction.
  have hinv := inductive_sound P I initiation (consecution_of_VC P I vcs)
  ⟨hinv, assert_safe P I hinv (chk_of_VC P I vcs)⟩

end Crabber
