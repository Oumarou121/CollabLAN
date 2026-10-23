// Appels et transferts directs entre clients : le serveur envoie a ses clients la
// liste des machines autorisees ("authorized_peers"). Le client ne l'accepte que
// du serveur (relay=false, connexion TLS vers le serveur approuve) ; envoyee par
// un client au serveur, elle servirait a faire accepter n'importe quel certificat.
#include <QtTest>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

#include "Application.h"
#include "PermissionManager.h"

class TestAuthorizedPeers : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    std::unique_ptr<Application> m_app;

    static quint16 nextPort()
    {
        static quint16 port = 24800;
        return port += 2;
    }

    void startApplication(const QString &role = QStringLiteral("CLIENT"))
    {
        m_app = std::make_unique<Application>();
        // Jamais le port de decouverte reel (45454) : les vrais postes du reseau
        // verraient sinon un poste fantome a chaque essai.
        m_app->setDiscoveryPort(nextPort());
        static int run = 0;
        m_app->initialize(nextPort(), m_dir.filePath(QStringLiteral("pairs-%1.db").arg(++run)),
                          role, -1, nextPort());
        QVERIFY(m_app->permissionManager());
    }

    void deliver(const QStringList &fingerprints, bool relay)
    {
        QJsonArray list;
        for (const QString &f : fingerprints)
            list.append(f);
        const QJsonObject payload{{QStringLiteral("type"), QStringLiteral("authorized_peers")},
                                  {QStringLiteral("fingerprints"), list}};
        QMetaObject::invokeMethod(m_app.get(), "handleIncomingPayload", Qt::DirectConnection,
                                  Q_ARG(QString, QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact))),
                                  Q_ARG(bool, relay));
    }

private slots:
    void cleanup() { m_app.reset(); }

    void listFromServerIsApplied()
    {
        QVERIFY(m_dir.isValid());
        startApplication();
        core::PermissionManager *pm = m_app->permissionManager();
        QVERIFY(!pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("abc123")));

        deliver({QStringLiteral("ABC123"), QStringLiteral("def456")}, /*relay=*/false);
        QVERIFY(pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("abc123")));
        QVERIFY(pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("def456")));

        // Revocation cote serveur : la liste suivante remplace la precedente.
        deliver({QStringLiteral("def456")}, false);
        QVERIFY(!pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("abc123")));
        QVERIFY(pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("def456")));
    }

    void listFromClientIsRefused()
    {
        startApplication();
        core::PermissionManager *pm = m_app->permissionManager();
        deliver({QStringLiteral("def456")}, false);

        // Recue par un serveur depuis un de ses clients : ignoree, rien ne change.
        deliver({QStringLiteral("evil999")}, /*relay=*/true);
        QVERIFY(!pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("evil999")));
        QVERIFY(pm->isMachineAuthorizedOrTrustedServer(QStringLiteral("def456")));
    }

    // Le serveur officiel garde sa propre liste comme seule reference, meme
    // connecte en client a un serveur de secours pendant la reconciliation.
    void officialServerIgnoresReceivedList()
    {
        startApplication(QStringLiteral("SERVER"));
        deliver({QStringLiteral("abc123")}, /*relay=*/false);
        QVERIFY(!m_app->permissionManager()->isMachineAuthorizedOrTrustedServer(QStringLiteral("abc123")));
    }
};

QTEST_MAIN(TestAuthorizedPeers)
#include "test_authorizedpeers.moc"
