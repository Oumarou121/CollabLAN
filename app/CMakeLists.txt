add_executable(CollabLAN
    main.cpp
    Application.cpp
    Application.h
)

target_link_libraries(CollabLAN PRIVATE
    Qt6::Quick
    Qt6::Qml
    core
    network
    database
    models
    services
)
