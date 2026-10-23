add_library(network STATIC)

# libdatachannel : implementation WebRTC (PeerConnection, ICE, DTLS-SRTP)
# utilisee par VoiceService pour l'appel audio P2P (issues #60/#61).
# Recuperee via FetchContent plutot que vendorisee ; le websocket interne
# de la lib est desactive (LocaLink utilise deja Qt WebSockets pour sa
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
# Le depot source une fois extrait (build/_deps/libdatachannel-src) n'est
# plus un working copy .git valide (son .git est absent une fois les
# sous-modules extraits/aplatis) : toute reconfiguration ulterieure de
# CMake (par ex. declenchee par l'ajout de nouveaux fichiers sources
# ailleurs dans le projet, via CONFIGURE_DEPENDS) fait echouer l'etape
# "git rev-parse HEAD" de FetchContent, meme en mode UPDATE_DISCONNECTED.
# Une fois le depot deja present localement, on bascule donc en mode
# FETCHCONTENT_FULLY_DISCONNECTED : CMake reutilise alors le repertoire
# existant sans plus jamais invoquer git dessus.
if(EXISTS "${CMAKE_BINARY_DIR}/_deps/libdatachannel-src/CMakeLists.txt")
    set(FETCHCONTENT_FULLY_DISCONNECTED ON)
endif()
# Le mode deconnecte ne vaut que pour libdatachannel (retire apres
# FetchContent_MakeAvailable) : Opus, plus bas, doit pouvoir etre telecharge
# dans un dossier de compilation qui contient deja libdatachannel.

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
unset(FETCHCONTENT_FULLY_DISCONNECTED)

# Opus : codec de la voix des appels (a deux comme en groupe), en bande
# elargie 16 kHz au lieu du G.711 8 kHz. Archive officielle de xiph.org
# (empreinte verifiee) plutot que le depot git : elle contient
# package_version, dont le CMake d'Opus tire son numero de version.
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    opus
    URL https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
    URL_HASH SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# Statique, comme libdatachannel : le CMake d'Opus construit une DLL des que
# BUILD_SHARED_LIBS est vrai (valeur heritee du cache), qu'il faudrait
# ensuite deployer a cote de l'application et de chaque test.
set(LOCALINK_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(opus)
set(BUILD_SHARED_LIBS ${LOCALINK_SAVED_BUILD_SHARED_LIBS})

file(GLOB_RECURSE NETWORK_SOURCES CONFIGURE_DEPENDS "*.cpp")
file(GLOB_RECURSE NETWORK_HEADERS CONFIGURE_DEPENDS "*.h")
target_sources(network PRIVATE ${NETWORK_SOURCES} ${NETWORK_HEADERS})

target_include_directories(network PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/Discovery
    ${CMAKE_CURRENT_SOURCE_DIR}/Election
    ${CMAKE_CURRENT_SOURCE_DIR}/Messaging
    ${CMAKE_CURRENT_SOURCE_DIR}/Sync
    ${CMAKE_CURRENT_SOURCE_DIR}/Transfer
    ${CMAKE_CURRENT_SOURCE_DIR}/Voice
    ${CMAKE_CURRENT_SOURCE_DIR}/Security
)

# database (SyncLogRepository) requis par network/Sync/SyncService.cpp (reconciliation
# post-panne, HYBRID_SERVER_FAILOVER.md section 7). models est deja tire par database.
target_link_libraries(network PUBLIC
    Qt6::Core Qt6::Network Qt6::WebSockets Qt6::Multimedia
    OpenSSL::SSL OpenSSL::Crypto
    LibDataChannel::LibDataChannelStatic   # <- remplacer LibDataChannel::LibDataChannel par ceci
    Opus::opus
    database
)
