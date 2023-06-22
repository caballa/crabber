# crab-tests #

The goal of this project is to allow Crab users to write small tests
to interact with [Crab](https://github.com/seahorn/crab) analyses and
abstract domains eliminating the need for writing C++ boilerplate code
to use Crab APIs.

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

# Usage #

## Command Line Interface ## 

``` bash
$INSTALL_DIR/bin/run_test samples/test-1.crabir
```

Run 

``` bash
$INSTALL_DIR/bin/run_test --help
```

to see all options. For instance, option `--print-invariants-to-dot`
prints both the CFG and the inferred invariants to dot format. 

## C++ API ##

``` c++
// include/crab_tests/run_test.hpp

TestResult run_test(std::istream &is, 
                    const CrabIrBuilderOpts &irOpts,
                    const CrabIrAnalyzerOpts &anaOpts);

```

