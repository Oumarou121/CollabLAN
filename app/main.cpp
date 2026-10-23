#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QHostInfo>

#include "network/Discovery/DiscoveryService.h"
#include <QQuickStyle>
#include <QWindow>
#include <QIcon>
#include <QPainter>
#include <QFont>
#include <QFontDatabase>
#include <QTimer>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QAction>
#include <QCommandLineParser>
#include <QSettings>
#include <QDir>
#include <QDebug>
#include <QSslConfiguration>
#include <QSslSocket>

#include "Application.h"
#include "UserManager.h"
#include "Discovery/PeersModel.h"
#include "MessagingContext.h"
#include "MessageModel.h"
#include "GroupModel.h"
#include "TransferContext.h"
#include "SharedFolderContext.h"
#include "CallContext.h"
#include "NotificationManager.h"
#include "AudioService.h"
#include "CallHistoryManager.h"
#include "CallHistoryModel.h"
#include "UserManagementModel.h"
#include "AuditLogModel.h"
#include "AuthorizedMachineModel.h"
#include "SettingsModel.h"
#include "Election/ElectionService.h"
#include "Transfer/TransferService.h"
#include "Voice/VoiceService.h"

#include <rtc/rtc.hpp>

#ifdef Q_OS_WIN
#include <shobjidl.h>
#endif

#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QDateTime>
#include <QStandardPaths>
#include <QCoreApplication>

// Journal de l'application : <AppData>/LocaLink/logs/localink.log (dossier propre a l'utilisateur,
// toujours accessible en ecriture, contrairement au dossier d'installation). Les messages emis
// avant que ce chemin soit connu (avant QApplication) ne vont que sur la sortie d'erreur.
// Les messages de niveau debug ne sont conserves que dans les builds Debug. Le contenu des
// messages echanges n'est jamais journalise (cf. MessagingServer/MessagingService).
static QString g_logPath;

static void fileMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
#ifdef NDEBUG
    if (type == QtDebugMsg)
        return;
#endif
    const char *levelStr = "DEBUG";
    switch (type) {
        case QtDebugMsg:    levelStr = "DEBUG";   break;
        case QtInfoMsg:     levelStr = "INFO";    break;
        case QtWarningMsg:  levelStr = "WARN";    break;
        case QtCriticalMsg: levelStr = "CRITICAL";break;
        case QtFatalMsg:    levelStr = "FATAL";   break;
    }

    const QString line = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz")
        + " [" + levelStr + "] " + msg
        + (context.file ? QString(" (%1:%2)").arg(context.file).arg(context.line) : QString());

    QTextStream(stderr) << line << Qt::endl;

    if (!g_logPath.isEmpty()) {
        static QFile logFile(g_logPath);
        static bool opened = logFile.open(QIODevice::Append | QIODevice::Text);
        if (opened) {
            QTextStream out(&logFile);
            out << line << Qt::endl;
        }
    }

    if (type == QtFatalMsg)
        abort();
}

/// Fixe le fichier de journal une fois l'organisation/l'application connues ; garde une seule
/// archive (.1) au-dela de 5 Mo pour que le journal ne grossisse pas indefiniment.
static void setupLogFile()
{
    const QString dir = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).filePath(QStringLiteral("logs"));
    if (!QDir().mkpath(dir))
        return;
    const QString path = QDir(dir).filePath(QStringLiteral("localink.log"));
    if (QFileInfo(path).size() > 5 * 1024 * 1024) {
        QFile::remove(path + QStringLiteral(".1"));
        QFile::rename(path, path + QStringLiteral(".1"));
    }
    g_logPath = path;
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(fileMessageHandler);

    // Garde-fou backend TLS : deplace apres QApplication app(argc, argv)
    // plus bas (cf. commentaire a cet endroit) -- QSslSocket::availableBackends()
    // / setActiveBackend() reposent en interne sur un chargeur de plugins TLS
    // qui est lui aussi un "application static" Qt exigeant une instance
    // QCoreApplication vivante, exactement comme applicationDirPath() plus haut.

    // Sans cet appel, toute la journalisation interne de libdatachannel
    // (gathering ICE, negociation DTLS, erreurs de certificat...) est
    // totalement silencieuse : impossible de diagnostiquer un appel qui
    // reste bloque sans jamais lever d'exception cote Qt. Debug en
    // developpement ; a repasser en LogLevel::Warning pour une release
    // si le volume de logs devient genant.
    rtc::InitLogger(rtc::LogLevel::Warning);

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

