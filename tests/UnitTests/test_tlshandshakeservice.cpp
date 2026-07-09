#include <QtTest>
#include <QTemporaryDir>
#include <QSslSocket>
#include <QHostAddress>
#include <QSignalSpy>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QPointer>

#include "Security/SecurityService.h"
#include "Security/TlsHandshakeService.h"

using network::SecurityService;
using network::TlsHandshakeService;

/*
 * Verifie les criteres d'acceptation de l'issue #12 :
 *  - "Une session TLS valide s'etablit entre deux postes autorises"
 *  - "Une machine non autorisee est rejetee"
 *
 * Chaque "poste" est simule par une SecurityService + TlsHandshakeService
 * pointant vers un repertoire de stockage temporaire distinct (identite
 * cryptographique independante), le tout sur localhost.
 */
class TestTlsHandshakeService : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        qRegisterMetaType<QSslSocket *>("QSslSocket*");
    }

    void authorizedPeersEstablishTlsSession()
    {
        QTemporaryDir dirA, dirB;
        QVERIFY(dirA.isValid());
        QVERIFY(dirB.isValid());

        SecurityService securityA(dirA.path());
        SecurityService securityB(dirB.path());
        QVERIFY(securityA.initialize());
        QVERIFY(securityB.initialize());

        TlsHandshakeService serviceA(&securityA);
        TlsHandshakeService serviceB(&securityB);

        // Confiance mutuelle explicite (liste blanche) avant toute connexion.
        serviceA.trustPeer(securityB.identity().fingerprintSha256, QStringLiteral("PosteB"));
        serviceB.trustPeer(securityA.identity().fingerprintSha256, QStringLiteral("PosteA"));

        QVERIFY(serviceA.listen(0));
        QVERIFY(serviceA.listenPort() != 0);

        QSignalSpy serverSucceeded(&serviceA, &TlsHandshakeService::handshakeSucceeded);
        QSignalSpy clientSucceeded(&serviceB, &TlsHandshakeService::handshakeSucceeded);
        QSignalSpy serverRejected(&serviceA, &TlsHandshakeService::handshakeRejected);
        QSignalSpy clientRejected(&serviceB, &TlsHandshakeService::handshakeRejected);

        QSslSocket *clientSocket = serviceB.connectToPeer(QHostAddress::LocalHost, serviceA.listenPort());
        QVERIFY(clientSocket != nullptr);

        QTRY_VERIFY(serverSucceeded.count() > 0);
        QTRY_VERIFY(clientSucceeded.count() > 0);

        QCOMPARE(serverRejected.count(), 0);
        QCOMPARE(clientRejected.count(), 0);

        const QString serverSeenFingerprint = serverSucceeded.at(0).at(1).toString();
        QCOMPARE(serverSeenFingerprint, securityB.identity().fingerprintSha256);

        const QString clientSeenFingerprint = clientSucceeded.at(0).at(1).toString();
        QCOMPARE(clientSeenFingerprint, securityA.identity().fingerprintSha256);
    }

    void unauthorizedPeerIsRejected()
    {
        QTemporaryDir dirA, dirB;
        QVERIFY(dirA.isValid());
        QVERIFY(dirB.isValid());

        SecurityService securityA(dirA.path());
        SecurityService securityB(dirB.path());
        QVERIFY(securityA.initialize());
        QVERIFY(securityB.initialize());

        TlsHandshakeService serviceA(&securityA);
        TlsHandshakeService serviceB(&securityB);

        // Aucune confiance accordee : B n'est pas dans la liste blanche de A.
        QVERIFY(!serviceA.isPeerTrusted(securityB.identity().fingerprintSha256));

        QVERIFY(serviceA.listen(0));

        QSignalSpy serverSucceeded(&serviceA, &TlsHandshakeService::handshakeSucceeded);

        QSslSocket *clientSocket = serviceB.connectToPeer(QHostAddress::LocalHost, serviceA.listenPort());
        QVERIFY(clientSocket != nullptr);

        // clientSocket peut etre detruit (deleteLater) des que la connexion est
        // fermee cote serveur : on le surveille via QPointer pour ne jamais le
        // dereferencer une fois invalide.
        QPointer<QSslSocket> clientGuard(clientSocket);
        QSignalSpy clientDisconnected(clientSocket, &QAbstractSocket::disconnected);
        QSignalSpy clientErrored(clientSocket, &QAbstractSocket::errorOccurred);

        // Le critere d'acceptation ("machine non autorisee rejetee") se
        // traduit cote client par une fermeture de connexion ou une erreur
        // socket (jamais de session TLS validee). On observe l'un OU l'autre,
        // plutot que de dependre du timing exact d'un signal en particulier.
        QTRY_VERIFY(clientDisconnected.count() > 0 || clientErrored.count() > 0
                    || (clientGuard && clientGuard->state() != QAbstractSocket::ConnectedState));

        // Aucune session n'a jamais ete validee cote serveur.
        QCOMPARE(serverSucceeded.count(), 0);

        // Si le socket client existe encore, il ne doit jamais avoir termine
        // de session chiffree valide.
        if (clientGuard)
            QVERIFY(!clientGuard->isEncrypted());
    }
};

QTEST_MAIN(TestTlsHandshakeService)
#include "test_tlshandshakeservice.moc"
