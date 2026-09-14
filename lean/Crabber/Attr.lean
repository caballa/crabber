import Lean
/-
# Crabber.Attr — the two simp sets

Lean requires an attribute to be *registered* in a module that is imported by
the modules using it, so this small file exists on its own.

The two sets answer different questions, and the split is what keeps a generated
program from perturbing unrelated proofs:

* `@[crab]` marks the **per-program** definitions — `prog`, `inv`, `bodyTable`,
  `succTable` — that `crab_program` installs and the automation must unfold to
  see the block it is reasoning about. Its contents change with every program.

* `@[crab_meaning]` marks the **fixed** chain of meaning functions that turns
  invariant *data* into arithmetic: `⟦A⟧ σ` down to the `Int` comparisons
  `omega` decides. Its contents change only when the assertion language does.
-/
register_simp_attr crab

/-- The meaning functions — invariant data down to arithmetic.

    Membership is declared in one place, `Crabber.Tactic`, rather than at the
    definition sites, so that the trusted core stays free of any dependency on
    `Lean`. See that file for why the set exists at all. -/
register_simp_attr crab_meaning