#ifdef Q_OS_WIN
    // CORRECTIF : sans AppUserModelID explicite, Windows n'a aucun moyen de
    // retrouver un nom d'affichage propre pour le processus et retombe sur
    // le nom brut de l'executable (ex: "LocaLink.exe") dans l'en-tete des
    // notifications systeme (Action Center / toasts). Cet appel doit se
    // faire avant toute creation de fenetre/QApplication pour etre pris en
    // compte par le shell. Contrairement a QCoreApplication::applicationName()
    // (qui ne concerne que Qt), l'AUMID est ce que Windows utilise
    // reellement pour l'identite du processus aupres du systeme.
    SetCurrentProcessExplicitAppUserModelID(L"LocaLink.SharedFolderApp");
#endif

    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);

    // Garde-fou backend TLS : sur Windows, meme avec les DLL OpenSSL presentes
    // a cote de l'executable, Qt 6.5+ peut par defaut utiliser le backend natif
    // Schannel plutot qu'OpenSSL -- il faut le demander explicitement. Schannel
    // n'honore pas ignoreSslErrors() de la meme facon pour les certificats
    // auto-signes, d'ou l'echec silencieux des connexions WebSocket securisees
    // observe en production malgre un deploiement correct des DLL.
    // Doit venir APRES QApplication app(argc, argv) : QSslSocket::
    // availableBackends()/setActiveBackend() reposent sur un chargeur de
    // plugins TLS qui est lui-meme un "application static" Qt (cf. crash
    // QFactoryLoader/Q_QAS_qtlsbLoader sans instance QCoreApplication).
#ifdef Q_OS_WIN
    qDebug() << "[TLS] backends disponibles:" << QSslSocket::availableBackends()
             << "- backend actif avant selection:" << QSslSocket::activeBackend();

    if (QSslSocket::availableBackends().contains(QLatin1String("openssl"))) {
        QSslSocket::setActiveBackend(QLatin1String("openssl"));
    } else {
        qWarning() << "[TLS] Backend 'openssl' indisponible (DLL manquantes ?) --"
                   << "repli sur" << QSslSocket::activeBackend()
                   << ": les connexions securisees vers des certificats"
                   << "auto-signes vont probablement echouer.";
    }

    qDebug() << "[TLS] backend actif apres selection:" << QSslSocket::activeBackend();
#endif

#ifdef Q_OS_WIN
    // CORRECTIF (suite) : SetCurrentProcessExplicitAppUserModelID() dit a
    // Windows QUEL identifiant utiliser pour ce processus, mais sans mapping
    // enregistre vers un nom/icone, l'Action Center affiche l'AUMID brut
    // ("LocaLink.SharedFolderApp") au lieu d'un nom lisible. Pour une appli
    // Win32 classique (pas de paquet MSIX/installeur creant un raccourci
    // Menu Demarrer avec proprietes Shell), la methode documentee par
    // Microsoft est d'enregistrer ce mapping directement dans le registre
    // sous HKCU\Software\Classes\AppUserModelId\<AUMID>. Idempotent : se
    // recree a l'identique a chaque lancement, sans effet de bord si deja
    // present.
    {
        QSettings aumIdSettings(
            QStringLiteral("HKEY_CURRENT_USER\\Software\\Classes\\AppUserModelId\\LocaLink.SharedFolderApp"),
            QSettings::NativeFormat);
        aumIdSettings.setValue(QStringLiteral("DisplayName"), QStringLiteral("LocaLink"));
        // IconUri exige un chemin direct vers un fichier .ico -- la syntaxe
        // "exe,index" (valable pour DefaultIcon) n'est pas supportee ici et
        // laissait le logo absent des notifications. app.ico est copie a
        // cote de l'executable par CMakeLists.txt (app/CMakeLists.txt,
        // POST_BUILD) specifiquement pour cet usage.
        aumIdSettings.setValue(QStringLiteral("IconUri"),
                                QDir::toNativeSeparators(
                                    QCoreApplication::applicationDirPath() + QStringLiteral("/app.ico")));
    }
