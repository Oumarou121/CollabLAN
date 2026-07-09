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
