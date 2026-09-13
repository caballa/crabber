# Range form: min is 3.3, but declare policies are current up to 4.0 so this
# still configures under CMake 4.x (which rejects a bare min < 3.5).
cmake_minimum_required(VERSION 3.3...4.0)

project(crabber)

if (CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR ) 
  message (FATAL_ERROR 
    "In-source builds are not allowed. Please clean your source tree and try again.")  
endif()

# Determine if this is top-level or embedded project
if (PROJECT_NAME STREQUAL CMAKE_PROJECT_NAME)
  set(TopLevel TRUE)
else()
  set(TopLevel FALSE)
endif()

# Default is release with debug info
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING
    "Choose the type of build, options are: Debug Release RelWithDebInfo Coverage." FORCE)
endif()

set(CMAKE_CXX_STANDARD 14 CACHE STRING "C++ standard to conform to")
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_CXX_EXTENSIONS NO)


set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")

if (TopLevel)
  if (IS_DIRECTORY "${CRAB_ROOT}" AND EXISTS ${CRAB_ROOT}/CMakeLists.txt)
    ## Needed by Crab headers included from crabber sources. Crab's own
    ## include_directories(Boost) is subdirectory-scoped and does not
    ## propagate to the crabber target, so we look Boost up here too.
    find_package (Boost 1.65.0)
    if (Boost_FOUND)
      include_directories (${Boost_INCLUDE_DIRS})
    endif ()
    ## Crab source code already exists out-of-the tree
    set(CRAB_BINARY_DIR crab) ## needed if CRAB_ROOT out of tree.
    add_subdirectory(${CRAB_ROOT} ${CRAB_BINARY_DIR})
    include_directories(${CRAB_INCLUDE_DIRS})
    message(STATUS "Crab found in ${CRAB_ROOT}. CRAB_INCLUDE_DIRS=${CRAB_INCLUDE_DIRS} CRAB_LIBS=${CRAB_LIBS}")
  else ()
    message(FATAL_ERROR "crab not found in \"${CRAB_ROOT}\". Set CRAB_ROOT")
  endif()  
endif()  


include_directories(${crabber_SOURCE_DIR}/external)
include_directories(${crabber_SOURCE_DIR}/include)
add_executable(crabber
  src/crabber.cpp
  src/parser.cpp
  src/crabir_builder.cpp
  src/analyzer.cpp
  src/json_export.cpp
  src/lean_verify.cpp
  src/domains/boxes_domain.cpp
  src/domains/dis_interval_domain.cpp    
  src/domains/interval_domain.cpp
  src/domains/octagons_domain.cpp
  src/domains/pk_domain.cpp
  src/domains/pk_pplite_domain.cpp
  src/domains/symbolic_terms.cpp
  src/domains/tvpi_dbm_domain.cpp
  src/domains/zones_domain.cpp
)
target_link_libraries(crabber PRIVATE ${CRAB_LIBS})

# --verify-with-lean: after the analysis, ask the Lean development in lean/ to
# prove the exported invariants sound.
#
# Configure-time rather than a runtime flag, for two reasons. It means the
# option exists only in a build that can actually honour it -- in particular the
# wasm build, which has no toolchain to call, does not carry code for a
# capability a browser cannot have. And it removes any need to discover lake or
# the project directory at run time.
set(LAKE_EXECUTABLE "" CACHE FILEPATH
    "Path to lake. Enables crabber's --verify-with-lean option.")

if (LAKE_EXECUTABLE)
  if (NOT EXISTS "${LAKE_EXECUTABLE}")
    message(FATAL_ERROR "LAKE_EXECUTABLE does not exist: ${LAKE_EXECUTABLE}")
  endif()

  # Build the Lean library as part of the normal build. Knowing where lake lives
  # is not the same as the library having been built, and a crabber that can
  # find lake but meets missing .olean files reports a confusing failure that
  # looks nothing like a proof not going through.
  add_custom_target(lean_library ALL
    COMMAND "${LAKE_EXECUTABLE}" build
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/lean"
    COMMENT "Building the Lean verification library")
  add_dependencies(crabber lean_library)

  target_compile_definitions(crabber PRIVATE
    CRABBER_WITH_LEAN=1
    CRABBER_LAKE="${LAKE_EXECUTABLE}"
    CRABBER_LEAN_PROJECT="${CMAKE_CURRENT_SOURCE_DIR}/lean")

  message(STATUS "Lean verification enabled: ${LAKE_EXECUTABLE}")