#endif

    // CORRECTIF : sans ces deux appels, QSettings (core::SettingsModel,
    // "Se souvenir de moi") n'a pas d'organisation/application stable pour
    // determiner OU stocker ses valeurs (registre Windows / fichier .conf
    // sous Linux) -- QCoreApplication::organizationName()/applicationName()
    // restent vides par defaut, ce qui rend QSettings() peu fiable d'un
    // lancement a l'autre (cle vide ou emplacement incoherent selon l'OS).
    // A definir AVANT toute construction de QSettings (SettingsModel est
    // cree plus bas, mais reste prudent de le faire au plus tot).
    QCoreApplication::setOrganizationName(QStringLiteral("LocaLink"));
    QCoreApplication::setApplicationName(QStringLiteral("LocaLink"));
    setupLogFile();

    // CORRECTIF (persistance des ports reseau, ecran Parametres > Ports
    // reseau) : messagingPort/discoveryPort etaient bien sauvegardes dans
    // QSettings par SettingsModel::save(), mais jamais relus au demarrage
    // -- le port de messagerie venait uniquement de --port (defaut 12345
    // code en dur) et le port de decouverte UDP restait fige a 45454 dans
    // DiscoveryService. On les relit ici, tot, pour servir de valeur par
    // defaut : un --port explicite en ligne de commande reste prioritaire
    // (utile pour les tests multi-instances), mais en usage normal c'est
    // desormais bien le reglage enregistre dans Parametres qui s'applique
    // (au prochain lancement : un socket deja lie ne peut pas changer de
    // port a chaud).
    QSettings persistedSettings;
    const quint16 persistedMessagingPort =
        static_cast<quint16>(persistedSettings.value("messagingPort", 12345).toUInt());
    const quint16 persistedDiscoveryPort =
        static_cast<quint16>(persistedSettings.value("discoveryPort", 45454).toUInt());

    // Parser les arguments de ligne de commande
    QCommandLineParser parser;
    parser.setApplicationDescription("LocaLink - Application de collaboration locale");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption portOption(QStringList() << "p" << "port",
        "Port pour le serveur de messagerie (défaut: valeur enregistrée dans Paramètres, 12345 sinon)",
        "port", QString::number(persistedMessagingPort));
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

    QCommandLineOption roleOption(QStringList() << "role",
        "Force le role initial de ce poste dans l'election de serveur "
        "(SERVER, CLIENT ou TEMP_SERVER), en ecrasant ce qui est deja "
        "persiste en base. Reserve aux scenarios de test multi-instances "
        "(HYBRID_SERVER_FAILOVER.md) : en usage normal, le role evolue "
        "seul via ElectionService et n'a pas besoin d'etre force.",
        "role", "");
    parser.addOption(roleOption);

    QCommandLineOption priorityWeightOption(QStringList() << "priority-weight",
        "Force le priority_weight de ce poste (plus petit = plus prioritaire "
        "pour devenir TEMP_SERVER lors d'une election). Utile en test pour "
        "designer a l'avance quel client doit gagner l'election. Ignore si "
        "absent (garde la valeur deja en base, 100 par defaut).",
        "poids", "-1");
    parser.addOption(priorityWeightOption);

    QCommandLineOption discoveryPortOption(QStringList() << "discovery-port",
        "Port UDP pour la découverte réseau (défaut: valeur enregistrée dans "
        "Paramètres, 45454 sinon).",
        "port", QString::number(persistedDiscoveryPort));
    parser.addOption(discoveryPortOption);

    parser.process(app);

    quint16 messagingPort = parser.value(portOption).toUShort();
    const quint16 discoveryPort = parser.value(discoveryPortOption).toUShort();
    const QString dbFilePath = parser.value(dbOption);
    // Options de test (scenarios multi-instances) : reservees aux builds Debug. En production,
    // elles permettraient de creer un compte avec un mot de passe visible dans la liste des
    // processus ou de forcer le role de serveur du poste : elles sont ignorees.
#ifdef NDEBUG
    const bool devOptionsAllowed = false;
