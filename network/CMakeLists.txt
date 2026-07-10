add_library(network STATIC)

# libdatachannel : implementation WebRTC (PeerConnection, ICE, DTLS-SRTP)
# utilisee par VoiceService pour l'appel audio P2P (issues #60/#61).
# Recuperee via FetchContent plutot que vendorisee ; le websocket interne
# de la lib est desactive (CollabLAN utilise deja Qt WebSockets pour sa
# propre signalisation, cf. VoiceSignalingChannel).
include(FetchContent)
set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
set(NO_TESTS ON CACHE BOOL "" FORCE)
# Contournement d'un bug connu de libsrtp (vendorise par libdatachannel) :
# sur les CMake recents, sa CMakeLists.txt appelle set_target_properties()
# avec une liste de cibles vide quand les apps de test sont construites.
# Les desactiver evite ce chemin de code casse.
set(LIBSRTP_TEST_APPS OFF CACHE BOOL "" FORCE)
set(TEST_APPS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    libdatachannel
    GIT_REPOSITORY https://github.com/paullouisageneau/libdatachannel.git
    GIT_TAG v0.23.0
    GIT_SUBMODULES_RECURSE ON
)

# Certaines dependances vendorisees par libdatachannel (ex. plog) declarent
# cmake_minimum_required() avec une version trop ancienne pour les CMake
# recents (>= 3.31), qui refusent toute compatibilite < 3.5. On force donc
# un plancher de compatibilite le temps de configurer ces sous-projets tiers.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_MakeAvailable(libdatachannel)
unset(CMAKE_POLICY_VERSION_MINIMUM)

file(GLOB_RECURSE NETWORK_SOURCES CONFIGURE_DEPENDS "*.cpp")
file(GLOB_RECURSE NETWORK_HEADERS CONFIGURE_DEPENDS "*.h")
target_sources(network PRIVATE ${NETWORK_SOURCES} ${NETWORK_HEADERS})

target_include_directories(network PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/Discovery
    ${CMAKE_CURRENT_SOURCE_DIR}/Messaging
    ${CMAKE_CURRENT_SOURCE_DIR}/Transfer
    ${CMAKE_CURRENT_SOURCE_DIR}/Voice
    ${CMAKE_CURRENT_SOURCE_DIR}/Security
)

target_link_libraries(network PUBLIC
    Qt6::Core Qt6::Network Qt6::WebSockets Qt6::Multimedia
    OpenSSL::SSL OpenSSL::Crypto
    LibDataChannel::LibDataChannel
)
