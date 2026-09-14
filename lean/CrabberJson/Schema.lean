import Lean
import Crabber.Syntax
import Crabber.Assn
/-
# CrabberJson.Schema — reading crabber's JSON export

`crabber --print-invariants-to-json out.json` emits one self-contained document
holding, for every block, its statements, its successors *and* the invariant
Crab inferred for it. This module turns that document into the data the proof
library consumes: a `Cfg` and a `Label → Assn`.

## Why this is two layers rather than one

The types below (`W…`, for "wire") mirror the JSON **exactly** — same fields,
same names, same nesting, including information the proof library has no use
for, such as bitwidths and source locations. Only afterwards does a separate
conversion drop what is unused and build `Cfg`/`Assn`.

The extra layer buys a check. Because the wire types are faithful, they can be
written *back* to JSON and compared against the document that was read. A
mapping that silently drops a statement, or misreads a coefficient, produces a
document that differs from the input, and the comparison catches it. Converting
straight to `Cfg` would make that impossible: `Cfg` has function fields and has
already discarded the bitwidths, so there would be nothing to compare.

Most of the mapping is not written by hand at all. Lean's derived JSON encoding
for a *structure* is a flat object of its fields, which is precisely the shape
crabber emits, so `deriving FromJson, ToJson` is exact for every record here.
Only the two tagged unions — statements, keyed by `"stmt"`, and invariants,
keyed by `"kind"` — use a discriminator convention of their own and need
instances written out.

## Trust

This module is **trusted**: nothing here is proved, and a bug that mistranslated
the program or the invariant would let the library prove a theorem about
something other than what Crab analysed. That is what the round-trip comparison
in `CrabberJson.RoundTrip` is for. The conversion is deliberately total and
fail-loud — every unsupported construct raises an error naming itself, and
nothing is ever skipped.
-/

namespace CrabberJson

open Lean (Json FromJson ToJson fromJson? toJson)
open Crabber

/-! ## Wire types

One per JSON object in the export. Field names are the JSON keys verbatim; do
not rename them, as the derived instances are what make the names load-bearing.
-/

/-- Raw JSON has no `Repr`, and the records below carry some verbatim. Showing
    it as its own compact text beats a constructor tree, so this is what `#eval`
    on a wire record prints for the parts nothing interprets. -/
instance : Repr Json := ⟨fun j _ => Std.Format.text j.compress⟩

/-- A CrabIR type: `{"kind": "int", "bitwidth": 32}`.

    `bitwidth` is carried only by `int`; `bool` and `int_array` omit the key
    entirely, so it is optional here. Note the export distinguishes *omitted*
    from *null*, and uses both — a missing bitwidth is an absent key, whereas an
    untyped expression is an explicit `null` (see `WExp`). The instances below
    have to preserve that difference for the round trip to mean anything. -/
structure WTy where
  kind      : String
  bitwidth  : Option Nat := none
  deriving FromJson, Repr, BEq

/-- One object field, present only when the value is.

    Needed because the export distinguishes an omitted key from a null one, and
    Lean's derived encoding does not: it writes `none` as an explicit `null`.
    Using the derived instance where crabber omits the key produces a document
    that differs from the input — which the round-trip check reports, and which
    is how this was found rather than reasoned about. -/
private def optField [ToJson α] (k : String) : Option α → List (String × Json)
  | some x => [(k, toJson x)]
  | none   => []

instance : ToJson WTy where
  toJson t := Json.mkObj (("kind", toJson t.kind) :: optField "bitwidth" t.bitwidth)

/-- A variable occurrence: `{"name": "x", "type": {...}}`. -/
structure WVar where
  name : String
  type : WTy
  deriving FromJson, ToJson, Repr, BEq

/-! ### Parts the proof never looks at

Several pieces of the export exist for provenance or for other consumers, and
nothing in the proof depends on them: where an assertion was written, the
function signature, which file was analysed, which domain ran, and Crab's own
verdict on each assertion.

They are held as raw `Lean.Json` rather than modelled with a record apiece.
Deleting them instead would be the obvious move, but it would quietly gut the
round-trip check: an unmodelled key is dropped on read and missing on write, so
every document would fail to reproduce. Carrying them opaquely keeps the check
over the *whole* document — `Json`'s own JSON instances are the identity, so a
value read into one of these fields is written back byte for byte — while
costing no types and no maintenance when a field is added to one of them.

