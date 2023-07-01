cmake_minimum_required(VERSION 3.3)

project(crab_tests)

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

# Add path for custom modules
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH}  "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 11 CACHE STRING "C++ standard to conform to")
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_CXX_EXTENSIONS NO)


set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")

if (TopLevel)
  if (IS_DIRECTORY "${CRAB_ROOT}" AND EXISTS ${CRAB_ROOT}/CMakeLists.txt)
    ## Needed by Crab
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


include_directories(${crab_tests_SOURCE_DIR}/external)
include_directories(${crab_tests_SOURCE_DIR}/include)
add_executable(run_test
  src/run_test.cpp
  src/parser.cpp
  src/crabir_builder.cpp
  src/analyzer.cpp
  src/domains/boxes_domain.cpp
  src/domains/fixed_tvpi_domain.cpp
  src/domains/interval_domain.cpp
  src/domains/octagons_domain.cpp
  src/domains/pk_domain.cpp
  src/domains/pk_pplite_domain.cpp
  src/domains/symbolic_terms.cpp  
  src/domains/zones_domain.cpp
)
target_link_libraries(run_test PRIVATE ${CRAB_LIBS})
install(TARGETS run_test DESTINATION bin)
install(DIRECTORY include/crab_tests DESTINATION include)
