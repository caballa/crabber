import Lean
import Crabber.VC
/-
# Crabber.Explain — saying out loud what the proof did

**Untrusted, and inert.** Nothing here is used by any proof. It registers one
option, pretty-prints program data, and logs goals Lean had already built. The
worst a bug here can do is describe a proof badly; the proof itself is checked
by the kernel either way.

## Why the narration is written on this side

`crabber --verify-with-lean` prints one line per procedure, and that line is a
verdict. It is the whole answer to "is Crab right" and no answer at all to "what
did Lean just do". The tempting place to answer the second question is crabber
itself, which already has the blocks and the invariants in memory — and it is the
wrong place, for the same reason `describe` in `lean_verify.cpp` is careful never
to say more than Lean reported. A narration composed on the C++ side is a *claim*
about a proof it did not perform: it would go on reading plausibly long after the
proof it describes stopped resembling it, and it would describe steps even on a
build where Lean was never run.

So the narration comes from the side holding the goals. Every line below is data
Lean read, a lemma Lean applied, or a goal produced by Lean's own pretty-printer.
crabber only relays it.

## What is narrated

`set_option crabber.explain true` — which `--lean-show-steps` writes into the
generated file — turns on four stages:

  * the program and the invariants as `crab_program` read them: the trusted half;
  * the entry obligation, and which of its two branches closed it;
  * one verification condition per block, shown as the arithmetic `crab_vc` hands
    to `omega` once the unfolding is done;
  * the final theorem, the lemmas it is assembled from, and the axioms it
    depends on.

The stages are named rather than numbered because a narrowed run — `--lean-only
init`, `--lean-block` — prints a subset, and "step 2 of 4" would then be a
promise about steps nobody asked for.

**They come out in order only with `set_option Elab.async false`.** Lean
elaborates declaration bodies asynchronously, so the messages a *tactic* logs are
appended after those its surrounding command logged — which puts every goal after
every piece of prose, and the blocks after the result they feed into. crabber's
`--lean-show-steps` writes both options into the generated file for that reason.
Narration read out of order is worse than no narration: it invites the reader to
infer a dependency that runs the other way.

The block stage is the point of the exercise. The rest is prose that could have been
written in a document; a goal is the actual state of the proof, and for a block
that did *not* go through it is exactly where the reasoning ran out.

## Why printers, rather than `Repr`

The datatypes all derive `Repr`, and `Repr` prints constructors:
`[[Crabber.Atom.lin { op := CmpOp.le, terms := [(1, "y")], const := 9 }]]`. That
is the right output for debugging the reader and the wrong output for reading an
invariant, which is what this stage is for. The printers below say `y ≤ 9`, in
the surface syntax the program was written in, so the table the first stage prints
can be compared against the `.crabir` file by eye.
-/

namespace Crabber

open Lean

register_option crabber.explain : Bool := {
  defValue := false
  descr := "report the proof steps as info messages: the data read, each \
obligation, and the arithmetic handed to omega"
}

/-- Whether the narration was asked for.

    Read from the options rather than passed around, because the two places that
    narrate — a command elaborator and a tactic — have no channel between them. -/
def explaining [Monad m] [MonadOptions m] : m Bool :=
  return crabber.explain.get (← getOptions)

/-- The tag every narrated line carries.

    **A contract with `extractSteps` in `src/lean_verify.cpp`**, which keeps the
    tagged lines and drops the tag. Both sides spell it out; grep for it there
    before changing it here.

    It exists because `lean` prints an *error* with a `file:line:col:` prefix and
    an *info* message with no prefix at all, so nothing in the output otherwise
    distinguishes a line of narration from the text of a diagnostic — or from
    whatever lake decides to say. Tagging every line, rather than bracketing each
    message, means a message's own line breaks (a goal spans several) need no
    agreement between the two sides, and that narration stays recognisable in the
    raw output `--lean-show-output` prints. -/
def explainTag : String := "crabber| "

/-- Log `msg`, tagged, but only when narrating.

    `logInfo` rather than `IO.println`: an info message goes through Lean's
    message log, so it survives a later error in the same command — which is what
    makes the stages before a failing block visible — and it reaches crabber
    through the same channel as every diagnostic.

    The message is rendered here rather than handed to `logInfo` as structured
    data, because tagging is per line and the line breaks are only known once the
    pretty-printer has run. `addMessageContext` supplies the environment and the
    options it needs to run, which is what `logInfo` would have done itself. -/
