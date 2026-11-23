cmake_minimum_required(VERSION 3.16)
project(caelestiastyle LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)
find_package(KF6XmlGui REQUIRED)

add_library(caelestiastyle MODULE style.cpp dolphinlayout.cpp)
target_link_libraries(caelestiastyle PRIVATE Qt6::Widgets KF6::XmlGui)
set_target_properties(caelestiastyle PROPERTIES PREFIX "")

install(TARGETS caelestiastyle LIBRARY DESTINATION lib/qt6/plugins/styles)
