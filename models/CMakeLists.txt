add_library(models STATIC)

file(GLOB MODELS_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(models PRIVATE ${MODELS_SOURCES})

target_include_directories(models PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(models PUBLIC Qt6::Core)
