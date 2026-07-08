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

target_link_libraries(network PUBLIC
    Qt6::Core
    Qt6::Network
    Qt6::WebSockets
    OpenSSL::SSL
    OpenSSL::Crypto
)

# --- WebRTC (VoiceService) : libdatachannel ---------------------------------
# Choix documente dans docs/ARCHITECTURE.md (section "Choix techniques").
# Recupere via FetchContent : pas besoin d'installer quoi que ce soit
# manuellement, mais desactivable (COLLABLAN_FETCH_LIBDATACHANNEL=OFF) pour
# les devs qui n'ont pas encore besoin de compiler VoiceService (Sprint 4).
option(COLLABLAN_FETCH_LIBDATACHANNEL "Recuperer et compiler libdatachannel (WebRTC) via FetchContent" ON)

if(COLLABLAN_FETCH_LIBDATACHANNEL)
    include(FetchContent)

    # La signalisation (SDP/ICE) passe par MessagingService (Qt6::WebSockets) :
    # on desactive le websocket interne de libdatachannel, inutile ici.
    set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
    set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
    set(NO_TESTS ON CACHE BOOL "" FORCE)
    # On reste sur OpenSSL (deja une dependance du projet) plutot que GnuTLS.
    set(USE_GNUTLS OFF CACHE BOOL "" FORCE)

    FetchContent_Declare(
        libdatachannel
        GIT_REPOSITORY https://github.com/paullouisageneau/libdatachannel.git
        GIT_TAG        v0.24.0
        GIT_SUBMODULES_RECURSE TRUE
    )
    FetchContent_MakeAvailable(libdatachannel)

    target_link_libraries(network PUBLIC LibDataChannel::LibDataChannel)
endif()
