#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "Application.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    Application application;
    application.initialize();

    QQmlApplicationEngine engine;
    // Permet d'utiliser "import Themes" (module singleton Theme, cf. ui/Themes/qmldir)
    engine.addImportPath(QStringLiteral("qrc:/ui"));
    engine.rootContext()->setContextProperty("application", &application);
    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
