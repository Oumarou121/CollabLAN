#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/Repositories/AuthorizedMachineRepository.h"
#include "models/AuthorizedMachine.h"
#include "DatabaseManager.h"

using database::AuthorizedMachineRepository;

// Couvre le plan "Machines autorisees avec etat pending/authorized/revoked" :
// registerPendingByCertificate() n'autorise jamais automatiquement,
// hasAnyAuthorizedMachine() sert de garde au bootstrap admin, et
// setAuthorizationByCertificate() est la seule voie vers authorized/revoked.
class TestAuthorizedMachineRepository : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<AuthorizedMachineRepository> m_repository;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-authorizedmachinerepository-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        QVERIFY(opened);

        // La table AuthorizedMachines (avec la colonne `status`, migration 031)
        // est creee par les migrations reelles executees dans open().
        // added_by reference Users(id) et les cles etrangeres sont actives : sans ces comptes,
        // toute autorisation echoue silencieusement (les ids 1 et 42 sont ceux utilises ci-dessous
        // comme "administrateur ayant autorise la machine").
        QSqlQuery seed(m_dbManager->database());
        QVERIFY(seed.exec(QStringLiteral(
            "INSERT INTO Users (id, name, password_hash, password_salt, uuid) VALUES "
            "(1, 'admin-test', 'h', 's', 'uuid-admin-test'), "
            "(42, 'autre-admin', 'h', 's', 'uuid-autre-admin')")));

        m_repository = std::make_unique<AuthorizedMachineRepository>(m_dbManager->database());
    }

private slots:
    void cleanup()
    {
        m_repository.reset();
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_dbManager.reset();
        m_dir.reset();
    }

    void hasAnyAuthorizedMachine_falseOnEmptyDatabase()
    {
        freshDatabase();
        QVERIFY(!m_repository->hasAnyAuthorizedMachine());
    }

    void registerPendingByCertificate_createsUnknownMachineAsPending()
    {
        freshDatabase();

        const bool ok = m_repository->registerPendingByCertificate(
            QStringLiteral("AA:BB:CC"), QStringLiteral("192.168.1.10"),
            QStringLiteral("laptop-1"), QString());
        QVERIFY(ok);

        const auto machine = m_repository->findByCertificateFingerprint(QStringLiteral("aa:bb:cc"));
        QVERIFY(machine.has_value());
        QCOMPARE(machine->status(), models::MachineStatus::Pending);
        QVERIFY(!machine->isAuthorized());

        // Une machine pending ne compte jamais comme "authorized".
        QVERIFY(!m_repository->hasAnyAuthorizedMachine());
    }

    void registerPendingByCertificate_neverDowngradesAnAlreadyAuthorizedMachine()
    {
        freshDatabase();

        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-1"), QStringLiteral("10.0.0.1"), QStringLiteral("srv"), QString()));
        QVERIFY(m_repository->setAuthorizationByCertificate(QStringLiteral("fp-1"), true, 1,
            QStringLiteral("Autorise par admin")));

        // Un nouveau contact avec la meme empreinte (ex. reconnexion) ne doit
        // jamais redegrader une machine deja authorized vers pending.
        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-1"), QStringLiteral("10.0.0.2"), QStringLiteral("srv"), QString()));

        const auto machine = m_repository->findByCertificateFingerprint(QStringLiteral("fp-1"));
        QVERIFY(machine.has_value());
        QCOMPARE(machine->status(), models::MachineStatus::Authorized);
        // La derniere IP vue est tout de meme rafraichie.
        QCOMPARE(machine->lastIpAddress(), QStringLiteral("10.0.0.2"));
    }

    void setAuthorizationByCertificate_authorizesAndRevokes()
    {
        freshDatabase();

        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-2"), QStringLiteral("10.0.0.5"), QStringLiteral("pc"), QString()));

        QVERIFY(m_repository->setAuthorizationByCertificate(QStringLiteral("fp-2"), true, 42,
            QStringLiteral("Autorise par admin")));
        {
            const auto machine = m_repository->findByCertificateFingerprint(QStringLiteral("fp-2"));
            QVERIFY(machine.has_value());
            QCOMPARE(machine->status(), models::MachineStatus::Authorized);
            QVERIFY(machine->isAuthorized());
            QVERIFY(m_repository->hasAnyAuthorizedMachine());
        }

        QVERIFY(m_repository->setAuthorizationByCertificate(QStringLiteral("fp-2"), false, 42,
            QStringLiteral("Revoque par admin")));
        {
            const auto machine = m_repository->findByCertificateFingerprint(QStringLiteral("fp-2"));
            QVERIFY(machine.has_value());
            QCOMPARE(machine->status(), models::MachineStatus::Revoked);
            QVERIFY(!machine->isAuthorized());
            QVERIFY(!m_repository->hasAnyAuthorizedMachine());
        }
    }

    void setAuthorizationByCertificate_failsForUnknownFingerprint()
    {
        freshDatabase();
        QVERIFY(!m_repository->setAuthorizationByCertificate(
            QStringLiteral("does-not-exist"), true, 1, QString()));
    }

    void findAuthorizedAndFindRevoked_filterByStatus()
    {
        freshDatabase();

        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-pending"), QStringLiteral("10.0.0.1"), QString(), QString()));
        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-authorized"), QStringLiteral("10.0.0.2"), QString(), QString()));
        QVERIFY(m_repository->setAuthorizationByCertificate(
            QStringLiteral("fp-authorized"), true, 1, QString()));
        QVERIFY(m_repository->registerPendingByCertificate(
            QStringLiteral("fp-revoked"), QStringLiteral("10.0.0.3"), QString(), QString()));
        QVERIFY(m_repository->setAuthorizationByCertificate(
            QStringLiteral("fp-revoked"), false, 1, QString()));

        const auto authorized = m_repository->findAuthorized();
        QCOMPARE(authorized.size(), size_t(1));
        QCOMPARE(authorized[0].certificateFingerprint(), QStringLiteral("fp-authorized"));

        const auto revoked = m_repository->findRevoked();
        QCOMPARE(revoked.size(), size_t(1));
        QCOMPARE(revoked[0].certificateFingerprint(), QStringLiteral("fp-revoked"));

        // findAll() doit retourner les trois, quel que soit leur statut.
        QCOMPARE(m_repository->findAll().size(), size_t(3));
    }
};

QTEST_MAIN(TestAuthorizedMachineRepository)
#include "test_authorizedmachinerepository.moc"
