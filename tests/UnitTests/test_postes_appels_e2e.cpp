// Essai de bout en bout « plusieurs postes » : trois instances completes
// d'Application dans le meme processus (un serveur, deux clients), chacune avec
// sa base, son identite TLS et ses ports. Passe par la vraie messagerie TLS
// (identification, liste "authorized_peers"), le vrai PermissionManager et la
// vraie signalisation d'appel :
//   - le serveur appelle un client autorise (correctif 1263ee2) ;
//   - un client appelle l'autre client autorise par le serveur, puis lui
//     envoie un fichier directement (a592b67) ;
//   - apres revocation par le serveur, l'appel du client revoque est refuse.
// Seul raccourci : la connexion client -> serveur est ouverte directement
// (connectToHost) au lieu de passer par la decouverte et l'election.
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QSignalSpy>
#include <QTemporaryDir>

#include "Application.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "Voice/VoiceService.h"
#include "Transfer/TransferService.h"
#include "models/AuthorizedMachine.h"

class TestPostesAppelsE2E : public QObject
{
    Q_OBJECT

    struct Poste {
        std::unique_ptr<Application> app;
        quint16 port = 0;          // messagerie ; transferts = +1, appels = +2
        QString fingerprint;
        quint16 voicePort() const { return static_cast<quint16>(port + 2); }
    };

    QTemporaryDir m_dir;
    quint16 m_base = 0;
    int m_count = 0;

    Poste start(const QString &name, const QString &role)
    {
        Poste p;
        p.port = static_cast<quint16>(m_base + 10 * m_count++);
        p.app = std::make_unique<Application>();
        // Ports de decouverte et d'election propres : aucune interference avec
        // un vrai LocaLink du reseau ni entre les instances du test.
        p.app->setDiscoveryPort(static_cast<quint16>(p.port + 5));
        p.app->initialize(p.port, m_dir.filePath(name + QStringLiteral(".db")), role, -1,
                          static_cast<quint16>(p.port + 6));
        // Un client sans serveur visible sur son port d'election se promouvrait
        // serveur de secours au bout du delai : on l'en empeche pendant l'essai.
        p.app->electionService()->setHeartbeatTimeoutMs(10 * 60 * 1000);
        p.fingerprint = p.app->securityService()->identity().fingerprintSha256.toLower();
        return p;
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_base = static_cast<quint16>(30000 + QRandomGenerator::global()->bounded(2000) * 10);
    }

