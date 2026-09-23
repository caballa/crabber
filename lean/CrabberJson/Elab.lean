import CrabberJson.RoundTrip
import Crabber
/-
# CrabberJson.Elab — `crab_program`, loading an export at elaboration time

    namespace MyProgram
    crab_program "exports/test-1.json" cfg "bar"

That one line reads the JSON while the file is being elaborated, converts it,
and adds the definitions a proof needs — `bodyTable`, `succTable`, `invTable`,
`labels`, `prog`, `inv` — as if they had been written out by hand.

## Why a command rather than generated source text

The alternative is a script that writes a `.lean` file. Both put the same term
in front of the kernel, but a generator adds a *printer* to the trusted path:
the JSON becomes Lean source, and nothing checks that the source says what the
JSON said. Here the data never becomes text. It is read, checked against the
document it came from (`CrabberJson.RoundTrip`), and handed to the elaborator
as a term. What stays trusted is the reader, and the reader has an inverse.

## What is trusted here, and what is not

The definitions this command adds are **data**, and data is trusted: if the
table said something other than what Crab analysed, the theorems below it would
be about the wrong program. That is the exposure the round-trip check addresses.

The *proofs* in a file using this command are not trusted at all. `crab_vc` may
be as unprincipled as convenient — the kernel checks what it produces.

## One practical caveat

Lean does not track a file read during elaboration as a build dependency, so
editing the JSON will not by itself trigger a rebuild of the module that loads
it. Re-export and rebuild from clean when the analysed program changes.
-/

namespace CrabberJson

open Lean Elab Command Term

/-! The program AST has to be convertible into a Lean term. `deriving instance`
works from outside a type's own module, which is what keeps `Lean` out of the
trusted core's imports: `Crabber.Syntax` never mentions any of this. -/

deriving instance ToExpr for Crabber.CmpOp
deriving instance ToExpr for Crabber.BoolOp
deriving instance ToExpr for Crabber.LinExp
deriving instance ToExpr for Crabber.LinCon
deriving instance ToExpr for Crabber.Atom
deriving instance ToExpr for Crabber.Stmt

/-- Add a definition holding a spliced value.

    Built as an `Expr` and installed with `addDecl` rather than by rendering a
    term and re-parsing it. `ToExpr` supplies both the value and its type, so
    there is no place for a printer to disagree with what was read. -/
