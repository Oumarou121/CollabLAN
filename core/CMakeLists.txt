add_library(core STATIC)

file(GLOB CORE_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(core PRIVATE ${CORE_SOURCES})

target_include_directories(core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(core PUBLIC Qt6::Core)
