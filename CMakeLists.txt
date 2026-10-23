cmake_minimum_required(VERSION 3.20)
project(LocaLink LANGUAGES CXX)

set(APP_BUNDLE_IDENTIFIER "com.nexis.localink" CACHE STRING "macOS bundle identifier")
# Version affichee par les installateurs et le paquet macOS (fournie par le CI).
set(LOCALINK_VERSION "1.0.0" CACHE STRING "Version de LocaLink")
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Quick Qml QuickControls2 Network Sql Test WebSockets Multimedia)
find_package(OpenSSL REQUIRED)

option(BUILD_TESTS "Build unit/integration tests" ON)

if(BUILD_TESTS)
    enable_testing()
endif()

add_subdirectory(models)
add_subdirectory(services)
add_subdirectory(database)
add_subdirectory(network)
add_subdirectory(core)
add_subdirectory(app)

if(BUILD_TESTS)
    add_subdirectory(tests)
endif()