The one to revisit is `checks`. Crab's per-assertion verdicts are exactly what a
finished `chk` should be compared against — Crab says "safe", Lean either proves
it or does not, and a disagreement is the interesting signal. When that
comparison is built, `checks` earns a real type. -/

/-- A linear expression: `{"type", "terms": [["1","y"]], "const": "9"}`.

    Coefficients and constants are **decimal strings**, not JSON numbers: Crab's
    numbers are arbitrary precision, and most JSON consumers would round them
    through a double. They are parsed to `Int` during conversion, not here.

    `type` is `null` when the expression is a bare constant — `x := 0` has no
    variable for Crab to take a type from. So an absent type is not missing
    information; it says the expression mentions no variables, which the
    conversion below checks rather than assumes. -/
structure WExp where
  type  : Option WTy
  terms : Array (Array String)
  const : String
  deriving Repr, BEq

/-- A linear constraint.

    Usually a comparison — a `WExp` plus an operator — but a domain may also
    export the two *nullary* constraints, written `{"op": "true"}` and
    `{"op": "false"}` with no other keys. The octagon domain emits `true` for a
    block it knows nothing about, where the interval domain emits an empty
    conjunction instead, so which of these appears depends on the domain rather
    than on the program. -/
inductive WCon where
  /-- `{"op": "true"}` — a constraint that constrains nothing. -/
  | tt
  /-- `{"op": "false"}` — an unsatisfiable constraint. -/
  | ff
  /-- A comparison. `type` is optional for the same reason as in `WExp`. -/
  | cmp (op : String) (type : Option WTy) (terms : Array (Array String))
        (const : String)
  deriving Repr, BEq

/-- A statement, tagged by the `"stmt"` key.

    The four of the numeric core and the six boolean ones. The remaining kinds
    crabber can emit — `binop`, `select`, `cast`, `unreachable`, the four array
    ones, `callsite` and the reference/region family — are rejected by name when
    read, rather than given a constructor here that the semantics could not
    interpret. -/
inductive WStmt where
  | assign (lhs : WVar) (rhs : WExp)
  | assume (cond : WCon)
  | assert (cond : WCon) (loc : Json)
  | havoc  (lhs : WVar)
  /-- `bool_assign_cst`. The right-hand side is either a linear constraint or a
      *reference* constraint, and the export says which in a sibling `cst_kind`
      key rather than by the shape of `rhs`.

      `rhs` is kept as raw `Json` for exactly that reason: its schema depends on
      another field, and only one of the two schemas is modelled. References are
      not, so parsing `rhs` is deferred to the conversion below, which reads it
      as a `WCon` when `cst_kind` is `"linear"` and refuses it by name otherwise.
      Holding it opaquely also keeps the round trip exact either way — `Json`'s
      own JSON instances are the identity — so a document containing a reference
      constraint is still reported against the construct, not against the
      reader. -/
  | boolAssignCst (cstKind : String) (rhs : Json) (lhs : WVar)
  /-- `bool_assign_var`. `negated` carries `b := not(c)`; Crab has no separate
      unary boolean statement. -/
  | boolAssignVar (rhs : WVar) (negated : Bool) (lhs : WVar)
  /-- `bool_binop`, with `op` one of `"and"`, `"or"`, `"xor"`. -/
  | boolBinop (op : String) (left : WVar) (right : WVar) (lhs : WVar)
  /-- `bool_assume`, with the same `negated` flag. -/
  | boolAssume (cond : WVar) (negated : Bool)
  /-- `bool_assert`. No `negated` key — the export does not write one here. -/
  | boolAssert (cond : WVar) (loc : Json)
  /-- `bool_select`. Crab's own parser cannot produce one; the export can. -/
  | boolSelect (cond : WVar) (left : WVar) (right : WVar) (lhs : WVar)
  deriving Repr, BEq

/-- An invariant, tagged by the `"kind"` key: `"true"`, `"false"`, or a
    `"disj"` of conjunctions. Top and bottom are explicit in the export because
    an empty list of disjuncts would be ambiguous on the wire. -/
inductive WInv where
  | top
  | bot
  | disj (disjuncts : Array (Array WCon))
  deriving Repr, BEq

