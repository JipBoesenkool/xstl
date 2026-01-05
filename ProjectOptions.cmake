include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(xstl_supports_sanitizers)
  # Emscripten doesn't support sanitizers
  if(EMSCRIPTEN)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  elseif((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(xstl_setup_options)
  option(xstl_ENABLE_HARDENING "Enable hardening" ON)
  option(xstl_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    xstl_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    xstl_ENABLE_HARDENING
    OFF)

  xstl_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR xstl_PACKAGING_MAINTAINER_MODE)
    option(xstl_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(xstl_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(xstl_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(xstl_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(xstl_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(xstl_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(xstl_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(xstl_ENABLE_PCH "Enable precompiled headers" OFF)
    option(xstl_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(xstl_ENABLE_IPO "Enable IPO/LTO" ON)
    option(xstl_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(xstl_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(xstl_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(xstl_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(xstl_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(xstl_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(xstl_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(xstl_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(xstl_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(xstl_ENABLE_PCH "Enable precompiled headers" OFF)
    option(xstl_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      xstl_ENABLE_IPO
      xstl_WARNINGS_AS_ERRORS
      xstl_ENABLE_USER_LINKER
      xstl_ENABLE_SANITIZER_ADDRESS
      xstl_ENABLE_SANITIZER_LEAK
      xstl_ENABLE_SANITIZER_UNDEFINED
      xstl_ENABLE_SANITIZER_THREAD
      xstl_ENABLE_SANITIZER_MEMORY
      xstl_ENABLE_UNITY_BUILD
      xstl_ENABLE_CLANG_TIDY
      xstl_ENABLE_CPPCHECK
      xstl_ENABLE_COVERAGE
      xstl_ENABLE_PCH
      xstl_ENABLE_CACHE)
  endif()

  xstl_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (xstl_ENABLE_SANITIZER_ADDRESS OR xstl_ENABLE_SANITIZER_THREAD OR xstl_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(xstl_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(xstl_global_options)
  if(xstl_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    xstl_enable_ipo()
  endif()

  xstl_supports_sanitizers()

  if(xstl_ENABLE_HARDENING AND xstl_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR xstl_ENABLE_SANITIZER_UNDEFINED
       OR xstl_ENABLE_SANITIZER_ADDRESS
       OR xstl_ENABLE_SANITIZER_THREAD
       OR xstl_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${xstl_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${xstl_ENABLE_SANITIZER_UNDEFINED}")
    xstl_enable_hardening(xstl_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(xstl_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(xstl_warnings INTERFACE)
  add_library(xstl_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  xstl_set_project_warnings(
    xstl_warnings
    ${xstl_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  # Linker and sanitizers not supported in Emscripten
  if(NOT EMSCRIPTEN)
    if(xstl_ENABLE_USER_LINKER)
      include(cmake/Linker.cmake)
      xstl_configure_linker(xstl_options)
    endif()

    include(cmake/Sanitizers.cmake)
    xstl_enable_sanitizers(
      xstl_options
      ${xstl_ENABLE_SANITIZER_ADDRESS}
      ${xstl_ENABLE_SANITIZER_LEAK}
      ${xstl_ENABLE_SANITIZER_UNDEFINED}
      ${xstl_ENABLE_SANITIZER_THREAD}
      ${xstl_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(xstl_options PROPERTIES UNITY_BUILD ${xstl_ENABLE_UNITY_BUILD})

  if(xstl_ENABLE_PCH)
    target_precompile_headers(
      xstl_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(xstl_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    xstl_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(xstl_ENABLE_CLANG_TIDY)
    xstl_enable_clang_tidy(xstl_options ${xstl_WARNINGS_AS_ERRORS})
  endif()

  if(xstl_ENABLE_CPPCHECK)
    xstl_enable_cppcheck(${xstl_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(xstl_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    xstl_enable_coverage(xstl_options)
  endif()

  if(xstl_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(xstl_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(xstl_ENABLE_HARDENING AND NOT xstl_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR xstl_ENABLE_SANITIZER_UNDEFINED
       OR xstl_ENABLE_SANITIZER_ADDRESS
       OR xstl_ENABLE_SANITIZER_THREAD
       OR xstl_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    xstl_enable_hardening(xstl_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
