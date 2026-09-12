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
    Qt6::Widgets
    Qt6::QuickControls2
    app_core
)

if(WIN32)
    # Necessaire pour SetCurrentProcessExplicitAppUserModelID (main.cpp) :
    # sans AUMID enregistre, les notifications systeme affichent le nom brut
    # de l'executable au lieu de "LocaLink".
    target_link_libraries(LocaLink PRIVATE Shell32)

    # CORRECTIF (logo absent des notifications) : la cle de registre
    # IconUri de l'AppUserModelId (main.cpp) exige un chemin direct vers un
    # fichier .ico -- la syntaxe "exe,index" (utilisee pour d'autres
    # mecanismes Windows comme DefaultIcon) n'est pas valide ici et laissait
    # le logo vide. app.ico n'etait jusque-la qu'embarque dans les
    # ressources de l'exe (app.rc) : on en copie aussi une version brute a
    # cote de l'executable pour que le registre puisse la referencer.
    add_custom_command(TARGET LocaLink POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${CMAKE_CURRENT_SOURCE_DIR}/../resources/win/app.ico
            $<TARGET_FILE_DIR:LocaLink>/app.ico
    )
endif()

if(UNIX AND NOT APPLE)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/localink.desktop
            DESTINATION share/applications)
    foreach(size 16 24 32 48 64 128 256 512)
        install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/icons/${size}x${size}/localink.png
                DESTINATION share/icons/hicolor/${size}x${size}/apps)
    endforeach()
endif()