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
  src/domains/boxes_domain.cpp
  src/domains/dis_interval_domain.cpp    
  src/domains/fixed_tvpi_domain.cpp
  src/domains/interval_domain.cpp
  src/domains/octagons_domain.cpp
  src/domains/pk_domain.cpp
  src/domains/pk_pplite_domain.cpp
  src/domains/symbolic_terms.cpp
  src/domains/zones_domain.cpp
)
target_link_libraries(crabber PRIVATE ${CRAB_LIBS})
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
  add_crabber_test(test-9  test-9.crabir  -d non-unit-oct --coefficients "4,8")
  add_crabber_test(test-10 test-10.crabir -d int-terms)

  # Function-call tests (cfg parameters + call sites).
  add_crabber_test(test-call-1 test-call-1.crabir -d zones)
  add_crabber_test(test-call-2 test-call-2.crabir -d zones)
  add_crabber_test(test-call-3 test-call-3.crabir -d zones)
  add_crabber_test(test-call-4 test-call-4.crabir -d zones)
endif()
