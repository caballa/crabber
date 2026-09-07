/-
# Crabber — proving Crab's invariants in Lean 4

Root module: importing `Crabber` pulls in the whole library.

## What this library does

Crab is an abstract interpreter for CrabIR. For a given program it computes an
invariant for every basic block. This library checks that output: given the
program and the invariants as data, it produces a machine-checked proof that
they really are invariants — every state the program can reach at a block
satisfies the invariant claimed there — and that assertions Crab reported as
safe can never fail.

It does **not** model Crab itself. No fixpoint engine, no widening, no abstract
domain is formalised here. That is what keeps the job tractable, and it means
the proof is indifferent to which domain produced the invariants.

## Reading order

  Syntax    — CrabIR programs as data
  State     — concrete states; meaning of expressions          } trusted
  Semantics — Exec / Step / Reachable: what a program *does*    }
  Assn      — invariants as data, and their meaning            } trusted
  WP        — the weakest-precondition calculus + soundness    } proved
  VC        — the per-block obligation + the adapter lemma     } proved
  Soundness — inductive_sound and assert_safe                  } proved
  Tactic    — `crab_vc`, the automation (untrusted)
  Samples/* — one file per analysed program (data + theorems; these will be
              machine generated from Crab's JSON export, hand-written for now)

"Trusted" means a bug there could let us prove something false, because those
files *are* the claim about what CrabIR means. "Proved" means a bug there can
only make a true statement unprovable — the kernel rejects a bad proof.
-/
import Crabber.Syntax
import Crabber.State
import Crabber.Assn
import Crabber.Semantics
import Crabber.WP
import Crabber.VC
import Crabber.Soundness
import Crabber.Tactic
import Crabber.Samples.Test1Bar
import Crabber.Samples.Test1Foo