else ()
  message(STATUS "Lean verification disabled "
                 "(set -DLAKE_EXECUTABLE=$(which lake) to enable)")
endif()

install(TARGETS crabber DESTINATION bin)
install(DIRECTORY include/crabber DESTINATION include)

if (TopLevel)
  # Run the sample CrabIR programs as tests. crabber exits non-zero when there
  # are unexpected results, so the process exit code is the pass/fail oracle.
  # These mirror the invocations in docker/crabber.Dockerfile.
  enable_testing()

  function(add_crabber_test test_name)
    add_test(
      NAME ${test_name}
      COMMAND crabber ${ARGN}
      WORKING_DIRECTORY ${crabber_SOURCE_DIR}/samples)
  endfunction()

  add_crabber_test(test-1  test-1.crabir  -d int)
  add_crabber_test(test-3  test-3.crabir  -d int)
  add_crabber_test(test-4  test-4.crabir  -d oct-snf)
  # test-5 checks a specific invariant rather than an assertion outcome: with
  # widening thresholds, n must be in [0, 60] at block b1. Adding an assert would
  # make the property hold trivially, so match the printed invariant instead.
  add_test(
    NAME test-5
    COMMAND sh -c "$<TARGET_FILE:crabber> test-5.crabir -d int --widening-thresholds 10 --print-invariants | grep -Fx 'b1: ({}, {n -> [0, 60]})'"
    WORKING_DIRECTORY ${crabber_SOURCE_DIR}/samples)
  add_crabber_test(test-6  test-6.crabir  -d int)
  # The boxes domain is only available when Crab is built with LDD support.
  if (CRAB_USE_LDD)
    add_crabber_test(test-7-boxes        test-7.crabir -d boxes          --widening-delay 10)
  endif()
  add_crabber_test(test-7-int-set        test-7.crabir -d int-set        --widening-delay 10)
  add_crabber_test(test-7-int-val-part   test-7.crabir -d int-val-part   --widening-delay 10)
  add_crabber_test(test-7-zones-val-part test-7.crabir -d zones-val-part --widening-delay 10)
  add_crabber_test(test-8  test-8.crabir  -d zones)
  # The only sample with an array access wider than one address, so the only
  # one that reaches the overlap machinery in the array domains.
  add_crabber_test(test-13 test-13.crabir -d zones)
  # Arrays of booleans, whose element sort comes from the stored value.
  add_crabber_test(test-14 test-14.crabir -d zones)
  add_crabber_test(test-9  test-9.crabir  -d tvpi-dbm --coefficients "4,8")
  add_crabber_test(test-10 test-10.crabir -d int-terms)
  # Neither zones nor oct-snf can prove these: the invariants need the non-unit
  # coefficients in the template. test-12 additionally needs two coefficients to
  # survive a join, which the superseded fixed_tvpi_domain could not do.
  add_crabber_test(test-tvpi-dbm-1 tvpi.crabir    -d tvpi-dbm --coefficients "2")
  add_crabber_test(test-tvpi-dbm-2 test-12.crabir -d tvpi-dbm --coefficients "2,3")

  # Function-call tests (cfg parameters + call sites).
  add_crabber_test(test-call-1 test-call-1.crabir -d zones)
  add_crabber_test(test-call-2 test-call-2.crabir -d zones)
  add_crabber_test(test-call-3 test-call-3.crabir -d zones)
  add_crabber_test(test-call-4 test-call-4.crabir -d zones)

  # Negative tests: these programs must fail to compile. Matching the error
  # message rather than using WILL_FAIL, because a non-zero exit alone does not
  # say the program was rejected for the intended reason -- and a negative test
  # that silently starts passing, or starts failing for an unrelated reason, is
  # worse than no test. Note PASS_REGULAR_EXPRESSION replaces the exit code as
  # the oracle, so it cannot be combined with WILL_FAIL.
  add_crabber_test(test-call-fail-1 test-call-fail-1.crabir -d int)
  set_tests_properties(test-call-fail-1 PROPERTIES
    PASS_REGULAR_EXPRESSION "inputs and outputs must be disjoint")
  add_crabber_test(test-call-fail-2 test-call-fail-2.crabir -d int)
  set_tests_properties(test-call-fail-2 PROPERTIES
    PASS_REGULAR_EXPRESSION "cannot parse.*call foo")

  # --verify-with-lean, pinned by verdict.
  #
  # The tests above cannot see this feature at all: their oracle is crabber's
  # exit code, which reports whether Crab's own assertion checking matched the
  # EXPECT_EQs and is identical whether Lean proved the invariants or was never
  # asked. test-4 was a registered, passing test throughout a period when its
  # octagon verification did not go through, so these exist to make a change in
  # what Lean can prove visible as a test failure rather than as a line of
  # output nobody reads.
  #
  # Each case is here for a distinct reason; see lean/tools/check-verdicts.sh
  # for what is compared and what deliberately is not.
  if (LAKE_EXECUTABLE)
    function(add_lean_test test_name expected)
      add_test(
        NAME ${test_name}
        COMMAND sh ${crabber_SOURCE_DIR}/lean/tools/check-verdicts.sh
                $<TARGET_FILE:crabber> ${expected} ${ARGN}
        WORKING_DIRECTORY ${crabber_SOURCE_DIR}/samples)
    endfunction()

    # The half of the regression that needs no Apron: with intervals the
    # assertion does not follow from the invariant, so this pins the negative.
    add_lean_test(lean-test-4-int "could not verify octagons" test-4.crabir -d int)

    # The positive half needs an Apron-backed domain, and not by accident.
    #
    # Whether the entry invariant arrives as the explicit top marker
    # {"kind": "true"} or as a disjunct holding the nullary constraint
    # {"op": "true"} -- which reads as [[0 <= 0]] -- is a property of the
    # *domain*. Crab's native domains (int, zones, oct-snf, the partitioning
    # ones) emit the first and take the `Assn.holds_top` branch of the entry
    # obligation. The Apron-backed ones, `oct` and `pk`, emit the second and
    # take the arithmetic branch, which is the branch that was broken.
    #
    # So oct-snf cannot stand in for oct here: it would exercise the wrong
    # branch and pass either way. A build without Apron genuinely cannot run
    # this regression test, which is why these are guarded rather than
    # rewritten to a native domain.
    if (CRAB_USE_APRON)
      add_lean_test(lean-test-4-oct "proved octagons" test-4.crabir -d oct)

      # `pk` was blocked by the same bug and for the same reason -- every pk run
      # failed its entry obligation whatever the invariants said. These two are
      # proved by no other domain here, so they also pin what pk buys.
      add_lean_test(lean-test-tvpi-pk "proved tvpi-example" tvpi.crabir -d pk)
      add_lean_test(lean-test-12-pk   "proved tvpi-dbm"     test-12.crabir -d pk)

      # The narrowing options. These are the commands that localise a failure to
      # the entry obligation or to the blocks, so a break in either would cost
      # exactly what it cost before they existed.
      add_lean_test(lean-test-4-oct-init "proved octagons" test-4.crabir -d oct
                    --lean-only init)
      add_lean_test(lean-test-4-oct-vc   "proved octagons" test-4.crabir -d oct
                    --lean-only vc)
      add_lean_test(lean-test-4-oct-block "proved octagons" test-4.crabir -d oct
                    --lean-block header)
    endif()

    # Both outcomes of the same file: `bar` is provable, `foo` asserts something
    # that is genuinely false and must stay unproved. --lean-cfg picks one of
    # the two, and suppresses the other rather than reporting it as skipped.
    add_lean_test(lean-test-1 "proved bar,could not verify foo" test-1.crabir -d int)
    add_lean_test(lean-test-1-cfg "proved bar" test-1.crabir -d int --lean-cfg bar)

    # The boolean fragment end to end, and its own negative. test-6 also uses
    # booleans but reaches them through a cast, so this is the one that can be
    # checked.
    add_lean_test(lean-test-bool-1 "proved safe,could not verify unsafe"
                  test-bool-1.crabir -d int)

    # Loops and widening thresholds -- the two shapes where an inductive
    # invariant is doing real work.
    add_lean_test(lean-test-3 "proved nested-loops" test-3.crabir -d int)
    add_lean_test(lean-test-5 "proved thresholds"   test-5.crabir -d int
                  --widening-thresholds 10)

    # An unmodelled construct must be reported as out of scope, not as a failure
    # to prove: `z := x * y` is nonlinear, and the reader refuses it by name.
    add_lean_test(lean-test-10 "not attempted terms" test-10.crabir -d int-terms)

    # Only call-graph roots are checked, because a callee's invariants are
    # conditional on its callers. Pinning both halves keeps that visible.
    add_lean_test(lean-test-call-1 "not attempted main,not checked inc"
                  test-call-1.crabir -d zones)

    # Deliberately absent: test-9 and test-11 exhaust the elaboration budget, so
    # they would each spend the full --lean-heartbeats allowance to assert that
    # nothing was proved.
  endif()
endif()
