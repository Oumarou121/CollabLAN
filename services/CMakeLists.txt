add_library(services STATIC)

file(GLOB SERVICES_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(services PRIVATE ${SERVICES_SOURCES})

# Sons de notification (issue #56) embarques via Qt Resources.
target_sources(services PRIVATE Resources/sounds.qrc)

target_include_directories(services PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(services PUBLIC Qt6::Core Qt6::Multimedia)
