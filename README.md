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

# Example #

``` 
# This is a comment.
# Newlines are used to delimit a new instruction, new block or new cfg.
# A cfg must have a name as a string (do not forget double quotes).
# Blocks are denoted as a string name followed by ":".
# The entry block of a cfg must be called "start"
#
# About types
#
# The language is strongly typed so there is NOT type inference. This means
# that all instructions must have enough type information so that the parser
# can know the type of all variables. For instance, left-hand side of 
# assignments must be typed, and constraints that appear in conditionals, assume, 
# and assert must be also typed.
#

cfg("foo")
  start: 
   x:i32 := 0  # x is an integer of 32 bits
   goto loop
  loop: 
   x:i32 := x + 1
   if (x <= 9):i32 goto loop else goto out
  out: 
   EXPECT_EQ(true, assert(x == 10):i32)
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

