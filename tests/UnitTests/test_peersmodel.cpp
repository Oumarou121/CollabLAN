#include <QtTest>
#include <QSignalSpy>
#include <QAbstractItemModel>

#include "Discovery/DiscoveryService.h"
#include "Discovery/PeersModel.h"

using network::DiscoveryService;
using network::DiscoveredPeer;
using network::PeersModel;

/*
 * Verifie le critere d'acceptation de l'issue #17 :
 * "La liste se met a jour sans rafraichissement manuel quand un poste
 * apparait/disparait", en exercant PeersModel (le modele QML branche sur
 * UsersView.qml) directement contre deux vraies instances de
 * DiscoveryService communiquant en UDP.
 */
class TestPeersModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        qRegisterMetaType<network::DiscoveredPeer>("network::DiscoveredPeer");
    }

    void modelReflectsPeerDiscoveryAndLossInRealTime()
    {
        DiscoveryService serviceA;
        DiscoveryService serviceB;

        const quint16 testPort = 45998;
        serviceA.setPort(testPort);
        serviceB.setPort(testPort);

        serviceA.setAnnounceIntervalMs(300);
        serviceB.setAnnounceIntervalMs(300);
        serviceA.setPeerTimeoutMs(1500);

        serviceA.setLocalName("MachineA");
        serviceB.setLocalName("MachineB");

        PeersModel model(&serviceA);
        QCOMPARE(model.rowCount(), 0);
        QCOMPARE(model.count(), 0);

        QSignalSpy rowsInserted(&model, &QAbstractItemModel::rowsInserted);
        QSignalSpy countChanged(&model, &PeersModel::countChanged);

        QVERIFY(serviceA.start());
        QVERIFY(serviceB.start());

        // Le modele doit se peupler tout seul, sans appel manuel, des que
        // DiscoveryService detecte le poste distant.
        QVERIFY(rowsInserted.wait(5000));
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.count(), 1);
        QVERIFY(countChanged.count() >= 1);

        const QModelIndex idx = model.index(0, 0);
        QCOMPARE(model.data(idx, PeersModel::NameRole).toString(), QStringLiteral("MachineB"));
        QCOMPARE(model.data(idx, PeersModel::StatusRole).toString(), QStringLiteral("online"));

        QSignalSpy rowsRemoved(&model, &QAbstractItemModel::rowsRemoved);

        serviceB.stop();

        // Le modele doit egalement retirer la ligne automatiquement quand
        // DiscoveryService emet peerLost, sans intervention de l'UI.
        QVERIFY(rowsRemoved.wait(5000));
        QCOMPARE(model.rowCount(), 0);
        QCOMPARE(model.count(), 0);

        serviceA.stop();
    }
};

QTEST_MAIN(TestPeersModel)
#include "test_peersmodel.moc"
