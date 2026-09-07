import Lean
/-
# Crabber.Attr — the `@[crab]` simp set

Lean requires an attribute to be *registered* in a module that is imported by
the modules using it, so this one-line file exists on its own.

`@[crab]` marks the per-program definitions (`prog`, `body`, `succ`, `inv`, …)
that `crab_vc` must unfold.  Keeping them in a named simp set rather than the
default one means a generated program cannot perturb unrelated proofs.
-/
register_simp_attr crab