private def addValueDef {α : Type} [ToExpr α] (name : Name) (v : α)
    (simpSet : Bool) : CommandElabM Unit := do
  let full := (← getCurrNamespace) ++ name
  -- `.regular 0`, not `.abbrev`: an abbreviation is unfolded eagerly, which
  -- would inline an entire block table into every definition mentioning it.
  -- `simp` unfolds these through the `crab` attribute's equation lemma instead,
  -- which does not depend on the reducibility hint.
  liftCoreM do
    addDecl (.defnDecl
      { name := full, levelParams := [], type := toTypeExpr α, value := toExpr v,
        hints := .regular 0, safety := .safe })
    -- A declaration added this way has no equation lemmas until realizations are
    -- switched on for it. Without this the definition exists but `simp` cannot
    -- unfold it, which is the whole reason it is here.
    enableRealizationsForConst full
  -- The tables must be in the set `crab_vc` unfolds; `labels` must not be, or
  -- it would be unfolded in goals that are about the label list itself.
  if simpSet then
    elabCommand (← `(command| attribute [crab] $(mkIdent name)))

/-- **`crab_program "file.json" cfg "name"`** — load one analysed cfg.

    The path is relative to the directory `lake` was invoked from. The named cfg
    must exist in the document; a document holds every cfg of the analysed file,
    so `samples/test-1.crabir` offers both `foo` and `bar`.

    Fails, with the reason, if the document cannot be read, if reading it is not
    faithful to the input, or if the program uses constructs outside the
    modelled fragment — of what a CrabIR program can contain, that is procedure
    calls, the array statements, and the two non-linear forms `y * z` and
    `y / z`, each rejected by name. Linear arithmetic is not among them: it
    arrives as an `assign` over a linear expression, whatever operators were
    written to produce it. Nor are the booleans: the six boolean statements are
    modelled, as are `havoc` of a boolean and the `bool_to_int` cast, and
    `samples/test-bool-1.crabir` is the sample that exercises them. -/
syntax (name := crabProgram) "crab_program " str " cfg " str : command

@[command_elab crabProgram]
def elabCrabProgram : CommandElab := fun stx => do
  match stx with
  | `(command| crab_program $pathStx:str cfg $cfgStx:str) => do
    let path := pathStx.getString
    let text ←
      try IO.FS.readFile path
      catch e => throwErrorAt pathStx m!"cannot read '{path}': {e.toMessageData}"
    match programOfString text cfgStx.getString with
    | .error e => throwErrorAt stx e
    | .ok p =>
      -- Tabulated over the block list, so the tables and `labels` cannot
      -- describe different sets of blocks.
      addValueDef `bodyTable (p.labels.map fun l => (l, p.cfg.body l)) true
      addValueDef `succTable (p.labels.map fun l => (l, p.cfg.succ l)) true
      addValueDef `invTable  (p.labels.map fun l => (l, p.inv l))      true
      addValueDef `labels    p.labels                                  false
      -- `prog` and `inv` are not data: they turn the tables into the total
      -- functions `Cfg` requires, via the library's `table`.
      --
      -- Every name here goes through `mkIdent`. An identifier written literally
      -- inside a quotation carries macro scopes — Lean's hygiene, which stops a
      -- macro from capturing names at the use site — and would therefore not
      -- refer to the plainly-named declarations added just above, nor be
      -- referable by the proofs that follow. `mkIdent` builds a scope-free name,
      -- which is what is wanted precisely because these *are* meant to be
      -- visible to the surrounding file.
      let progId := mkIdent `prog
      let invId  := mkIdent `inv
      let bodyId := mkIdent `bodyTable
      let succId := mkIdent `succTable
      let invTId := mkIdent `invTable
      -- `noncomputable` because these exist only to be reasoned about. A `Cfg`
      -- stores its blocks as *functions* of the label, and asking the code
      -- generator to build one from the tables is both pointless — no proof ever
      -- runs it — and, on this toolchain, enough to crash it. The tables
      -- themselves stay computable, which is what a future reflective checker
      -- would need.
      elabCommand (← `(command|
        @[crab] noncomputable def $progId : Crabber.Cfg :=
          { entry := $(quote p.entry)
            body  := Crabber.table [] $bodyId
            succ  := Crabber.table [] $succId }))
      elabCommand (← `(command|
        @[crab] noncomputable def $invId : Crabber.Label → Crabber.Assn :=
          Crabber.table Crabber.Assn.bot $invTId))
  | _ => throwUnsupportedSyntax

/-! ## `crab_verify` — the proofs, for a program `crab_program` has loaded

    crab_program "exports/test-1.json" cfg "bar"
    crab_verify

Adds `body_keys`, `succ_keys`, `vc_all`, `initiation` and the theorem that
bundles them. It is a second command rather than part of `crab_program` so
that a file can load a program and then reason about it by hand — which is what
the worked example under `Samples/` does.

**Why the proofs are generated here rather than written as reusable tactics.**
Nothing in these scripts depends on the program: none of them counts blocks, and
the case analysis over labels is `repeat'` over however many alternatives `simp`
produced, so three blocks and thirty take the same script. They could therefore
be tactics in the library — except that they must mention `prog`, `inv`,
`labels` and the tables, which live in the *generated file's* namespace and are
invisible to a macro defined elsewhere. Passing seven identifiers to every
tactic call is the alternative, and it is worse to read. Here the elaborator has
already built each name with `mkIdent`, so it can splice them directly.

**These proofs are not trusted.** A tactic that goes wrong fails to find a proof,
or produces one the kernel rejects; it cannot produce a false theorem. What is
trusted is the data `crab_program` installed above.

**When it fails.** The invariants may genuinely not be inductive; the arithmetic
may be beyond `omega`; the entry invariant may not be ⊤; or the program may have
an assertion that really can fail, which under the current reading of `assert`
makes a block's verification condition false rather than merely hard. A failure
here is never by itself evidence that Crab is wrong. -/
/-- The entry obligation, emitted under whatever name the caller wants.

    Shared by `crab_verify` and `crab_verify_init` so the two cannot drift; the
    lesson of the `crab_meaning` set below applies to whole proof scripts too. -/
private def emitInitiation (thmName : Name) : CommandElabM Unit := do
  let progId := mkIdent `prog
  let invId  := mkIdent `inv
  let initId := mkIdent thmName
  -- `InitState` constrains nothing, so this goes through exactly when Crab
  -- claimed ⊤ at the entry block.
  elabCommand (← `(command|
    theorem $initId : ∀ σ : Crabber.State, Crabber.InitState $progId σ →
        Crabber.Assn.holds ($invId ($progId).entry) σ := by
      intro σ _
      -- Work out *which* invariant the entry block has, by evaluating the
      -- lookup rather than by rewriting it. `conv` aims at argument 1 of
      -- `Assn.holds` -- the invariant -- and `whnf` reduces it there.
      --
      -- `inv` is `table Assn.bot invTable`, a linear scan comparing the entry
      -- label against each key, so `inv prog.entry` is a chain of `if`s over
      -- string equalities. `simp` used to do that chain, and it is the wrong
      -- tool twice over: unfolding `invTable` pastes every block's invariant
      -- into the goal, which simp then rescans after each of the six steps,
      -- and every `if` needs a `String` disequality decided -- which, since a
      -- `String` is a `List Char` and a `Char` carries a validity proof, is
      -- nothing like comparing bytes.
      --
      -- The cost is superlinear in the label lengths, and it is paid by every
      -- program, before anything about the invariant is even looked at. On
      -- `test-9 -d pk` -- labels like `edge-loop_header-loop_body` -- it stopped
      -- being survivable: 117s of `simp` and then a `whnf` timeout at 4M
      -- heartbeats, for a lookup `rfl` does instantly. Hence doing it the way
      -- `rfl` does.
      --
      -- `whnf` stops at the outermost constructor, which is enough: the
      -- expensive part is the scan, and the `simp` below finishes the rest.
      conv => enter [1]; whnf
      first
        | exact Crabber.Assn.holds_top σ
        -- `crab_meaning`, not a list spelled out here: this proof and `crab_vc`
        -- need the same unfoldings, and when the list was written out twice the
        -- copies drifted. See `Crabber.Tactic` for what that cost.
        --
        -- `all_goals omega`, not `omega`: an entry invariant that is trivially
        -- true without being literally ⊤ -- `[[0 ≤ 0]]`, which the octagon
        -- domain exports where the interval domain exports an empty conjunction
        -- -- is closed by `simp` alone, and `omega` would then fail for want of
        -- a goal.
        | (simp [crab_meaning]
           all_goals omega)))

syntax (name := crabVerify) "crab_verify" : command

@[command_elab crabVerify]
def elabCrabVerify : CommandElab := fun _ => do
  -- Same `mkIdent` discipline as above: these have to name the declarations the
  -- surrounding file can see, so they must carry no macro scopes.
  let progId     := mkIdent `prog
  let invId      := mkIdent `inv
  let labelsId   := mkIdent `labels
  let bodyId     := mkIdent `bodyTable
  let succId     := mkIdent `succTable
  let bodyKeysId := mkIdent `body_keys
  let succKeysId := mkIdent `succ_keys
  let vcAllId    := mkIdent `vc_all
  let initId     := mkIdent `initiation
  let resultId   := mkIdent `verified_program

  -- The tables and `labels` are built from one list, so these hold by
  -- computation: both sides are literals.
  elabCommand (← `(command|
    theorem $bodyKeysId : List.map Prod.fst $bodyId = $labelsId := rfl))
  elabCommand (← `(command|
    theorem $succKeysId : List.map Prod.fst $succId = $labelsId := rfl))

  -- Every label's obligation: the blocks that exist, then every other string.
  elabCommand (← `(command|
    theorem $vcAllId : ∀ B : Crabber.Label, Crabber.VC $progId $invId B := by
      refine Crabber.vc_all_of_blocks $progId $invId $labelsId ?_ ?_ ?_
      · intro B h
        show Crabber.table [] $bodyId B = []
        exact Crabber.table_not_mem [] $bodyId B ($bodyKeysId ▸ h)
      · intro B h
        show Crabber.table [] $succId B = []
        exact Crabber.table_not_mem [] $succId B ($succKeysId ▸ h)
      · intro B hB
        simp only [$labelsId:ident, List.mem_cons, List.not_mem_nil, or_false] at hB
        repeat' (rcases hB with rfl | hB)
        -- `rfl` written inside a quotation carries macro scopes, so `rcases`
        -- reads it as a fresh name rather than as the substitution pattern: the
        -- equation lands in the context instead of being applied. `subst_vars`
        -- applies whatever equations ended up there, which is what was meant.
        all_goals (try subst_vars)
        all_goals crab_vc))

  -- The entry obligation, under its usual name.
  emitInitiation `initiation

  -- The assertion obligations are *not* generated. `wpStmt` puts an assert's
  -- obligation inside its block's verification condition, so `Crabber.chk_of_VC`
  -- extracts it from `vc_all` for every program at once. What used to stand here
  -- was a per-program case split over labels followed by a statement-by-statement
  -- peel of the prefix — a script that re-derived, once per program, something
  -- true of all of them. See `chk_of_VC` for the one assumption it rests on.

  -- The result. `verified` chains the adapter lemma, the extraction lemma, the
  -- inductive-assertion meta-theorem and assertion safety, so nothing above
  -- mentions `Step`, `Reachable` or `wp_sound`.
  elabCommand (← `(command|
    theorem $resultId :
        Crabber.InvariantOf $progId $invId ∧ ¬ Crabber.AssertFails $progId :=
      Crabber.verified $progId $invId $initId $vcAllId))

