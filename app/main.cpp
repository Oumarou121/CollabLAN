#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QCommandLineParser>
#include <QDebug>

#include "Application.h"
#include "UserManager.h"
#include "Discovery/PeersModel.h"
#include "MessagingContext.h"
#include "MessageModel.h"
#include "GroupModel.h"
#include "TransferContext.h"
#include "NotificationManager.h"

int main(int argc, char *argv[])
{
    // Le .qrc "sounds" est compile dans la bibliotheque STATIQUE "services".
    // Sans reference explicite, l'editeur de liens elague l'objet genere par
    // AUTORCC (rien dans l'executable ne l'appelle), et les ressources
    // ":/sounds/*.wav" restent introuvables au runtime. Q_INIT_RESOURCE force
    // l'enregistrement de la ressource embarquee (le nom correspond au nom
    // du fichier .qrc, ici "sounds", sans le prefixe /sounds/ du <qresource>).
    Q_INIT_RESOURCE(sounds);

    // Toutes les vues QML personnalisent "background" et "contentItem" sur
    // des controles Qt Quick Controls (Button, Label...). Cette personnalisation
    // n'est possible qu'avec un style non-natif (Basic/Fusion/Material) : le
    // style natif de la plateforme (Windows, macOS...) l'ignore et emet un
    // avertissement pour chaque controle. On force donc "Basic" avant toute
    // creation de QGuiApplication (le style doit etre fixe avant le premier
    // objet Qt Quick Controls instancie).
    // Peut etre surcharge par la variable d'environnement QT_QUICK_CONTROLS_STYLE
    // si besoin (ex: pour tester avec "Fusion" ou "Material").
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("Basic"));
    }

    QGuiApplication app(argc, argv);

    // Parser les arguments de ligne de commande
    QCommandLineParser parser;
    parser.setApplicationDescription("CollabLAN - Application de collaboration locale");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption portOption(QStringList() << "p" << "port",
        "Port pour le serveur de messagerie (défaut: 12345)",
        "port", "12345");
    parser.addOption(portOption);

    QCommandLineOption dbOption(QStringList() << "db",
        "Chemin du fichier de base de donnees SQLite (defaut: emplacement standard de l'OS). "
        "Utile pour lancer plusieurs instances sur la meme machine (tests locaux).",
        "path", "");
    parser.addOption(dbOption);

    QCommandLineOption createUserOption(QStringList() << "create-user",
        "Cree (si absent) un utilisateur de test au demarrage, au format nom:motdepasse "
        "(ex: --create-user alice:pass123). Pratique pour peupler rapidement plusieurs "
        "bases separees (une par instance/--db) avec des comptes differents, en l'absence "
        "d'un ecran d'inscription dans l'UI.",
        "nom:motdepasse", "");
    parser.addOption(createUserOption);

    parser.process(app);

    quint16 messagingPort = parser.value(portOption).toUShort();
    const QString dbFilePath = parser.value(dbOption);
    qDebug() << "MessagingServer port:" << messagingPort;

    Application application;
    application.initialize(messagingPort, dbFilePath);

    if (parser.isSet(createUserOption)) {
        const QString spec = parser.value(createUserOption);
        const int sep = spec.indexOf(QLatin1Char(':'));
        if (sep <= 0) {
            qWarning() << "--create-user attend le format nom:motdepasse, recu :" << spec;
        } else {
            const QString name = spec.left(sep);
            const QString password = spec.mid(sep + 1);
            if (application.userManager()->authenticate(name, password).has_value()) {
                qDebug() << "Utilisateur" << name << "existe deja, rien a faire.";
            } else {
                const auto user = application.userManager()->createUser(name, password);
                if (user.has_value()) {
                    qDebug() << "Utilisateur de test cree :" << name;
                } else {
                    qWarning() << "Impossible de creer l'utilisateur" << name
                               << "(code erreur :" << static_cast<int>(application.userManager()->lastError()) << ")";
                }
            }
        }
    }

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
    // Brancher ToastHost.qml (Main.qml) sur les evenements notifiables
    // (message, transfert, connexion/deconnexion - issue #58).
    engine.rootContext()->setContextProperty("notificationManager", static_cast<QObject*>(application.notificationManager()));

    // Enregistrer les types QML pour la messagerie
    qmlRegisterType<core::MessagingContext>("Core", 1, 0, "MessagingContext");
    qmlRegisterType<models::MessageModel>("Models", 1, 0, "MessageModel");
    qmlRegisterType<models::GroupModel>("Models", 1, 0, "GroupModel");

    // Créer et exposer le contexte de messagerie
    core::MessagingContext *messagingContext = new core::MessagingContext(&engine);
    messagingContext->setMessagingManager(application.messagingManager());
    messagingContext->setGroupManager(application.groupManager());
    messagingContext->setUserManager(application.userManager());
    engine.rootContext()->setContextProperty("messagingContext", messagingContext);

    // Créer et exposer le contexte de transfert de fichiers (issue #57) :
    // relie network::TransferService/core::TransferManager a
    // FileTransferView.qml (selection de fichier, choix du destinataire,
    // progression en temps reel).
    core::TransferContext *transferContext = new core::TransferContext(&engine);
    transferContext->setTransferManager(application.transferManager());
    transferContext->setTransferService(application.transferService());
    transferContext->setPeersModel(application.peersModel());
    transferContext->setUserManager(application.userManager());
    engine.rootContext()->setContextProperty("transferContext", transferContext);

    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
