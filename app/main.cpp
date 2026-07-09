#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "Application.h"
#include "UserManager.h"

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
    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
