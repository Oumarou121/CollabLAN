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

# --- Icônes multiplateformes ---
if(WIN32)
    set(APP_ICON_RESOURCE ${CMAKE_CURRENT_SOURCE_DIR}/../resources/win/app.rc)
elseif(APPLE)
    set(APP_ICON_RESOURCE ${CMAKE_CURRENT_SOURCE_DIR}/../resources/mac/app.icns)
    set_source_files_properties(${APP_ICON_RESOURCE} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
endif()

add_executable(LocaLink
    main.cpp
    ../ui/qml.qrc
    ${APP_ICON_RESOURCE}
)

if(APPLE)
    set_target_properties(LocaLink PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_ICON_FILE app.icns
        MACOSX_BUNDLE_BUNDLE_NAME "LocaLink"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${APP_BUNDLE_IDENTIFIER}"
    )
endif()

target_link_libraries(LocaLink PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    app_core
)

if(UNIX AND NOT APPLE)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/localink.desktop
            DESTINATION share/applications)
    foreach(size 16 24 32 48 64 128 256 512)
        install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/icons/${size}x${size}/localink.png
                DESTINATION share/icons/hicolor/${size}x${size}/apps)
    endforeach()
endif()