def explain [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]
    [MonadLiftT BaseIO m] (msg : MessageData) : m Unit := do
  unless ← explaining do return
  let text ← liftM (n := m) (← addMessageContext msg).toString
  let tagged := "\n".intercalate ((text.splitOn "\n").map (explainTag ++ ·))
  logInfo tagged

open Elab Tactic in
/-- **`crab_explain "…"`** — a line of narration from inside a proof script.

    For the facts only the running tactic knows. The entry obligation has two
    ways of closing, and which one it took is a property of the invariant Crab
    exported — `⊤` from the native domains, `0 ≤ 0` from the Apron-backed ones —
    so the branch that succeeds is the only place that can report it. -/
elab "crab_explain " s:str : tactic => explain m!"{s.getString}"

/-! ## Printing the data in the syntax it was written in -/

/-- `2*y`, `y`, `-y` — a coefficient and its variable, with the two units special
    cased because `1*y` reads worse than `y`. -/
private def termPretty (c : Int) (v : Var) : String :=
  if c == 1 then v else if c == -1 then "-" ++ v else s!"{c}*{v}"

/-- A sum of terms, with `+ -3*z` folded back into `- 3*z`.

    Done as a rewrite of the assembled string rather than by tracking signs while
    folding: the sign of a term is already in the term, and the only thing wanted
    here is not to print the two operators next to each other. -/
private def sumPretty (terms : List (Int × Var)) : String :=
  (String.intercalate " + " (terms.map fun (c, v) => termPretty c v)).replace
    " + -" " - "

def CmpOp.pretty : CmpOp → String
  | .le => "≤"
  | .lt => "<"
  | .eq => "="
  | .ne => "≠"

def LinExp.pretty (e : LinExp) : String :=
  match e.terms with
  | [] => toString e.const
  | _  =>
    let s := sumPretty e.terms
    if e.const == 0 then s
    else if e.const < 0 then s!"{s} - {-e.const}"
    else s!"{s} + {e.const}"

/-- `y ≤ 9`. An empty left-hand side prints as `0`, which is what the nullary
    constraint the Apron domains export (`{"op": "true"}`, read as `0 ≤ 0`)
    means. -/
def LinCon.pretty (c : LinCon) : String :=
  let lhs := match c.terms with
    | [] => "0"
    | _  => sumPretty c.terms
  s!"{lhs} {c.op.pretty} {c.const}"

def BoolOp.pretty : BoolOp → String
  | .and => "and"
  | .or  => "or"
  | .xor => "xor"

def Atom.pretty : Atom → String
  | .lin c    => c.pretty
  | .bool x v => s!"{x} = {v}"

/-- A conjunct. Empty means "no constraints", which is `True`. -/
def Conj.pretty (k : Conj) : String :=
  match k with
  | [] => "true"
  | _  => String.intercalate " ∧ " (k.map Atom.pretty)

/-- An invariant.

    The two degenerate cases are named rather than printed as their list
    encodings, because `⊥` is the claim "this block is unreachable" and that is
    worth seeing at a glance; `[]` would not say it. -/
def Assn.pretty (A : Assn) : String :=
  match A with
  | []   => "⊥ (block unreachable)"
  | [[]] => "⊤"
  | [k]  => k.pretty
  | _    => String.intercalate " ∨ " (A.map fun k => s!"({k.pretty})")

/-- A statement, in CrabIR's surface syntax rather than as a constructor. -/
def Stmt.pretty : Stmt → String
  | .assign x e          => s!"{x} := {e.pretty}"
  | .havoc x             => s!"havoc({x})"
  | .assume c            => s!"assume({c.pretty})"
  | .assert c            => s!"assert({c.pretty})"
  | .boolAssignCst x c   => s!"{x} := {c.pretty}"
  | .boolAssignVar x y n => s!"{x} := " ++ (if n then s!"not({y})" else y)
  | .boolBinop x op y z  => s!"{x} := {y} {op.pretty} {z}"
  | .boolAssume y n      => s!"assume({if n then s!"not({y})" else y})"
  | .boolAssert y        => s!"assert({y})"
  | .boolHavoc x         => s!"havoc({x}:bool)"
  | .boolToInt x b       => s!"{x} := bool_to_int({b})"

/-! ## The program, as Lean read it -/

/-- The data `crab_program` installed, one paragraph per block.

    Takes the pieces rather than the reader's `Program` record, which keeps this
    file — and with it the option and the tactic support — independent of
    `CrabberJson` and of `Lean.Json`.

    A block prints its invariant on the label line and then its body and
    successors, rather than everything in one aligned row. Blocks of a dozen
    statements are ordinary (the boolean sample has one), and a table wide enough
    for those wraps in a terminal, which loses the alignment that was the reason
    for the table. -/
