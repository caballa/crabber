import CrabberJson.Schema
/-
# CrabberJson.RoundTrip — reading the export back out again

The reader in `Schema.lean` is trusted: nothing proves that the `Cfg` it
produces is the graph Crab analysed. This module supplies the check that makes
a mistranslation visible instead of silent.

The idea is only that a faithful reader has an inverse. Read the document into
the wire types, write those back out, and compare against what was read. A
reader that dropped a statement, misparsed a coefficient, or ignored a key
cannot reproduce the input, because the information needed to do so is no longer
there. The comparison is on `Json` values rather than on text, so key ordering
and whitespace are irrelevant.

What this does **not** check: that the wire types mean what the conversion to
`Cfg`/`Assn` says they mean. Reading `math_int` as Lean's unbounded `Int`,
reading `1·b = 1` as a claim
about the boolean store, discarding an assertion's source location — those are
choices argued for where they are made, and no round trip can validate them.
What it covers is the mechanical half, which is the half where a silent slip is
plausible.

Nor does it apply to documents this library refuses outright. A program using
statements outside the modelled fragment fails at the reading step, loudly;
there is nothing to round-trip. That is the intended behaviour, not a gap.
-/

namespace CrabberJson

open Lean (Json toJson fromJson?)

/-- Where two JSON documents first diverge, with a little context from each.

    Both sides are printed in Lean's canonical compressed form — object keys
    sorted, no whitespace — so the offset is a genuine locator rather than an
    artifact of formatting. -/
def firstDifference (a b : Json) : String :=
  let sa := a.compress
  let sb := b.compress
  let la := sa.toList
  let lb := sb.toList
  let rec go (xs ys : List Char) (n : Nat) : Nat :=
    match xs, ys with
    | x :: xs', y :: ys' => if x == y then go xs' ys' (n + 1) else n
    | _, _ => n
  let n := go la lb 0
  let window (s : String) : String :=
    let start := if n < 30 then 0 else n - 30
    String.ofList ((s.toList.drop start).take 90)
  s!"first difference at offset {n}\n  read : …{window sb}…\n  input: …{window sa}…"

/-- Read a document and confirm the reader is faithful to it.

    Returns the document on success, so a caller that wants both the check and
    the data does not parse twice. -/
def readChecked (raw : Json) : Except String WDoc := do
  let d ← docOfJson raw
  let back := toJson d
  if back == raw then
    return d
  else
    throw s!"the JSON reader is not faithful to this document: writing the parsed \
             form back out does not reproduce the input. Something was dropped or \
             misread.\n{firstDifference raw back}"

/-- Parse one CFG and confirm the parse reproduces the JSON it came from.

    This is where the round trip earns its keep. `readChecked` above covers the
    document's header, but the header is small and mostly carried verbatim; the
    statements, the successors and the invariants are what a mistranslation
    would silently corrupt, and they all live here.

    Doing it per CFG rather than for the whole array is what stops one CFG the
    library cannot model from condemning its neighbours. Only the CFG actually
    being verified has to parse. -/
def cfgChecked (raw : Json) : Except String WCfg := do
  let c : WCfg ← fromJson? raw
  let back := toJson c
  if back == raw then
    return c
  else
    throw s!"the JSON reader is not faithful to this cfg: writing the parsed \
             form back out does not reproduce the input. Something was dropped \
             or misread.\n{firstDifference raw back}"

/-- Read one named cfg from a document's text, checking both round trips on the
    way. This is the entry point a generated file should use: it is the only
    path that both produces a `Program` and validates the reading of it. -/
def programOfString (text : String) (cfgName : String) : Except String Program := do
  let raw ← Json.parse text
  let d ← readChecked raw
  let cfgRaw ← d.rawCfg cfgName
  let c ← cfgChecked cfgRaw
  c.toProgram

/-- The names of every cfg in a document, without parsing any of them. -/
def cfgNamesOfString (text : String) : Except String (List String) := do
  let raw ← Json.parse text
  let d ← readChecked raw
  return d.cfgNames

end CrabberJson
