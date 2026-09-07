import CrabberJson
/-
# `checkjson` — run the reader over exported documents

    lake exe checkjson out1.json out2.json …

For each file: parse it, read it into the wire types, confirm that writing those
back out reproduces the input, and convert every cfg in it to the `Cfg` and
`Label → Assn` the proof library consumes. Reports one line per cfg and exits
non-zero if anything failed.

This is how the reader is exercised against the whole sample suite without
writing a per-program Lean file for each. A program using constructs outside the
numeric core is *expected* to fail here, with the construct named; that is the
reader refusing to silently drop it.

## This program proves nothing

Worth stating plainly, because "check" is a word the proof side has a claim on.
Nothing here constructs a verification condition, runs a tactic, or produces a
theorem. `ok` means *this export can be read and converted* — it says nothing
about whether Crab's invariants are sound or its assertions hold.

Where proving actually happens is `lake build`: the per-program files under
`CrabberJson/Samples/` are elaborated, `crab_vc` searches for the proofs, and
Lean's kernel checks them. That is the whole design — proofs are found and
checked offline, once per program, and no binary ever decides anything at run
time. (Building *this* executable does cause those proofs to be checked, since
it imports them, but that is a build dependency, not something it does when run.)

The one future exception is the reflective checker sketched for the playground,
where a compiled Lean function would render a verdict in a browser. That would be
a different binary, and it would carry a soundness theorem of its own.
-/

open CrabberJson

/-- Run the reader over one file. Returns whether it succeeded.

    With `dump`, also prints the converted program block by block, which is what
    lets a generated file be compared against a hand transcription. -/
def checkFile (path : System.FilePath) (dump : Bool) : IO Bool := do
  let text ← IO.FS.readFile path
  match Lean.Json.parse text >>= readChecked with
  | .error e =>
      IO.println s!"FAIL {path}\n  {e}"
      return false
  | .ok d =>
      let mut ok := true
      -- One CFG at a time, each parsed and round-tripped on its own, so a CFG
      -- the library cannot model is reported against itself rather than taking
      -- its neighbours down with it.
      for name in d.cfgNames do
        match d.rawCfg name >>= cfgChecked >>= WCfg.toProgram with
        | .error e =>
            IO.println s!"FAIL {path} [{name}]\n  {e}"
            ok := false
        | .ok p =>
            let stmts := p.labels.foldl (fun n l => n + (p.cfg.body l).length) 0
            -- `analysis` is carried as raw JSON, so the domain is dug out here
            -- rather than modelled; it is reporting, not something a proof needs.
            let domain := (d.analysis.getObjValAs? String "domain").toOption.getD "?"
            IO.println s!"ok   {path} [{p.name}] \
                          {p.labels.length} blocks, {stmts} statements, \
                          entry {p.entry}, domain {domain}"
            if dump then
              for l in p.labels do
                IO.println s!"       {l}"
                IO.println s!"         body  {repr (p.cfg.body l)}"
                IO.println s!"         succs {repr (p.cfg.succ l)}"
                IO.println s!"         inv   {repr (p.inv l)}"
      return ok

def main (args : List String) : IO UInt32 := do
  let dump := args.contains "--dump"
  let files := args.filter (· != "--dump")
  if files.isEmpty then
    IO.println "usage: checkjson [--dump] <exported.json> …"
    return 1
  let mut failures := 0
  for a in files do
    unless ← checkFile ⟨a⟩ dump do
      failures := failures + 1
  IO.println s!"\n{files.length - failures} of {files.length} documents read and \
                round-tripped; {failures} failed"
  return if failures == 0 then 0 else 1
