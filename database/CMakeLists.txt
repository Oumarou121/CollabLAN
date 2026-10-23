add_library(database STATIC)

file(GLOB_RECURSE DATABASE_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(database PRIVATE ${DATABASE_SOURCES})

target_include_directories(database PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/Repositories
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(database PUBLIC Qt6::Core Qt6::Sql models)

# Migrations embarquees dans l'executable : sur un poste ou seule l'application
# a ete copiee, ni database/Migrations a cote de l'executable ni le dossier des
# sources n'existent, et la base restait sans schema (cf. DatabaseManager).
file(GLOB DATABASE_MIGRATIONS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Migrations/*.sql")
qt_add_resources(database "database_migrations"
    PREFIX "/database/migrations"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/Migrations"
    FILES ${DATABASE_MIGRATIONS}
)
