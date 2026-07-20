add_library(models STATIC)

file(GLOB MODELS_SOURCES CONFIGURE_DEPENDS "*.cpp")
file(GLOB MODELS_HEADERS CONFIGURE_DEPENDS "*.h")
target_sources(models PRIVATE ${MODELS_SOURCES} ${MODELS_HEADERS})

target_include_directories(models PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(models PUBLIC Qt6::Core Qt6::Qml)

# Enable Qt's automatic MOC/UIC/RCC processing
set_target_properties(models PROPERTIES AUTOMOC ON)