def explainProgram [Monad m] [MonadLog m] [AddMessageContext m] [MonadOptions m]
    [MonadLiftT BaseIO m]
    (name entry : String) (labels : List Label) (body : Label → List Stmt)
    (succ : Label → List Label) (inv : Label → Assn) : m Unit := do
  unless ← explaining do return
  let blocks := labels.map fun l =>
    let stmts := (body l).map fun s => m!"{s.pretty}"
    let succs := match succ l with
      | [] => m!"→ (no successors)"
      | ss => m!"→ {String.intercalate ", " ss}"
    let lines := (if stmts.isEmpty then [m!"(empty body)"] else stmts) ++ [succs]
    m!"{l}    invariant: {(inv l).pretty}{indentD (MessageData.joinSep lines "\n")}"
  -- The prose is broken into lines here rather than left to the formatter: a
  -- plain string is one atom to Lean's pretty-printer, which will not wrap it,
  -- and crabber indents every line of this again when it relays it.
  explain m!"\
    * the program and the invariants, as Lean read them\n\
    procedure {name}, entry block {entry}, {labels.length} block(s).\n\
    This is the data half, and the only part of the run that is trusted: the\n\
    theorems below are about exactly this program. The reader that produced it\n\
    is checked against the document it read (CrabberJson.RoundTrip). The CFG is\n\
    the one Crab analysed, so the blocks carrying compiled-away guards are here\n\
    too, and the invariants are in the form the domain exported them.\
    {indentD (MessageData.joinSep blocks "\n")}"

/-! ## The arithmetic each block came down to

The other stages are prose the command elaborators write; this one has to be read
out of the proof while it runs, which is why it lives in a tactic. -/

open Elab Tactic in
/-- The block a `VC` goal is about, when the goal names one literally.

    `vc_all`'s script reaches `VC prog inv "loop"` by case analysis over the label
    list, so the label is a literal by the time `crab_vc` sees it. Before the
    substitution it is a local, and then there is no block to name — hence the
    `Option` rather than an error: a `crab_vc` used by hand on an open goal should
    still narrate its arithmetic. -/
def vcLabel? (goal : Expr) : Option String :=
  match goal.consumeMData.getAppFnArgs with
  | (``Crabber.VC, #[_, _, b]) =>
    match b.consumeMData with
    | .lit (.strVal s) => some s
    | _                => none
  | _ => none

open Elab Tactic in
/-- What `crab_vc` is about to work on, named for the narration. -/
def vcHeader : TacticM MessageData := do
  if (← getGoals).isEmpty then
    return m!"(no goal)"
  match vcLabel? (← instantiateMVars (← (← getMainGoal).getType)) with
  | some l => return m!"block {l}"
  | none   => return m!"the goal"

open Elab Tactic in
/-- Report the goals as they stand, under `header`.

    Printed with `MessageData.ofGoal`, which is Lean's own goal display — the
    hypotheses `crab_vc` introduced and the target it is about to decide, exactly
    as an editor would show them. Nothing is reformatted: a narration that
    paraphrased the goal could paraphrase it wrongly.

    The case tag is cleared first. A goal reached through `vc_all`'s case analysis
    carries one — `case refine_3.inr.inr.inl` — and it names a branch of a
    `rcases` chain this development generated, so it tells a reader nothing the
    header does not say better. Clearing it only changes how the goal prints.

    No goals means the simplifier finished the block on its own, which is worth
    saying rather than passing over: it is the normal outcome for a block whose
    successors carry no constraints. -/
def explainGoals (header : MessageData) (what : String) : TacticM Unit := do
  unless ← explaining do return
  let gs ← getGoals
  if gs.isEmpty then
    explain m!"{header} · closed by simp alone; no arithmetic was left for omega"
  else
    for g in gs do g.setTag .anonymous
    explain
      m!"{header} · {what}{indentD (MessageData.joinSep (gs.map MessageData.ofGoal) "\n")}"

open Elab Tactic in
/-- Report the goals only if there are any, saying nothing when there are not.

    The companion to `explainGoals`, for the *second* report `crab_vc` makes. By
    then a closed goal was closed by `omega`, not by the simplifier, and the note
    `explainGoals` prints in that case would be false. Usually nothing survives to
    that point, and then this stays quiet, which is the intent: the second pass
    exists for the boolean blocks that need it, and only those should mention
    it. -/
def explainRemaining (header : MessageData) (what : String) : TacticM Unit := do
  unless ← explaining do return
  unless (← getGoals).isEmpty do explainGoals header what

end Crabber
