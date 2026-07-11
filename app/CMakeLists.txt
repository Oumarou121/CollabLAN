add_library(app_core STATIC
    Application.cpp
    Application.h
)

target_include_directories(app_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(app_core PUBLIC
    core
    network
    database
    models
    services
)

add_executable(CollabLAN
    main.cpp
    ../ui/qml.qrc
)

target_link_libraries(CollabLAN PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    app_core
)
