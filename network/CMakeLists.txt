add_library(network STATIC)

file(GLOB_RECURSE NETWORK_SOURCES CONFIGURE_DEPENDS "*.cpp")
target_sources(network PRIVATE ${NETWORK_SOURCES})

target_include_directories(network PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/Discovery
    ${CMAKE_CURRENT_SOURCE_DIR}/Messaging
    ${CMAKE_CURRENT_SOURCE_DIR}/Transfer
    ${CMAKE_CURRENT_SOURCE_DIR}/Voice
    ${CMAKE_CURRENT_SOURCE_DIR}/Security
)

target_link_libraries(network PUBLIC Qt6::Core Qt6::Network Qt6::WebSockets OpenSSL::SSL OpenSSL::Crypto)
