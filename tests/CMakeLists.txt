add_executable(test_usermanager UnitTests/test_usermanager.cpp)
target_link_libraries(test_usermanager PRIVATE Qt6::Test core)
add_test(NAME test_usermanager COMMAND test_usermanager)

add_executable(test_databasemanager UnitTests/test_databasemanager.cpp)
target_link_libraries(test_databasemanager PRIVATE Qt6::Test database)
add_test(NAME test_databasemanager COMMAND test_databasemanager)

add_executable(test_discoveryservice UnitTests/test_discoveryservice.cpp)
target_link_libraries(test_discoveryservice PRIVATE Qt6::Test network)
add_test(NAME test_discoveryservice COMMAND test_discoveryservice)
