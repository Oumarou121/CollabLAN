add_executable(test_usermanager UnitTests/test_usermanager.cpp)
target_link_libraries(test_usermanager PRIVATE Qt6::Test Qt6::Sql core database models)
add_test(NAME test_usermanager COMMAND test_usermanager)

add_executable(test_settingsmodel UnitTests/test_settingsmodel.cpp)
target_link_libraries(test_settingsmodel PRIVATE Qt6::Test core)
add_test(NAME test_settingsmodel COMMAND test_settingsmodel)

add_executable(test_databasemanager UnitTests/test_databasemanager.cpp)
target_link_libraries(test_databasemanager PRIVATE Qt6::Test database)
add_test(NAME test_databasemanager COMMAND test_databasemanager)

add_executable(test_discoveryservice UnitTests/test_discoveryservice.cpp)
target_link_libraries(test_discoveryservice PRIVATE Qt6::Test network)
add_test(NAME test_discoveryservice COMMAND test_discoveryservice)

add_executable(test_peersmodel UnitTests/test_peersmodel.cpp)
target_link_libraries(test_peersmodel PRIVATE Qt6::Test Qt6::Core network)
add_test(NAME test_peersmodel COMMAND test_peersmodel)

add_executable(test_securityservice UnitTests/test_securityservice.cpp)
target_link_libraries(test_securityservice PRIVATE Qt6::Test network)
add_test(NAME test_securityservice COMMAND test_securityservice)

add_executable(test_tlshandshakeservice UnitTests/test_tlshandshakeservice.cpp)
target_link_libraries(test_tlshandshakeservice PRIVATE Qt6::Test Qt6::Network network)
add_test(NAME test_tlshandshakeservice COMMAND test_tlshandshakeservice)
add_executable(test_userrepository UnitTests/test_userrepository.cpp)
target_link_libraries(test_userrepository PRIVATE Qt6::Test database models)
add_test(NAME test_userrepository COMMAND test_userrepository)

add_executable(test_serverelectionrepository UnitTests/test_serverelectionrepository.cpp)
target_link_libraries(test_serverelectionrepository PRIVATE Qt6::Test database models)
add_test(NAME test_serverelectionrepository COMMAND test_serverelectionrepository)

# Plan #71 : etat pending/authorized/revoked des machines autorisees.
add_executable(test_authorizedmachinerepository UnitTests/test_authorizedmachinerepository.cpp)
target_link_libraries(test_authorizedmachinerepository PRIVATE Qt6::Test database models)
add_test(NAME test_authorizedmachinerepository COMMAND test_authorizedmachinerepository)

add_executable(test_permissionmanager UnitTests/test_permissionmanager.cpp)
target_link_libraries(test_permissionmanager PRIVATE Qt6::Test core database models)
add_test(NAME test_permissionmanager COMMAND test_permissionmanager)

add_executable(test_messagingservice UnitTests/test_messagingservice.cpp)
target_link_libraries(test_messagingservice PRIVATE Qt6::Test Qt6::WebSockets network)
add_test(NAME test_messagingservice COMMAND test_messagingservice)

add_executable(test_messagingmanager UnitTests/test_messagingmanager.cpp)
target_link_libraries(test_messagingmanager PRIVATE Qt6::Test core database models)
add_test(NAME test_messagingmanager COMMAND test_messagingmanager)

add_executable(test_groupmanager UnitTests/test_groupmanager.cpp)
target_link_libraries(test_groupmanager PRIVATE Qt6::Test core database models)
add_test(NAME test_groupmanager COMMAND test_groupmanager)

add_executable(test_messagerepository UnitTests/test_messagerepository.cpp)
target_link_libraries(test_messagerepository PRIVATE Qt6::Test database models)
add_test(NAME test_messagerepository COMMAND test_messagerepository)

add_executable(test_grouprepository UnitTests/test_grouprepository.cpp)
target_link_libraries(test_grouprepository PRIVATE Qt6::Test database models)
add_test(NAME test_grouprepository COMMAND test_grouprepository)

add_executable(test_notification UnitTests/test_notification.cpp)
target_link_libraries(test_notification PRIVATE Qt6::Test core services models)
add_test(NAME test_notification COMMAND test_notification)

add_executable(test_transferrepository UnitTests/test_transferrepository.cpp)
target_link_libraries(test_transferrepository PRIVATE Qt6::Test database models)
add_test(NAME test_transferrepository COMMAND test_transferrepository)

add_executable(test_callhistoryrepository UnitTests/test_callhistoryrepository.cpp)
target_link_libraries(test_callhistoryrepository PRIVATE Qt6::Test database models)
add_test(NAME test_callhistoryrepository COMMAND test_callhistoryrepository)

add_executable(test_transferservice UnitTests/test_transferservice.cpp)
target_link_libraries(test_transferservice PRIVATE Qt6::Test Qt6::Network network)
add_test(NAME test_transferservice COMMAND test_transferservice)

# Issue #59 : test d'integration simulant une veritable coupure reseau en
# plein transfert (destruction de la connexion en cours), puis verifiant
# la reprise automatique et l'integrite (checksum) du fichier final.
add_executable(test_transferresumeintegration UnitTests/test_transferresumeintegration.cpp)
target_link_libraries(test_transferresumeintegration PRIVATE Qt6::Test Qt6::Network network)
add_test(NAME test_transferresumeintegration COMMAND test_transferresumeintegration)

add_executable(test_transfermanager UnitTests/test_transfermanager.cpp)
target_link_libraries(test_transfermanager PRIVATE Qt6::Test Qt6::Network core database models network)
add_test(NAME test_transfermanager COMMAND test_transfermanager)

