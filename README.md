# crabber  #

[![Try the CrabIR Playground](https://img.shields.io/badge/Try%20it-CrabIR%20Playground-orange?logo=webassembly&logoColor=white)](https://caballa.github.io/crabber/)

The goal of this project is to allow Crab users to write small tests
to interact with [Crab](https://github.com/seahorn/crab) analyses and
abstract domains eliminating the need for writing C++ boilerplate code
to use Crab APIs.

# Try it online #

Run CrabIR programs in your browser — no install — at the
**[CrabIR Playground](https://caballa.github.io/crabber/)**. The full analyzer is
compiled to WebAssembly and runs entirely client-side (nothing is sent to a
server). See [`build-wasm/`](build-wasm/) for how it is built.

# Requirements #

- [Crab requirements](https://github.com/seahorn/crab#requirements)

# Compilation and Installation # 

     1. mkdir build && cd build
     2. cmake -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR -DCRAB_ROOT=$CRAB_SOURCE_ROOT ../
     3. cmake --build . --target install 

where `$CRAB_SOURCE_ROOT` is the path where source code of Crab is
located.

# Writing CrabIR programs #

A CrabIR program is a text file describing one or more control-flow graphs
(cfgs). This section is a reference for the syntax; the shortest way to learn
it, though, is to skim the ready-to-run programs under [`samples/`](samples/).

## Program structure ##

```
# Lines starting with '#' are comments. A '#' anywhere on a line starts a
# comment until the end of the line.
#
# Newlines delimit instructions, blocks and cfgs (there are no semicolons).

cfg("foo")            # a cfg is introduced by cfg("<name>"). Quotes required.
  start:              # a block is a label followed by ':'. Entry MUST be "start".
   x:i32 := 0         # instructions belong to the block above them
   goto loop
  loop:               # another block
   x:i32 := x + 1
   if (x <= 9):i32 goto loop else goto out
  out:
   EXPECT_EQ(true, assert(x == 10):i32)
```

Rules of the game:

- A file may contain several cfgs; each begins with a new `cfg(...)` header.
- Every cfg needs an entry block named **`start`**.
- Blocks do not fall through: a block continues only via an explicit `goto` or
  `if ... goto ... else goto ...`. A block with no successor is a sink.
- Blocks may be defined in any order; a `goto`/`if` may reference a block that
  appears later in the file.

## Types ##

The language is **strongly typed and has no type inference**, so every
instruction must carry enough type annotations for the parser to know the type
of each variable. In practice this means the left-hand side of assignments is
typed, and the constraints inside `if`, `assume`, and `assert` are typed.

| Type          | Meaning                                            |
|---------------|----------------------------------------------------|
| `iN`          | integer of `N` bits, e.g. `i8`, `i32`, `i64`       |
| `i1`          | Boolean (a 1-bit integer is treated as a Boolean)  |
| array         | array of integers; indices must be `i64`           |

A type annotation is written `:iN` right after a variable, e.g. `x:i32`.
Variable names match `[.@a-zA-Z_][.a-zA-Z0-9_]*` (`true` and `false` are
reserved). Integer literals are decimal (`-3`, `42`) or hexadecimal (`0x1F`).

## Statement reference ##

Below, `x`, `y`, `z` are integer variables, `b` are Booleans, `arr` an array,
and `L1`/`L2` block labels.

### Integer assignments ###

```
x:i32 := 5              # immediate (decimal); the LHS must be typed
x:i32 := 0x1F           # immediate (hexadecimal)
x:i32 := 2*y - 3*z + 1  # linear expression; the RHS need NOT be typed
x:i32 := y * z          # multiplication of two variables (non-linear)
x:i32 := y / z          # division of two variables (non-linear)
```

A *linear expression* is a sum of terms `k*var` and integer constants. Use the
`y * z` / `y / z` forms when both operands are variables.

### Boolean assignments ###

```
b3:i1 := b2             # copy another Boolean (LHS typed with :i1)
b := (x <= 10):i32      # truth value of a constraint (LHS type is inferred as i1)
b := b1 and b2          # Boolean and / or / xor
b := b1 or  b2
b := b1 xor b2
b := not(b1)            # Boolean negation
```

Note the asymmetry: a plain Boolean **copy** types the left-hand side (`b3:i1`),
whereas assignments from a constraint, `and`/`or`/`xor`, and `not` leave the
left-hand side untyped because it is inferred to be `i1`.

### Integer casts ###

```
trunc(x:i32, y:i16)     # truncate  (destination narrower than source)
sext(x:i32,  y:i64)     # sign-extend  (destination wider than source)
zext(x:i32,  y:i64)     # zero-extend  (destination wider than source)
```

The first argument is the source, the second the destination. `trunc` may
target `i1` (a handy way to obtain a Boolean).

### Non-deterministic value ###

```
havoc(x:i32)            # assign an arbitrary (unknown) value to x
```

### Arrays ###

```
array_store(arr, idx:i64, val:i32)   # arr[idx] := val
x:i32 := array_load(arr, idx:i64)    # x := arr[idx]
```

Array variables are named without a type annotation; the element size is taken
from the value/result type and the index must be `i64`.

### assume ###

`assume` restricts the analysis to states satisfying a condition.

```
assume(x <= y):i32      # integer linear constraint (typed)
assume(b)               # Boolean variable
assume(true)            # trivially true / false
assume(false)
```

### assert ###

`assert` states a property to be checked by the analyzer; the tool reports
whether each assertion holds.

```
assert(x == 10):i32     # integer linear constraint (typed)
assert(b)               # Boolean variable
assert(true)            # trivial
assert(false)
```

### EXPECT_EQ (for tests) ###

`EXPECT_EQ(expected, assert(...))` wraps an assertion with the expected
outcome, driving the `### TESTS RESULTS ###` summary. `expected` is `true` if
the assertion should be proven, or `false` if it is expected to fail.

```
EXPECT_EQ(true,  assert(x == 10):i32)   # expected to hold
EXPECT_EQ(false, assert(x == 11):i32)   # expected to fail
EXPECT_EQ(true,  assert(b))             # also works with Boolean/trivial asserts
```

### Control flow ###

```
goto L1                        # unconditional jump
if (x <= 9):i32 goto L1 else goto L2   # conditional; the constraint is typed
```

On the `then` edge the constraint is assumed to hold; on the `else` edge its
negation is assumed.

### Value partitioning (advanced) ###

```
value_partition_start(x:i32)   # begin partitioning the analysis on values of x
...
value_partition_end(x:i32)     # end the partition
```

### exit ###

```
exit                           # marks the end of a path (see Function calls)
```

# Function calls #

A cfg can declare typed **input** and **output** parameters and be invoked
from another cfg through a call site.

## Declaring parameters ##

Parameters are written after the cfg name as a comma-separated list of
`name:type:direction`, where `direction` is `in` or `out`. A cfg without
parameters keeps the old `cfg("name")` form.

```
# inc(a) returns a + 1
cfg("inc", a:i32:in, b:i32:out)
  start:
   b:i32 := a + 1
   exit
```

The set of inputs and outputs must be disjoint: the same variable cannot be
declared both as an input and as an output.

## Call sites ##

A call is written with the (optional) outputs on the left-hand side and the
inputs as arguments. As everywhere else in the language, both the outputs and
the arguments must be typed.

```
call foo(a:i32)                         # no outputs
b:i32 := call foo(a:i32)                # single output
(b:i32) := call foo(a:i32)             # single output, parenthesized
(y:i32, w:i64) := call g(x:i32, z:i64) # multiple outputs
```

Putting it together:

```
cfg("inc", a:i32:in, b:i32:out)
  start:
   b:i32 := a + 1
   exit

cfg("main")
  start:
   x:i32 := 5
   y:i32 := call inc(x:i32)
   EXPECT_EQ(true, assert(y == 6):i32)
```

See `samples/test-call-*.crabir` for more examples, including negative tests
(`samples/test-call-fail-*.crabir`) that are expected to be rejected by the
parser.

# Usage #

## Command Line Interface ## 

``` bash
$INSTALL_DIR/bin/crabber samples/test-1.crabir
```

Run 

``` bash
$INSTALL_DIR/bin/crabber --help
```

to see all options. For instance, option `--print-invariants-to-dot`
prints both the CFG and the inferred invariants to dot format. 

## C++ API ##

``` c++
// include/crab_tests/crabber.hpp

TestResult run_program(std::istream &is, 
                       const CrabIrBuilderOpts &irOpts,
                       const CrabIrAnalyzerOpts &anaOpts);

```