/-! ## Asking a narrower question

`crab_verify` proves the whole thing or reports one failure, and the failure is
reported *at the command*, because every theorem below it is built from a
quotation and a quotation carries no source position. So "omega could not prove
the goal, line 5, column 0" is the entire diagnosis, whether what failed was the
entry obligation or one block out of thirty.

The three commands here let the question be narrowed instead. They exist only
for debugging, they are what `crabber --lean-only` and `--lean-block` generate,
and none of them builds `verified_program`: proving a subset of the obligations
establishes nothing on its own, and none of these should ever be mistaken for a
verified program.

Their ancestor is a scratch file written by hand — `example : VC prog inv "body"
:= by crab_vc`, once per label, to find which block was failing. That worked and
took twenty minutes; this is the same idea with the labels checked. -/

/-- The `labels` list of the program loaded in this namespace.

    Read back out of the declaration `crab_program` installed, by taking apart
    the `List String` literal `ToExpr` built. The alternative, `evalExpr`, is
    `unsafe` and would need an `implemented_by` dance for something this small.

    Reading it matters because an unknown label is *provable*: `Cfg.body` and
    `Cfg.succ` are total and default to `[]`, so `VC prog inv "tpyo"` is the
    trivial obligation and `crab_vc` discharges it. A mistyped `--lean-block`
    would report "proved" without having checked anything. -/
