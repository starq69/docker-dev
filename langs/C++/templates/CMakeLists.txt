cmake_minimum_required(VERSION 3.20)
project(cpp_demo VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(cpp_demo
    src/main.cpp
)

target_compile_options(cpp_demo PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -O0
    -g3
)
