add_executable(test_usermanager UnitTests/test_usermanager.cpp)
target_link_libraries(test_usermanager PRIVATE Qt6::Test Qt6::Sql core database models)
add_test(NAME test_usermanager COMMAND test_usermanager)

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
