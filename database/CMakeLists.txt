add_library(database STATIC)

file(GLOB_RECURSE DATABASE_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(database PRIVATE ${DATABASE_SOURCES})

target_include_directories(database PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/Repositories
)

target_link_libraries(database PUBLIC Qt6::Core Qt6::Sql)