/-- A block: everything Crab knows about it, in one object. This is the shape
    that makes a separate CFG document unnecessary — statements, successors and
    the inferred invariant cannot disagree about which block they describe. -/
structure WBlock where
  label     : String
  stmts     : Array WStmt
  invariant : WInv
  succs     : Array String
  deriving Repr, BEq

/-- One analysed CFG. A document holds several — `samples/test-1.crabir` has
    `foo` and `bar` — so a caller must say which one it means.

    `declaration` (the signature) and `exit` (the final block, `null` for two of
    the samples) are carried verbatim. Neither reaches a proof: the obligation
    for a block with no successors is discharged by the empty conjunction, not by
    knowing which block is final. -/
structure WCfg where
  name        : String
  declaration : Json
  entry       : String
  exit        : Json
  blocks      : Array WBlock
  deriving Repr, BEq

/-- The whole document.

    `schema` and `kind` are checked; the rest of the header — which file was
    analysed, how the CFG was built, which domain ran, and Crab's own verdict on
    each assertion — passes through untouched.

    **`cfgs` is deliberately left unparsed.** A document holds every CFG of the
    analysed file, and they are independent: one may use a construct this
    library does not model while another is perfectly ordinary. Parsing the
    array eagerly would make a single unsupported CFG condemn all of them —
    `samples/test-call-1.crabir` has a `main` that calls, and an `inc` that
    contains nothing but an assignment, and there is no reason the second should
    be unreadable because of the first.

    So a CFG is parsed only when it is asked for, and only that one has to
    succeed. The round-trip check moves with it: it is applied to the selected
    CFG against the JSON it came from, which is where it was doing the work
    anyway. -/
structure WDoc where
  schema   : Nat
  kind     : String
  source   : Json
  options  : Json
  analysis : Json
  cfgs     : Array Json
  checks   : Json
  deriving Repr, BEq

/-! ## The two hand-written instances

Everything above is a record, and Lean's derived encoding for a record is a flat
object of its fields — exactly crabber's shape. The two tagged unions are the
exception: Lean would encode `WStmt.assume c` as `{"assume": …}`, whereas the
export writes `{"stmt": "assume", "cond": …}`. So these four instances are the
only place where the correspondence between Lean and the schema is asserted by
hand, and the only place a typo could go unnoticed by the compiler. -/

/-! The three records carrying an *explicitly null* field are written out too.
Lean's derived encoding omits a `none`, whereas crabber writes `null`, and the
round trip only means something if that distinction survives it. (Contrast
`WTy.bitwidth`, where crabber omits the key and the derived behaviour is
therefore already right.) -/

instance : FromJson WExp where
  fromJson? j := do
    return { type  := ← j.getObjValAs? (Option WTy) "type"
             terms := ← j.getObjValAs? (Array (Array String)) "terms"
             const := ← j.getObjValAs? String "const" }

instance : ToJson WExp where
  toJson e := Json.mkObj
    [("type", toJson e.type), ("terms", toJson e.terms), ("const", toJson e.const)]

instance : FromJson WCon where
  fromJson? j := do
    match ← j.getObjValAs? String "op" with
    -- The nullary forms carry no other keys, so they must be recognised before
    -- anything tries to read a term list that is not there.
    | "true"  => return .tt
    | "false" => return .ff
    | op =>
      return .cmp op (← j.getObjValAs? (Option WTy) "type")
                     (← j.getObjValAs? (Array (Array String)) "terms")
                     (← j.getObjValAs? String "const")

instance : ToJson WCon where
  toJson
    | .tt => Json.mkObj [("op", "true")]
    | .ff => Json.mkObj [("op", "false")]
    | .cmp op type terms const => Json.mkObj
        [("op", toJson op), ("type", toJson type),
         ("terms", toJson terms), ("const", toJson const)]