add_executable(test_transfercontext UnitTests/test_transfercontext.cpp)
target_link_libraries(test_transfercontext PRIVATE Qt6::Test Qt6::Network core database models network)
add_test(NAME test_transfercontext COMMAND test_transfercontext)

add_executable(test_audioservice UnitTests/test_audioservice.cpp)
target_link_libraries(test_audioservice PRIVATE Qt6::Test Qt6::Multimedia services)
add_test(NAME test_audioservice COMMAND test_audioservice)

add_executable(test_pcmconverter UnitTests/test_pcmconverter.cpp)
target_link_libraries(test_pcmconverter PRIVATE services)
add_test(NAME test_pcmconverter COMMAND test_pcmconverter)

add_executable(test_electionservice UnitTests/test_electionservice.cpp)
target_link_libraries(test_electionservice PRIVATE Qt6::Test Qt6::Network network models)
add_test(NAME test_electionservice COMMAND test_electionservice)

add_executable(test_synclogrepository UnitTests/test_synclogrepository.cpp)
target_link_libraries(test_synclogrepository PRIVATE Qt6::Test database models)
add_test(NAME test_synclogrepository COMMAND test_synclogrepository)

add_executable(test_syncserviceintegration UnitTests/test_syncserviceintegration.cpp)
target_link_libraries(test_syncserviceintegration PRIVATE Qt6::Test Qt6::WebSockets Qt6::Network Qt6::Sql database models network)
add_test(NAME test_syncserviceintegration COMMAND test_syncserviceintegration)

add_executable(test_applicationelectionwiring UnitTests/test_applicationelectionwiring.cpp)
target_link_libraries(test_applicationelectionwiring PRIVATE Qt6::Test Qt6::Network Qt6::Sql app_core network models)
add_test(NAME test_applicationelectionwiring COMMAND test_applicationelectionwiring)

add_executable(test_applicationreconciliationwiring UnitTests/test_applicationreconciliationwiring.cpp)
target_link_libraries(test_applicationreconciliationwiring PRIVATE Qt6::Test Qt6::Network Qt6::Sql app_core network models)
add_test(NAME test_applicationreconciliationwiring COMMAND test_applicationreconciliationwiring)

# Release 2/3 : detection des changements + journal de synchronisation
add_executable(test_sharedfoldermanager UnitTests/test_sharedfoldermanager.cpp)
target_link_libraries(test_sharedfoldermanager PRIVATE Qt6::Test core database models)
add_test(NAME test_sharedfoldermanager COMMAND test_sharedfoldermanager)

add_executable(test_foldersyncservice UnitTests/test_foldersyncservice.cpp)
target_link_libraries(test_foldersyncservice PRIVATE Qt6::Test core database models network)
add_test(NAME test_foldersyncservice COMMAND test_foldersyncservice)

add_executable(test_syncoperationrepository UnitTests/test_syncoperationrepository.cpp)
target_link_libraries(test_syncoperationrepository PRIVATE Qt6::Test database models)
add_test(NAME test_syncoperationrepository COMMAND test_syncoperationrepository)

add_executable(test_folderwatcher UnitTests/test_folderwatcher.cpp)
target_link_libraries(test_folderwatcher PRIVATE Qt6::Test core)
add_test(NAME test_folderwatcher COMMAND test_folderwatcher)

add_executable(test_syncengine UnitTests/test_syncengine.cpp)
target_link_libraries(test_syncengine PRIVATE Qt6::Test core database models)
add_test(NAME test_syncengine COMMAND test_syncengine)

add_executable(test_syncengine_multinode_integration UnitTests/test_syncengine_multinode_integration.cpp)
target_link_libraries(test_syncengine_multinode_integration PRIVATE Qt6::Test core database models network)
add_test(NAME test_syncengine_multinode_integration COMMAND test_syncengine_multinode_integration)
# Lot 1 securite : garde des chemins des dossiers partages (traversee "../").
add_executable(test_safepath UnitTests/test_safepath.cpp)
target_link_libraries(test_safepath PRIVATE Qt6::Test core)
add_test(NAME test_safepath COMMAND test_safepath)

# Lot 1 securite : un transfert n'est accepte que sur le certificat TLS prouve (pas l'empreinte annoncee).
add_executable(test_transferidentity UnitTests/test_transferidentity.cpp)
target_link_libraries(test_transferidentity PRIVATE Qt6::Test Qt6::Network network)
add_test(NAME test_transferidentity COMMAND test_transferidentity)

# Lot 1 securite : machines en attente sans aucun message, jamais de demarrage en clair.
add_executable(test_messagingserverauth UnitTests/test_messagingserverauth.cpp)
target_link_libraries(test_messagingserverauth PRIVATE Qt6::Test Qt6::WebSockets network)
add_test(NAME test_messagingserverauth COMMAND test_messagingserverauth)

# Lot 2 securite : journal de synchronisation filtre par utilisateur pour les clients.
add_executable(test_syncvisibility UnitTests/test_syncvisibility.cpp)
target_link_libraries(test_syncvisibility PRIVATE Qt6::Test network models)
add_test(NAME test_syncvisibility COMMAND test_syncvisibility)

# Lot 3 : messages de groupe en temps reel reellement traites (code auparavant inatteignable).


# Lot 3 : reprise, integrite, fichier existant preserve, limite de taille en reception.
add_executable(test_transferintegrity UnitTests/test_transferintegrity.cpp)
target_link_libraries(test_transferintegrity PRIVATE Qt6::Test Qt6::Network network)
add_test(NAME test_transferintegrity COMMAND test_transferintegrity)
