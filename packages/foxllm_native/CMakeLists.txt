cmake_minimum_required(VERSION 3.22)
project(foxllm_native LANGUAGES C CXX)

include(FetchContent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(FOXLLM_WITH_LLAMA_CPP "Build FoxLLM with llama.cpp support" OFF)

if(FOXLLM_WITH_LLAMA_CPP)
    # Keep llama.cpp as static implementation details of libfoxllm_native.so.
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
    set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)

    # Android-safe baseline recommended by llama.cpp's NDK documentation.
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
    set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
    set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)

    # b10903 -> 481c65f091f74c5e7089dd0a3a1cc6b50cced31e
    FetchContent_Declare(
        llama_cpp
        GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
        GIT_TAG b10903
        GIT_SHALLOW TRUE
        GIT_PROGRESS TRUE
    )
    FetchContent_MakeAvailable(llama_cpp)
endif()

add_library(foxllm_native SHARED src/foxllm_native.cpp)
target_include_directories(foxllm_native PRIVATE src)
target_compile_features(foxllm_native PRIVATE cxx_std_17)

if(FOXLLM_WITH_LLAMA_CPP)
    target_compile_definitions(foxllm_native PRIVATE FOXLLM_WITH_LLAMA_CPP=1)
    target_link_libraries(foxllm_native PRIVATE llama)
endif()

set_target_properties(
    foxllm_native
    PROPERTIES
        OUTPUT_NAME foxllm_native
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
)

install(
    TARGETS foxllm_native
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
    ARCHIVE DESTINATION lib
)