instance : FromJson WStmt where
  fromJson? j := do
    match ← j.getObjValAs? String "stmt" with
    | "assign" => return .assign (← j.getObjValAs? WVar "lhs") (← j.getObjValAs? WExp "rhs")
    | "assume" => return .assume (← j.getObjValAs? WCon "cond")
    | "assert" => return .assert (← j.getObjValAs? WCon "cond") (← j.getObjValAs? Json "loc")
    | "havoc"  => return .havoc  (← j.getObjValAs? WVar "lhs")
    | "bool_assign_cst" =>
      return .boolAssignCst (← j.getObjValAs? String "cst_kind")
                            (← j.getObjValAs? Json "rhs")
                            (← j.getObjValAs? WVar "lhs")
    | "bool_assign_var" =>
      return .boolAssignVar (← j.getObjValAs? WVar "rhs")
                            (← j.getObjValAs? Bool "negated")
                            (← j.getObjValAs? WVar "lhs")
    | "bool_binop" =>
      return .boolBinop (← j.getObjValAs? String "op")
                        (← j.getObjValAs? WVar "left")
                        (← j.getObjValAs? WVar "right")
                        (← j.getObjValAs? WVar "lhs")
    | "bool_assume" =>
      return .boolAssume (← j.getObjValAs? WVar "cond")
                         (← j.getObjValAs? Bool "negated")
    | "bool_assert" =>
      return .boolAssert (← j.getObjValAs? WVar "cond") (← j.getObjValAs? Json "loc")
    | "bool_select" =>
      return .boolSelect (← j.getObjValAs? WVar "cond")
                         (← j.getObjValAs? WVar "left")
                         (← j.getObjValAs? WVar "right")
                         (← j.getObjValAs? WVar "lhs")
    | other    =>
      throw s!"statement kind '{other}' is outside the fragment this library \
               models (assign, assume, assert, havoc, and the six boolean \
               statements). It is rejected rather than skipped: dropping a \
               statement would weaken every proof obligation in its block."

instance : ToJson WStmt where
  toJson
    | .assign lhs rhs => Json.mkObj
        [("stmt", "assign"), ("lhs", toJson lhs), ("rhs", toJson rhs)]
    | .assume c => Json.mkObj [("stmt", "assume"), ("cond", toJson c)]
    | .assert c loc => Json.mkObj
        [("stmt", "assert"), ("cond", toJson c), ("loc", toJson loc)]
    | .havoc lhs => Json.mkObj [("stmt", "havoc"), ("lhs", toJson lhs)]
    | .boolAssignCst k rhs lhs => Json.mkObj
        [("stmt", "bool_assign_cst"), ("cst_kind", toJson k), ("rhs", rhs),
         ("lhs", toJson lhs)]
    | .boolAssignVar rhs n lhs => Json.mkObj
        [("stmt", "bool_assign_var"), ("rhs", toJson rhs), ("negated", toJson n),
         ("lhs", toJson lhs)]
    | .boolBinop op l r lhs => Json.mkObj
        [("stmt", "bool_binop"), ("op", toJson op), ("left", toJson l),
         ("right", toJson r), ("lhs", toJson lhs)]
    | .boolAssume c n => Json.mkObj
        [("stmt", "bool_assume"), ("cond", toJson c), ("negated", toJson n)]
    | .boolAssert c loc => Json.mkObj
        [("stmt", "bool_assert"), ("cond", toJson c), ("loc", toJson loc)]
    | .boolSelect c l r lhs => Json.mkObj
        [("stmt", "bool_select"), ("cond", toJson c), ("left", toJson l),
         ("right", toJson r), ("lhs", toJson lhs)]

instance : FromJson WInv where
  fromJson? j := do
    match ← j.getObjValAs? String "kind" with
    | "true"  => return .top
    | "false" => return .bot
    | "disj"  => return .disj (← j.getObjValAs? (Array (Array WCon)) "disjuncts")
    | other   => throw s!"unknown invariant kind '{other}' (expected true, false or disj)"

instance : ToJson WInv where
  toJson
    | .top  => Json.mkObj [("kind", "true")]
    | .bot  => Json.mkObj [("kind", "false")]
    | .disj ds => Json.mkObj [("kind", "disj"), ("disjuncts", toJson ds)]

-- Derived, but only here: each of these contains the one above it, so the
-- instances have to be introduced outermost-last.
deriving instance FromJson, ToJson for WBlock
deriving instance FromJson, ToJson for WCfg
deriving instance FromJson, ToJson for WDoc

/-! ## Conversion to the proof library's types

Everything below can fail, and says why when it does. The failures are not
defensive padding: the unmodelled statement kinds occur throughout `samples/` —
`test-6` reaches its booleans through a `cast` and is refused for that reason
alone — so these paths are exercised. -/

