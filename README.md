# crab-tests #

The goal of this project is to allow Crab users to write small tests
to interact with [Crab](https://github.com/seahorn/crab) analyses and
abstract domains eliminating the need for writing C++ boilerplace code
to use Crab APIs.

# Requirements #

- [Crab requirements](https://github.com/seahorn/crab#requirements)

# Compilation and Installation # 

     1. mkdir build && cd build
     2. cmake -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR -DCRAB_ROOT=$CRAB_SOURCE_ROOT ../
     3. cmake --build . --target install 

where `$CRAB_SOURCE_ROOT` is the path where source code of Crab is
located.

# Examples #

TODO: add example and syntax


# Usage #

## Command Line Interface ## 

``` bash
$INSTALL_DIR/bin/run_test samples/test-1.crabir
```

## C++ API ##

``` c++
// include/crab_tests/run_test.hpp

TestResult run_test(std::istream &is, 
                    const CrabIrBuilderOpts &irOpts,
                    const CrabIrAnalyzerOpts &anaOpts);

```

