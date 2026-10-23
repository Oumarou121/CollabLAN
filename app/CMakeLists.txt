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

# Application graphique : pas de fenetre console chez les utilisateurs. Pour un diagnostic,
# configurer avec -DLOCALINK_CONSOLE=ON (les journaux sont de toute facon ecrits dans
# <AppData>/LocaLink/logs/localink.log, cf. main.cpp).
option(LOCALINK_CONSOLE "Ouvrir une fenetre console avec les journaux (diagnostic)" OFF)
if(LOCALINK_CONSOLE)
    add_executable(LocaLink
        main.cpp
        ../ui/qml.qrc
        ${APP_ICON_RESOURCE}
    )
else()
    add_executable(LocaLink WIN32
        main.cpp
        ../ui/qml.qrc
        ${APP_ICON_RESOURCE}
    )
endif()

if(APPLE)
    set_target_properties(LocaLink PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_ICON_FILE app.icns
        MACOSX_BUNDLE_BUNDLE_NAME "LocaLink"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${APP_BUNDLE_IDENTIFIER}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${LOCALINK_VERSION}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${LOCALINK_VERSION}"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/../resources/mac/Info.plist"
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

    # CORRECTIF (TLS Schannel sur Windows) : sans les DLL OpenSSL a cote de
    # l'executable, Qt ne trouve pas le plugin TLS "openssl" au runtime et
    # retombe silencieusement sur le backend natif Schannel, qui n'honore
    # pas ignoreSslErrors() de la meme facon pour les certificats auto-signes
    # -- d'ou le rejet des connexions WebSocket securisees en production.
    get_filename_component(_openssl_bin_dir "${OPENSSL_INCLUDE_DIR}/../bin" ABSOLUTE)

    find_file(OPENSSL_SSL_DLL
        NAMES libssl-3-x64.dll libssl-3.dll libssl-1_1-x64.dll libssl-1_1.dll
        PATHS "${_openssl_bin_dir}"
        NO_DEFAULT_PATH
    )
    find_file(OPENSSL_CRYPTO_DLL
        NAMES libcrypto-3-x64.dll libcrypto-3.dll libcrypto-1_1-x64.dll libcrypto-1_1.dll
        PATHS "${_openssl_bin_dir}"
        NO_DEFAULT_PATH
    )

    if(OPENSSL_SSL_DLL AND OPENSSL_CRYPTO_DLL)
        add_custom_command(TARGET LocaLink POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${OPENSSL_SSL_DLL}" "${OPENSSL_CRYPTO_DLL}"
                $<TARGET_FILE_DIR:LocaLink>
            COMMENT "Copie des DLL OpenSSL (necessaires au backend TLS 'openssl' de Qt)"
        )
    else()
        message(WARNING
            "DLL OpenSSL introuvables pres de ${_openssl_bin_dir} -- "
            "Qt risque de retomber sur Schannel au runtime sur Windows, "
            "ce qui casse les connexions TLS avec certificats auto-signes. "
            "Verifiez OPENSSL_ROOT_DIR / OPENSSL_INCLUDE_DIR."
        )
    endif()
endif()

if(UNIX AND NOT APPLE)
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/localink.desktop
            DESTINATION share/applications)
    foreach(size 16 24 32 48 64 128 256 512)
        install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../resources/linux/icons/${size}x${size}/localink.png
                DESTINATION share/icons/hicolor/${size}x${size}/apps)
    endforeach()
endif()