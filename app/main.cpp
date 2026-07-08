#include <QGuiApplication>
#include <QQmlApplicationEngine>

#include "Application.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    Application application;
    application.initialize();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("application", &application);
    engine.load(QUrl(QStringLiteral("qrc:/ui/Home/HomeView.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