#else
    const bool devOptionsAllowed = true;
#endif
    if (!devOptionsAllowed && (parser.isSet(roleOption) || parser.isSet(priorityWeightOption)
                               || parser.isSet(createUserOption))) {
        qWarning() << "Options --role, --priority-weight et --create-user ignorees : reservees aux builds de developpement.";
    }
    const QString roleOverride = devOptionsAllowed ? parser.value(roleOption) : QString();
    const int priorityWeightOverride = devOptionsAllowed ? parser.value(priorityWeightOption).toInt() : -1;
    qDebug() << "MessagingServer port:" << messagingPort << "- DiscoveryService port:" << discoveryPort;

    Application application;
    application.setDiscoveryPort(discoveryPort);
    application.initialize(messagingPort, dbFilePath, roleOverride, priorityWeightOverride);

    if (devOptionsAllowed && parser.isSet(createUserOption)) {
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

    // Police a chasse fixe de l interface (empreintes, adresses, ports) :
    // Cascadia Mono n est livree qu avec Windows 11 / Windows Terminal. Sans
    // elle (Windows 10), Qt devait chercher un remplacant au hasard, parfois a
    // chasse variable ; Consolas est presente sur tous les Windows.
    QFont::insertSubstitutions(QStringLiteral("Cascadia Mono"),
                               {QStringLiteral("Consolas"), QStringLiteral("Courier New")});

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
    engine.rootContext()->setContextProperty("discoveryService", static_cast<QObject*>(application.discoveryService()));
    // Brancher ToastHost.qml (Main.qml) sur les evenements notifiables
    // (message, transfert, connexion/deconnexion - issue #58).
    engine.rootContext()->setContextProperty("notificationManager", static_cast<QObject*>(application.notificationManager()));
    // Expose AudioService en QML pour que SettingsView puisse lire/modifier
    // soundEnabled et volume sans passer par Application (issue #56).
    engine.rootContext()->setContextProperty("audioService", static_cast<QObject*>(application.audioService()));
    // Brancher SettingsView.qml (priority_weight/timeout) et l'indicateur de
    // role dans Main.qml sur ElectionService (HYBRID_SERVER_FAILOVER.md
    // section 9, etape 5).
    engine.rootContext()->setContextProperty("electionService", static_cast<QObject*>(application.electionService()));

    // Enregistrer les types QML pour la messagerie
    qmlRegisterType<core::MessagingContext>("Core", 1, 0, "MessagingContext");
    qmlRegisterType<models::MessageModel>("Models", 1, 0, "MessageModel");
    qmlRegisterType<models::GroupModel>("Models", 1, 0, "GroupModel");

    // Créer et exposer le contexte de messagerie
    core::MessagingContext *messagingContext = new core::MessagingContext(&engine);
    messagingContext->setMessagingManager(application.messagingManager());
    messagingContext->setGroupManager(application.groupManager());
    messagingContext->setUserManager(application.userManager());
    messagingContext->setPeersModel(application.peersModel());
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

    // Créer et exposer le contexte d'appel vocal (issues #60/#61/#64) :
    // relie network::VoiceService (signalisation WebRTC + session media) a
    // CallView.qml. Expose globalement (comme electionService plus haut,
    // et non uniquement via qmlRegisterType) pour que Main.qml puisse
    // ecouter callContext.callStateChanged en dehors de CallView (navigation
    // automatique vers l'ecran d'appel sur reception d'un appel entrant,
    // meme depuis un autre ecran).
    core::CallContext *callContext = new core::CallContext(&engine);
    callContext->setVoiceService(application.voiceService());
    engine.rootContext()->setContextProperty("callContext", callContext);

    // Créer et exposer le modèle de l'historique des appels
    // (CallHistoryView.qml) : persiste chaque appel émis/reçu en base
    // (migration 013) et affiche l'historique de l'utilisateur local
    // actuellement connecté.
    core::CallHistoryModel *callHistoryModel = new core::CallHistoryModel(&engine);
    callHistoryModel->setUserManager(application.userManager());
    callHistoryModel->setCallHistoryManager(application.callHistoryManager());
    engine.rootContext()->setContextProperty("callHistoryModel", callHistoryModel);

    // CORRECTIF : auditLogModel et authorizedMachineModel avaient ete retires
    // du contexte QML lors d'une precedente passe de nettoyage ("non
    // utilises"), en se basant sur le fait qu'AuditManager/PermissionManager
    // restent actifs cote C++ (journalisation des tentatives refusees,
    // controle des machines autorisees au niveau reseau - MessagingService/
    // MessagingServer/DiscoveryService, voir plus haut). C'etait une erreur :
    // AdminView.qml consomme directement "auditLogModel" (onglet "Journal
    // d'audit" - model, filtres, export CSV) et "authorizedMachineModel"
    // (onglet "Machines autorisees" - liste, ajout/revocation/suppression),
    // par leur nom en tant que proprietes de contexte globales. Sans cette
    // exposition, les deux onglets referencaient des identifiants QML
    // indefinis : listes vides, boutons inoperants, warnings QML silencieux
    // a l'exécution plutot qu'une erreur visible. On les recree ici, sur le
    // meme patron que callHistoryModel/userManagementModel ci-dessus.
    core::AuditLogModel *auditLogModel = new core::AuditLogModel(&engine);
    auditLogModel->setAuditManager(reinterpret_cast<QObject*>(application.auditManager()));
    engine.rootContext()->setContextProperty("auditLogModel", auditLogModel);

    core::AuthorizedMachineModel *authorizedMachineModel = new core::AuthorizedMachineModel(&engine);
    authorizedMachineModel->setPermissionManager(application.permissionManager());
    // CORRECTIF : added_by restait fige a l'id 1, quel que soit l'admin
    // reellement connecte qui autorise/revoque/supprime une machine depuis
    // l'onglet "Machines autorisees". On branche desormais le UserManager
    // pour que l'audit reflete le veritable auteur de l'action.
    authorizedMachineModel->setUserManager(application.userManager());
    authorizedMachineModel->refresh();
    engine.rootContext()->setContextProperty("authorizedMachineModel", authorizedMachineModel);

    // Créer et exposer le modèle de gestion des utilisateurs (issue #69).
    core::UserManagementModel *userManagementModel = new core::UserManagementModel(&engine);
    userManagementModel->setUserManager(application.userManager());
    userManagementModel->refresh();
    engine.rootContext()->setContextProperty("userManagementModel", userManagementModel);

    // Créer et exposer le modèle de paramètres globaux (issue #69).
    core::SettingsModel *settingsModel = new core::SettingsModel(&engine);
    engine.rootContext()->setContextProperty("settingsModel", settingsModel);

    // CORRECTIF : defaultDownloadPath restait une simple valeur d'affichage
    // dans SettingsView.qml, jamais consommee par le reseau -- les fichiers
    // recus continuaient d'atterrir dans le repertoire par defaut de
    // TransferService (~/Documents/LocaLink Transfers) quel que soit le
    // reglage. On applique la valeur persistee au demarrage, puis on
    // repercute tout changement ulterieur (ecran Parametres) en temps reel.
    if (application.transferService() && !settingsModel->defaultDownloadPath().isEmpty()) {
        application.transferService()->setReceiveDirectory(settingsModel->defaultDownloadPath());
    }
    QObject::connect(settingsModel, &core::SettingsModel::defaultDownloadPathChanged,
                      &application, [settingsModel, &application]() {
        if (application.transferService())
            application.transferService()->setReceiveDirectory(settingsModel->defaultDownloadPath());
    });

    // CORRECTIF : enableNotifications restait une simple valeur d'affichage
    // dans SettingsView.qml, jamais consommee -- NotificationManager expose
    // pourtant deja setNotificationsEnabled()/notificationsEnabled(), il
    // manquait juste le branchement. On applique la valeur persistee au
    // demarrage, puis on repercute tout changement ulterieur (ecran
    // Parametres) en temps reel.
    if (application.notificationManager()) {
        application.notificationManager()->setNotificationsEnabled(settingsModel->enableNotifications());
    }
    QObject::connect(settingsModel, &core::SettingsModel::enableNotificationsChanged,
                      &application, [settingsModel, &application]() {
        if (application.notificationManager())
            application.notificationManager()->setNotificationsEnabled(settingsModel->enableNotifications());
    });

    // CORRECTIF : le README annonce un parametre "nom du poste", mais ce nom
    // etait fige sur QHostInfo::localHostName() -- deux machines au nom Windows
    // generique apparaissaient donc a l'identique dans la liste des pairs, sans
    // aucun moyen de les distinguer. settingsModel->machineName() vide conserve
    // l'ancien comportement (nom d'hote).
    const auto applyMachineName = [settingsModel, &application]() {
        if (!application.discoveryService())
            return;
        const QString chosen = settingsModel->machineName();
        application.discoveryService()->setLocalName(chosen.isEmpty() ? QHostInfo::localHostName()
                                                                      : chosen);
    };
    applyMachineName();
    QObject::connect(settingsModel, &core::SettingsModel::machineNameChanged,
                      &application, applyMachineName);

    // Créer et exposer le contexte "Shared Folder" (1ère tranche : creer/
    // lister/supprimer des dossiers partages + indexation locale de leur
    // contenu, sans synchronisation reseau -- voir core::SharedFolderManager).
    core::SharedFolderContext *sharedFolderContext = new core::SharedFolderContext(&engine);
    sharedFolderContext->setSharedFolderManager(application.sharedFolderManager());
    sharedFolderContext->setSyncEngine(application.syncEngine());
    sharedFolderContext->setUserManager(application.userManager());
    sharedFolderContext->setFolderSyncService(application.folderSyncService());
    engine.rootContext()->setContextProperty("sharedFolderContext", sharedFolderContext);

    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    if (!window)
        return -1;

    QSystemTrayIcon trayIcon(QIcon(QStringLiteral(":/ui/Assets/logo.png")), &app);
    const QIcon applicationIcon = trayIcon.icon();
    const int iconFontId = QFontDatabase::addApplicationFont(
        QStringLiteral(":/ui/Assets/fonts/fontawesome-webfont.ttf"));
    const QString iconFontFamily = iconFontId >= 0
        ? QFontDatabase::applicationFontFamilies(iconFontId).value(0)
        : QString();
    // Table alignee sur Toast.qml (accentColor / iconGlyph) afin que
    // l'icone de la notification systeme (tray, hors-plan) corresponde a
    // la meme categorie que la notification en avant-plan. Avant ce
    // correctif, seuls "call" et "transfer" avaient un rendu dedie ;
    // "connection", "disconnection", "group" et "folder" retombaient tous
    // sur l'enveloppe verte generique du cas "message", ce qui les rendait
    // non representatifs (ex: une deconnexion de poste affichait la meme
    // icone qu'un nouveau message).
    const auto notificationIcon = [iconFontFamily](const QString &category) {
        QPixmap pixmap(64, 64);
        pixmap.fill(Qt::transparent);

        QPainter painter(&pixmap);
        const QColor color = category == QStringLiteral("call")
            ? QColor(QStringLiteral("#D6455A"))         // Theme.error (light)
            : category == QStringLiteral("transfer")
                ? QColor(QStringLiteral("#2457A6"))     // Theme.primary (light)
                : category == QStringLiteral("connection")
                    ? QColor(QStringLiteral("#1FA971")) // Theme.success (light)
                    : category == QStringLiteral("disconnection")
                        ? QColor(QStringLiteral("#536273")) // Theme.textSecondary (light)
                        : category == QStringLiteral("group")
                            ? QColor(QStringLiteral("#2457A6")) // Theme.accent (= Theme.primary)
                            : category == QStringLiteral("folder")
                                ? QColor(QStringLiteral("#2457A6")) // Theme.primary (light)
                                : QColor(QStringLiteral("#2457A6")); // "message" (defaut) : Theme.accent
        painter.setBrush(color);
        painter.setPen(Qt::NoPen);
        painter.drawEllipse(2, 2, 60, 60);

        if (!iconFontFamily.isEmpty()) {
            QFont font(iconFontFamily, 28);
            painter.setFont(font);
            painter.setPen(Qt::white);
            const QString glyph = category == QStringLiteral("call")
                ? QStringLiteral("\uf095")              // telephone
                : category == QStringLiteral("transfer")
                    ? QStringLiteral("\uf019")           // telechargement
                    : category == QStringLiteral("connection")
                        ? QStringLiteral("\uf234")       // utilisateur connecte
                        : category == QStringLiteral("disconnection")
                            ? QStringLiteral("\uf235")   // utilisateur deconnecte
                            : category == QStringLiteral("group")
                                ? QStringLiteral("\uf0c0")   // groupe d'utilisateurs
                                : category == QStringLiteral("folder")
                                    ? QStringLiteral("\uf07b")   // dossier
                                    : QStringLiteral("\uf0e0");  // enveloppe (message)
            painter.drawText(pixmap.rect(), Qt::AlignCenter, glyph);
        }
        return QIcon(pixmap);
    };
    QMenu trayMenu;
    QAction *showAction = trayMenu.addAction(QObject::tr("Afficher LocaLink"));
    QAction *quitAction = trayMenu.addAction(QObject::tr("Quitter"));
    trayIcon.setContextMenu(&trayMenu);
    trayIcon.setToolTip(QObject::tr("LocaLink"));

    const bool trayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
    window->setProperty("backgroundModeAvailable", trayAvailable);

    QObject::connect(showAction, &QAction::triggered, window, [window]() {
        window->show();
        window->raise();
        window->requestActivate();
    });
    QObject::connect(&trayIcon, &QSystemTrayIcon::activated, window,
                     [window](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger ||
            reason == QSystemTrayIcon::DoubleClick) {
            window->show();
            window->raise();
            window->requestActivate();
        }
    });
    QObject::connect(&trayIcon, &QSystemTrayIcon::messageClicked, window, [window]() {
        window->show();
        window->raise();
        window->requestActivate();
    });
    QObject::connect(application.notificationManager(),
                     &core::NotificationManager::notificationRequested,
                     window,
                     [&trayIcon, window, notificationIcon, applicationIcon](
                         const QString &title, const QString &message,
                         const QString &category, qint64) {
        if (!window->isVisible()) {
            const QIcon icon = notificationIcon(category);
            trayIcon.setIcon(icon);
            // Surcharge QIcon (et non l'enum QSystemTrayIcon::Information) :
            // c'est cette version qui transmet reellement notre icone dessinee
            // au toast Windows. Avec l'enum, Windows affiche systematiquement
            // son icone "info" generique et ignore l'icone du tray, ce qui
            // rendait le correctif precedent invisible malgre une recompilation.
            trayIcon.showMessage(title, message, icon, 5000);
            QTimer::singleShot(750, window, [&trayIcon, applicationIcon]() {
                trayIcon.setIcon(applicationIcon);
            });
        }
        Q_UNUSED(category);
    });
    QObject::connect(application.voiceService(), &network::VoiceService::incomingCall,
                     window, [&trayIcon, window, notificationIcon, applicationIcon, &application](
                         const QHostAddress &callerAddress) {
        if (!window->isVisible()) {
            const QIcon icon = notificationIcon(QStringLiteral("call"));
            trayIcon.setIcon(icon);
            // Meme resolution que CallView.qml (PeersModel::nameForAddress) :
            // sans ca, la notification en arriere-plan n'affichait que
            // l'adresse IP de l'appelant au lieu de son nom, contrairement
            // au premier plan ou CallView resout deja ce nom.
            const QString resolvedName = application.peersModel()
                ? application.peersModel()->nameForAddress(callerAddress.toString())
                : QString();
            const QString callerLabel = resolvedName.isEmpty() ? callerAddress.toString() : resolvedName;
            trayIcon.showMessage(QObject::tr("Appel entrant"),
                                 QObject::tr("Appel de %1").arg(callerLabel),
                                 icon, 10000);
            QTimer::singleShot(750, window, [&trayIcon, applicationIcon]() {
                trayIcon.setIcon(applicationIcon);
            });
        }
    });
    QObject::connect(quitAction, &QAction::triggered, &app, [window, &app]() {
        window->setProperty("allowApplicationQuit", true);
        app.quit();
    });

    if (trayAvailable) {
        trayIcon.show();
    } else {
        qWarning() << "System tray indisponible : l'application restera active en arriere-plan";
    }

    return app.exec();
}
