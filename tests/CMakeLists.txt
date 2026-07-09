enable_testing()

add_executable(test_usermanager UnitTests/test_usermanager.cpp)
target_link_libraries(test_usermanager PRIVATE Qt6::Test Qt6::Sql core database models)
add_test(NAME test_usermanager COMMAND test_usermanager)
