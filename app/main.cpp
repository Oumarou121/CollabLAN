#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "Application.h"
#include "UserManager.h"
#include "Discovery/PeersModel.h"
#include "SharedFolderManager.h"
#include "SharedFoldersModel.h"
#include "SyncHistoryService.h"
#include "Sync/SyncNetworkService.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    Application application;
    application.initialize();

    QQmlApplicationEngine engine;
    // Permet d'utiliser "import Themes" (module singleton Theme, cf. ui/Themes/qmldir)
    engine.addImportPath(QStringLiteral("qrc:/ui"));
    engine.rootContext()->setContextProperty("application", &application);
    // Brancher LoginView.qml (et les autres ecrans) sur la vraie logique
    // d'authentification (issue #16), a la place du mock precedent.
    engine.rootContext()->setContextProperty("userManager", application.userManager());
    // Brancher UsersView.qml sur la liste des postes decouverts en temps
    // reel par DiscoveryService (issue #17).
    engine.rootContext()->setContextProperty("peersModel", static_cast<QObject*>(application.peersModel()));
    // Brancher SharedFolderView.qml sur la gestion des dossiers partages
    // (creation/suppression, liste temps reel, historique).
    engine.rootContext()->setContextProperty("sharedFolderManager", static_cast<QObject*>(application.sharedFolderManager()));
    engine.rootContext()->setContextProperty("sharedFoldersModel", static_cast<QObject*>(application.sharedFoldersModel()));
    engine.rootContext()->setContextProperty("syncHistoryService", static_cast<QObject*>(application.syncHistoryService()));
    // Brancher AdminView.qml sur la gestion des postes de confiance TLS du
    // canal de synchronisation (accepter/revoquer un poste).
    engine.rootContext()->setContextProperty("syncNetworkService", static_cast<QObject*>(application.syncNetworkService()));
    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
