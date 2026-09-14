/-
# CrabberJson — the frontend: crabber's JSON export, read into Lean

Kept in a library of its own, imported by neither `Crabber` nor anything it
imports. Two reasons, both deliberate:

  * the proof library has a dependency footprint of zero and is built from core
    datatypes only. Reading JSON needs `Lean` itself as a library, which is a
    heavy import; confining it here keeps the trusted development untouched by
    it;
  * the split matches the trust boundary. `Crabber` says what CrabIR means and
    proves things about it. `CrabberJson` only transcribes — and its output is
    checked against its input rather than believed.

  Schema    — the wire types, the JSON instances, and the conversion to Cfg/Assn
  RoundTrip — reading a document back out and comparing, so a mistranslation is
              visible rather than silent
  Elab      — `crab_program`, which loads an export while a file is elaborated
  Samples/* — one file per analysed program: the loader line, then the proofs
-/
import CrabberJson.Schema
import CrabberJson.RoundTrip
import CrabberJson.Elab
import CrabberJson.Samples.Test1Bar
import CrabberJson.Samples.TestBool1