    void serverAndClientsCallEachOther()
    {
        Poste server = start(QStringLiteral("serveur"), QStringLiteral("SERVER"));
        Poste a = start(QStringLiteral("client-a"), QStringLiteral("CLIENT"));
        Poste b = start(QStringLiteral("client-b"), QStringLiteral("CLIENT"));
        QVERIFY(!server.fingerprint.isEmpty() && !a.fingerprint.isEmpty() && !b.fingerprint.isEmpty());
        QVERIFY(a.fingerprint != b.fingerprint);

        // L'administrateur du serveur autorise les deux clients ; chaque client a
        // approuve le certificat du serveur (ce que fait l'ecran de connexion).
        const auto admin = server.app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        core::PermissionManager *serverPm = server.app->permissionManager();
        QVERIFY(serverPm->authorizeMachineByCertificate(a.fingerprint, QStringLiteral("machine-a"), QStringLiteral("CLIENT-A"),
                                                        QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
        QVERIFY(serverPm->authorizeMachineByCertificate(b.fingerprint, QStringLiteral("machine-b"), QStringLiteral("CLIENT-B"),
                                                        QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
        for (Poste *c : {&a, &b})
            QVERIFY(c->app->permissionManager()->approveServerCertificate(server.fingerprint, QStringLiteral("127.0.0.1")));

        // Connexion des clients : identification, puis envoi de la liste par le serveur.
        QVERIFY(a.app->messagingService()->connectToHost(QHostAddress::LocalHost, server.port));
        QVERIFY(b.app->messagingService()->connectToHost(QHostAddress::LocalHost, server.port));
        QTRY_VERIFY_WITH_TIMEOUT(a.app->permissionManager()->isAuthorizedByServer(b.fingerprint), 15000);
        QTRY_VERIFY_WITH_TIMEOUT(b.app->permissionManager()->isAuthorizedByServer(a.fingerprint), 15000);
        // Jamais ecrite dans la politique d'admission locale du client.
        QVERIFY(!a.app->permissionManager()->isMachineAuthorizedByCertificate(b.fingerprint));

        // 1. Le serveur appelle le client A.
        {
            QSignalSpy ringing(a.app->voiceService(), &network::VoiceService::incomingCall);
            QVERIFY(server.app->voiceService()->call(QHostAddress::LocalHost, a.voicePort()));
            QTRY_COMPARE_WITH_TIMEOUT(ringing.count(), 1, 15000);
            server.app->voiceService()->hangUp();
            a.app->voiceService()->hangUp();
            QTest::qWait(500);
        }

        // 2. Le client A appelle le client B.
        {
            QSignalSpy ringing(b.app->voiceService(), &network::VoiceService::incomingCall);
            QVERIFY(a.app->voiceService()->call(QHostAddress::LocalHost, b.voicePort()));
            QTRY_COMPARE_WITH_TIMEOUT(ringing.count(), 1, 15000);
            a.app->voiceService()->hangUp();
            b.app->voiceService()->hangUp();
            QTest::qWait(500);
        }

        // 2 bis. Le client A envoie un fichier directement au client B.
        {
            const QString receiveDir = m_dir.filePath(QStringLiteral("recus-b"));
            QVERIFY(QDir().mkpath(receiveDir));
            b.app->transferService()->setReceiveDirectory(receiveDir);
            const QString source = m_dir.filePath(QStringLiteral("rapport.txt"));
            QFile file(source);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("Rapport envoye de A a B");
            file.close();

            QSignalSpy received(b.app->transferService(), &network::TransferService::transferCompleted);
            QSignalSpy failed(b.app->transferService(), &network::TransferService::transferFailed);
            QVERIFY(a.app->transferService()->sendFile(QHostAddress::LocalHost, static_cast<quint16>(b.port + 1),
                                                       source, QString(), QString()));
            QTRY_COMPARE_WITH_TIMEOUT(received.count(), 1, 15000);
            QCOMPARE(failed.count(), 0);
            QFile got(received.first().at(1).toString());
            QVERIFY(got.open(QIODevice::ReadOnly));
            QCOMPARE(got.readAll(), QByteArray("Rapport envoye de A a B"));
        }

        // 3. Le serveur revoque B : A recoit la nouvelle liste et refuse l'appel de B.
        QVERIFY(serverPm->revokeMachineByCertificate(b.fingerprint, admin->id(), QStringLiteral("essai")));
        QTRY_VERIFY_WITH_TIMEOUT(!a.app->permissionManager()->isAuthorizedByServer(b.fingerprint), 15000);
        {
            QSignalSpy ringing(a.app->voiceService(), &network::VoiceService::incomingCall);
            b.app->voiceService()->call(QHostAddress::LocalHost, a.voicePort());
            QTest::qWait(4000);
            QCOMPARE(ringing.count(), 0);
            // Refus pour defaut d'autorisation (et non session occupee) : A note B
            // comme machine en attente, ce qu'il ne fait que dans ce cas.
            const auto noted = a.app->permissionManager()->findMachineByCertificateFingerprint(b.fingerprint);
            QVERIFY(noted.has_value());
            QCOMPARE(noted->status(), models::MachineStatus::Pending);
            b.app->voiceService()->hangUp();
        }
    }
};

QTEST_MAIN(TestPostesAppelsE2E)
#include "test_postes_appels_e2e.moc"