private partial def decodeLabels (e : Expr) : Option (List String) :=
  match e.getAppFnArgs with
  | (``List.nil, _)            => some []
  | (``List.cons, #[_, x, xs]) =>
      match x with
      | .lit (.strVal s) => (decodeLabels xs).map (s :: ·)
      | _                => none
  | _ => none

private def programLabels : CommandElabM (List String) := do
  let name := (← getCurrNamespace) ++ `labels
  let some info := (← getEnv).find? name
    | throwError "no program is loaded in this namespace: \
                  run `crab_program` before this command"
  let some value := info.value?
    | throwError "'{name}' has no value to read the block list from"
  let some ls := decodeLabels value
    | throwError "cannot read the block list out of '{name}'"
  return ls

/-- One block's verification condition, as a theorem named after the block. -/
private def emitBlockVc (label : String) : CommandElabM Unit := do
  let progId := mkIdent `prog
  let invId  := mkIdent `inv
  -- The label verbatim, so the declaration the error names is the block the
  -- user asked about. Labels are CrabIR block names and routinely contain
  -- characters an identifier may not -- `edge-header-body` is one crabber
  -- generates itself -- which Lean prints back guillemet-quoted.
  let thmId  := mkIdent (Name.mkSimple s!"vc_{label}")
  elabCommand (← `(command|
    theorem $thmId : Crabber.VC $progId $invId $(quote label) := by crab_vc))

/-- **`crab_verify_init`** — the entry obligation alone.

    Crab claimed something at the entry block; this asks whether it is implied by
    `InitState`, which constrains nothing. Cheap, and independent of every block,
    so it is the first thing to try when `crab_verify` fails and the blocks look
    innocent. -/
syntax (name := crabVerifyInit) "crab_verify_init" : command

@[command_elab crabVerifyInit]
def elabCrabVerifyInit : CommandElab := fun _ => do
  emitInitiation `initiation

/-- **`crab_verify_block "body"`** — one block's verification condition.

    Fails, naming the blocks that do exist, if the label names none of them. -/
syntax (name := crabVerifyBlock) "crab_verify_block " str : command

@[command_elab crabVerifyBlock]
def elabCrabVerifyBlock : CommandElab := fun stx => do
  match stx with
  | `(command| crab_verify_block $labelStx:str) => do
    let label := labelStx.getString
    let ls ← programLabels
    unless ls.contains label do
      throwErrorAt labelStx
        "this cfg has no block named '{label}'. Its blocks are: {", ".intercalate ls}"
    emitBlockVc label
  | _ => throwUnsupportedSyntax

/-- **`crab_verify_blocks`** — every block's verification condition, separately.

    One theorem per block rather than `crab_verify`'s single `vc_all`, which
    buys two things. A failure names the block it belongs to. And because each
    is its own declaration, they all elaborate: *every* failing block is
    reported, where `vc_all`'s `all_goals crab_vc` stops at the first. -/
syntax (name := crabVerifyBlocks) "crab_verify_blocks" : command

@[command_elab crabVerifyBlocks]
def elabCrabVerifyBlocks : CommandElab := fun _ => do
  for label in (← programLabels) do
    emitBlockVc label

end CrabberJson
