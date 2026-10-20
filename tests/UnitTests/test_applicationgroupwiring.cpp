// Lot 3 : les messages de groupe en temps reel (group_created, member_added, member_removed)
// n'etaient JAMAIS traites -- leur code se trouvait apres un "return" inconditionnel dans
// Application::handleIncomingPayload(). Les autres postes n'apprenaient donc l'existence d'un
// groupe ou un changement de membre qu'a la prochaine reconciliation complete.
#include <QtTest>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlQuery>
#include <QTemporaryDir>

#include "Application.h"
#include "UserManager.h"
#include "database/DatabaseManager.h"
#include "database/Repositories/GroupRepository.h"
#include "models/User.h"

class TestApplicationGroupWiring : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    std::unique_ptr<Application> m_app;

    static quint16 nextPort()
    {
        static quint16 port = 24700;
        return port += 2;
    }

    /// Poste demarre en SERVER avec une base vierge, et deux comptes locaux.
    void startApplication()
    {
        m_app = std::make_unique<Application>();
        static int run = 0;
        m_app->initialize(nextPort(), m_dir.filePath(QStringLiteral("groupes-%1.db").arg(++run)),
                          QStringLiteral("SERVER"), -1, nextPort());
        QVERIFY(m_app->userManager());
        QVERIFY(m_app->userManager()->createUser(QStringLiteral("alice"), QStringLiteral("motdepasse-alice")).has_value());
        QVERIFY(m_app->userManager()->createUser(QStringLiteral("bob"), QStringLiteral("motdepasse-bob")).has_value());
    }

    QString uuidOf(const QString &name) const
    {
        for (const auto &user : m_app->userManager()->allUsers())
            if (user.name() == name)
                return user.uuid();
        return QString();
    }

    void deliver(const QJsonObject &payload)
    {
        // relay=false : ce poste recoit le message en tant que client du serveur actif.
        QMetaObject::invokeMethod(m_app.get(), "handleIncomingPayload", Qt::DirectConnection,
                                  Q_ARG(QString, QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact))),
                                  Q_ARG(bool, false));
    }

    int memberCount(const QString &groupUuid) const
    {
        QSqlQuery query(m_app->databaseManager()->database());
        query.prepare(QStringLiteral(
            "SELECT COUNT(*) FROM GroupMembers gm JOIN Groups g ON g.id = gm.group_id WHERE g.uuid = :uuid"));
        query.bindValue(QStringLiteral(":uuid"), groupUuid);
        return (query.exec() && query.next()) ? query.value(0).toInt() : -1;
    }

private slots:
    void cleanup() { m_app.reset(); }

    void groupCreatedByAnotherPeerIsAppliedLocally()
    {
        QVERIFY(m_dir.isValid());
        startApplication();
        const QString alice = uuidOf(QStringLiteral("alice"));
        const QString bob = uuidOf(QStringLiteral("bob"));
        QVERIFY(!alice.isEmpty() && !bob.isEmpty());

        const QString groupUuid = QStringLiteral("uuid-groupe-projet");
        deliver({{QStringLiteral("type"), QStringLiteral("group_created")},
                 {QStringLiteral("groupUuid"), groupUuid},
                 {QStringLiteral("name"), QStringLiteral("Projet")},
                 {QStringLiteral("ownerUuid"), alice},
                 {QStringLiteral("conversationUuid"), QStringLiteral("uuid-conv-projet")},
                 {QStringLiteral("memberUuids"), QJsonArray{alice, bob}}});

        database::GroupRepository groups(m_app->databaseManager());
        const auto stored = groups.findByUuid(groupUuid);
        QVERIFY2(stored.has_value(), "le groupe annonce par un pair doit exister localement");
        QCOMPARE(stored->name(), QStringLiteral("Projet"));
        QCOMPARE(memberCount(groupUuid), 2);
    }

    void memberAddedThenRemovedIsAppliedLocally()
    {
        QVERIFY(m_dir.isValid());
        startApplication();
        const QString alice = uuidOf(QStringLiteral("alice"));
        const QString bob = uuidOf(QStringLiteral("bob"));

        const QString groupUuid = QStringLiteral("uuid-groupe-rh");
        deliver({{QStringLiteral("type"), QStringLiteral("group_created")},
                 {QStringLiteral("groupUuid"), groupUuid},
                 {QStringLiteral("name"), QStringLiteral("RH")},
                 {QStringLiteral("ownerUuid"), alice},
                 {QStringLiteral("conversationUuid"), QStringLiteral("uuid-conv-rh")},
                 {QStringLiteral("memberUuids"), QJsonArray{alice}}});
        QCOMPARE(memberCount(groupUuid), 1);

        deliver({{QStringLiteral("type"), QStringLiteral("member_added")},
                 {QStringLiteral("groupUuid"), groupUuid},
                 {QStringLiteral("memberUuid"), bob}});
        QCOMPARE(memberCount(groupUuid), 2);

        deliver({{QStringLiteral("type"), QStringLiteral("member_removed")},
                 {QStringLiteral("groupUuid"), groupUuid},
                 {QStringLiteral("memberUuid"), bob}});
        QCOMPARE(memberCount(groupUuid), 1);
    }
};

QTEST_MAIN(TestApplicationGroupWiring)
#include "test_applicationgroupwiring.moc"