/-- Parse one of the export's decimal strings. -/
def parseInt (s : String) : Except String Int :=
  match s.toInt? with
  | some n => .ok n
  | none   => .error s!"'{s}' is not a decimal integer"

/-- Reject anything that is not an integer type.

    The types that reach this are `bool`, `int_array` and the reference/region
    family. Booleans are the case that matters, and the reason it is still an
    error rather than a widening: an integer *expression* or *constraint* over a
    boolean variable would mean Crab had put a boolean into arithmetic, which the
    state's two-store representation says is not what CrabIR does. Boolean facts
    reach the assertion language through `WCon.toAtom` below, which is the only
    path that accepts a bool-typed constraint, and it accepts only the shapes
    Crab actually writes.

    The bitwidth is deliberately ignored rather than rejected. Measured against
    the analyser, Crab's integers behave as mathematical integers — `x:i8 := 127;
    x := x+1` yields 128, and a truncating cast does not truncate — so the
    semantics is over unbounded `Int` and a width would be recorded but never
    consulted. -/
def WTy.expectInt (t : WTy) (ctx : String) : Except String Unit :=
  if t.kind == "int" then .ok () else
    .error s!"{ctx} has type '{t.kind}', which is outside the fragment this \
              library models. An integer type is required here: boolean \
              variables live in their own store, and only an invariant's \
              conjuncts may be bool-typed."

/-- Reject anything that is not a boolean type. Used for the operands and
    targets of the boolean statements, all of which the export types `bool`. -/
def WTy.expectBool (t : WTy) (ctx : String) : Except String Unit :=
  if t.kind == "bool" then .ok () else
    .error s!"{ctx} has type '{t.kind}', but a boolean statement's operands must \
              be boolean"

def opOfString : String → Except String Crabber.CmpOp
  | "<=" => .ok .le
  | "<"  => .ok .lt
  | "="  => .ok .eq
  | "!=" => .ok .ne
  | s    => .error s!"unknown comparison operator '{s}'"

def boolOpOfString : String → Except String Crabber.BoolOp
  | "and" => .ok .and
  | "or"  => .ok .or
  | "xor" => .ok .xor
  | s     => .error s!"unknown boolean operator '{s}' (expected and, or or xor)"

/-- `[["1","y"], ["-2","x"]]` becomes `[(1, "y"), (-2, "x")]`. -/
def termsToList (ts : Array (Array String)) : Except String (List (Int × Crabber.Var)) :=
  ts.toList.mapM fun t =>
    match t.toList with
    | [coef, var] => do return (← parseInt coef, var)
    | _ => .error s!"a term must be a [coefficient, variable] pair, got {t.size} elements"

/-- Check the type of an expression or constraint, which may be absent.

    Absence is not "type unknown": Crab writes `null` exactly when there is no
    variable to take a type from, i.e. for a bare constant such as the right-hand
    side of `x := 0`. So the untyped case is accepted, but only after confirming
    that it really does mention no variables — an untyped expression *with* terms
    would mean the export had lost information, and guessing `int` there is
    precisely the silent assumption worth refusing to make. -/
def expectIntType (t : Option WTy) (terms : Array (Array String))
    (ctx : String) : Except String Unit :=
  match t with
  | some ty => ty.expectInt ctx
  | none =>
    if terms.isEmpty then .ok () else
      .error s!"{ctx} carries no type, which the export uses to mean 'a bare \
                constant', yet it mentions {terms.size} variable(s)"

def WExp.toLinExp (e : WExp) : Except String Crabber.LinExp := do
  expectIntType e.type e.terms "a right-hand side"
  return { terms := ← termsToList e.terms, const := ← parseInt e.const }

/-- The two nullary constraints have exact counterparts in the assertion
    language, so neither needs a special case downstream.

    `LinCon.lhs` of an empty term list is `0`, so `0 ≤ 0` is satisfied by every
    state and `0 ≤ -1` by none — which is what `true` and `false` mean. Encoding
    them this way rather than extending `LinCon` keeps the proof library's
    syntax unchanged and its meaning function untouched. -/
def WCon.toLinCon : WCon → Except String Crabber.LinCon
  | .tt => .ok { op := .le, terms := [], const := 0 }
  | .ff => .ok { op := .le, terms := [], const := -1 }
  | .cmp op type terms const => do
      expectIntType type terms "a constraint"
      return { op := ← opOfString op, terms := ← termsToList terms,
               const := ← parseInt const }

/-- A bool-typed constraint, read as a claim about the boolean store.

    **Only `1·b = 0` and `1·b = 1` are accepted.** That is not a simplification:
    measured across `int`, `int-terms`, `int-set`, `zones`, `oct-snf` and `pk`,
    it is the only bool-tagged shape Crab emits, because its booleans go through
    a flat per-variable lattice with no relational information to export.

    Anything else — a comparison other than `=`, a coefficient other than 1, more
    than one term, a constant other than 0 or 1 — is refused, naming what was
    seen. The alternative would be to read such a constraint as arithmetic over a
    0/1 encoding, which is precisely the representation the state does not use;
    it would be quietly meaningless. If a future domain does export a relational
    boolean fact, this error is where it will surface, and the assertion language
    will need an atom for it rather than a silent misreading. -/
def WCon.toBoolAtom (op : String) (terms : Array (Array String))
    (const : String) : Except String Crabber.Atom := do
  let ts ← termsToList terms
  match op, ts, const with
  | "=", [(1, b)], "0" => .ok (.bool b false)
  | "=", [(1, b)], "1" => .ok (.bool b true)
  | _, _, _ =>
    .error s!"a bool-typed constraint here is '{op}' over {terms.size} term(s) \
              against '{const}', which is outside the fragment this library \
              models. Only '1·b = 0' and '1·b = 1' are understood, and measured \
              against every domain crabber offers that is the only shape Crab \
              exports for a boolean. Reading anything else would mean treating \
              a boolean as a 0/1 integer, which is not how the state \
              represents one."

/-- One conjunct of an invariant, dispatched on the type the export tagged it
    with. This is the only place a bool-typed constraint is accepted. -/
def WCon.toAtom : WCon → Except String Crabber.Atom
  | .cmp op (some ty) terms const =>
    if ty.kind == "bool" then WCon.toBoolAtom op terms const
    else do return .lin (← WCon.toLinCon (.cmp op (some ty) terms const))
  | c => do return .lin (← c.toLinCon)

/-- Drops the source location: the asserts carry only their condition, since the
    proof obligation does not depend on where the assertion was written. -/
def WStmt.toStmt : WStmt → Except String Crabber.Stmt
  | .assign lhs rhs => do
      lhs.type.expectInt s!"the assignment target '{lhs.name}'"
      return .assign lhs.name (← rhs.toLinExp)
  | .assume c   => return .assume (← c.toLinCon)
  | .assert c _ => return .assert (← c.toLinCon)
  | .havoc lhs  => do
      lhs.type.expectInt s!"the havoc target '{lhs.name}'"
      return .havoc lhs.name
  -- `rhs` was held as raw JSON because its schema depends on `cst_kind`; this is
  -- where that is resolved. A reference constraint is refused by name — the
  -- reference and region statements are unmodelled as a group, and accepting
  -- their constraints alone would be meaningless.
  | .boolAssignCst kind rhs lhs => do
      lhs.type.expectBool s!"the boolean assignment target '{lhs.name}'"
      if kind != "linear" then
        throw s!"a bool_assign_cst whose right-hand side is a '{kind}' \
                 constraint. References are outside the fragment this library \
                 models; only a linear constraint is understood here."
      let c : WCon ← fromJson? rhs
      return .boolAssignCst lhs.name (← c.toLinCon)
  | .boolAssignVar rhs neg lhs => do
      lhs.type.expectBool s!"the boolean assignment target '{lhs.name}'"
      rhs.type.expectBool s!"the boolean assignment source '{rhs.name}'"
      return .boolAssignVar lhs.name rhs.name neg
  | .boolBinop op l r lhs => do
      lhs.type.expectBool s!"the boolean operation target '{lhs.name}'"
      l.type.expectBool s!"the left operand '{l.name}'"
      r.type.expectBool s!"the right operand '{r.name}'"
      return .boolBinop lhs.name (← boolOpOfString op) l.name r.name
  | .boolAssume c neg => do
      c.type.expectBool s!"the assumed boolean '{c.name}'"
      return .boolAssume c.name neg
  | .boolAssert c _ => do
      c.type.expectBool s!"the asserted boolean '{c.name}'"
      return .boolAssert c.name
  | .boolSelect c l r lhs => do
      lhs.type.expectBool s!"the boolean select target '{lhs.name}'"
      c.type.expectBool s!"the select condition '{c.name}'"
      l.type.expectBool s!"the left operand '{l.name}'"
      r.type.expectBool s!"the right operand '{r.name}'"
      return .boolSelect lhs.name c.name l.name r.name

def WInv.toAssn : WInv → Except String Crabber.Assn
  | .top     => .ok Crabber.Assn.top
  | .bot     => .ok Crabber.Assn.bot
  | .disj ds => ds.toList.mapM fun d => d.toList.mapM WCon.toAtom

/-! ## Building the CFG

`Cfg.body` and `Cfg.succ` are *total* functions: every label, including strings
naming no block, must have an answer. The export gives an association list, so
the total function is a lookup defaulting to the empty list — which is exactly
the convention the library's "unknown label" lemma expects. The invariant map
defaults to bottom for the same reason: a label that names no block is not
reachable, and bottom is the claim that says so. -/

/-- One analysed program, in the form the proof library wants.

    `labels` is kept because the bundling step needs to case-split over exactly
    the blocks that exist, and because it is the list a generated file prints. -/
structure Program where
  name   : String
  entry  : Crabber.Label
  labels : List Crabber.Label
  cfg    : Crabber.Cfg
  inv    : Crabber.Label → Crabber.Assn

/-- A block after conversion, before the maps are assembled. -/
private structure BlockData where
  label : Crabber.Label
  body  : List Crabber.Stmt
  succs : List Crabber.Label
  inv   : Crabber.Assn

private def WBlock.toData (b : WBlock) : Except String BlockData := do
  return { label := b.label
           body  := ← b.stmts.toList.mapM WStmt.toStmt
           succs := b.succs.toList
           inv   := ← b.invariant.toAssn }

def WCfg.toProgram (c : WCfg) : Except String Program := do
  let bs ← c.blocks.toList.mapM WBlock.toData
  let bodyTbl := bs.map fun b => (b.label, b.body)
  let succTbl := bs.map fun b => (b.label, b.succs)
  let invTbl  := bs.map fun b => (b.label, b.inv)
  -- Duplicate labels would make the lookups below silently prefer the first,
  -- so the two documents could agree while describing different graphs.
  let labels := bs.map (·.label)
  if labels.eraseDups.length != labels.length then
    throw s!"cfg '{c.name}' lists a block label twice"
  return { name   := c.name
           entry  := c.entry
           labels := labels
           cfg    := { entry := c.entry
                       body  := fun l => (bodyTbl.lookup l).getD []
                       succ  := fun l => (succTbl.lookup l).getD [] }
           inv    := fun l => (invTbl.lookup l).getD Crabber.Assn.bot }

/-! ## Entry points -/

/-- Read a document, checking it is the combined invariants export rather than
    the CFG-only one — the latter has no `invariant` on its blocks, and silently
    accepting it would produce a program annotated entirely with bottom. -/
def docOfJson (j : Json) : Except String WDoc := do
  let d : WDoc ← fromJson? j
  if d.schema != 1 then
    throw s!"unsupported schema version {d.schema} (this reader knows version 1)"
  if d.kind != "invariants" then
    throw s!"document kind is '{d.kind}'; expected 'invariants', the export that \
             carries the CFG and the inferred invariants together"
  return d

/-- The name of an unparsed CFG, read straight out of its JSON.

    Enough to find the one that was asked for without committing to parsing any
    of the others. -/
def cfgNameOf (j : Json) : Option String :=
  (j.getObjValAs? String "name").toOption

/-- Every CFG the document mentions, named but not parsed. -/
def WDoc.cfgNames (d : WDoc) : List String :=
  d.cfgs.toList.filterMap cfgNameOf

/-- The JSON of one named CFG, still unparsed. -/
def WDoc.rawCfg (d : WDoc) (cfgName : String) : Except String Json :=
  match d.cfgs.find? (fun j => cfgNameOf j == some cfgName) with
  | some j => .ok j
  | none   =>
    let available := String.intercalate ", " d.cfgNames
    .error s!"no cfg named '{cfgName}' in this document (it has: {available})"

end CrabberJson
