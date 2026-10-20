// Lot 2 securite : un client qui demande le journal de synchronisation ne recoit que ce qui
// concerne l'utilisateur identifie sur sa connexion (plus les messages prives des autres).
#include <QtTest>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include "Sync/SyncService.h"

using network::syncEntriesVisibleTo;

namespace {
models::SyncLogEntry entry(const QString &table, const QString &record, const QJsonObject &payload,
                           const QString &operation = models::SyncOperation::Insert)
{
    models::SyncLogEntry e;
    e.setEntryUuid(table + QLatin1Char('-') + record);
    e.setTableName(table);
    e.setRecordUuid(record);
    e.setOperation(operation);
    e.setPayloadJson(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
    return e;
}

QStringList records(const std::vector<models::SyncLogEntry> &entries)
{
    QStringList out;
    for (const auto &e : entries)
        out << e.tableName() + QLatin1Char(':') + e.recordUuid();
    return out;
}

std::vector<models::SyncLogEntry> journal()
{
    return {
        entry(QStringLiteral("Users"), QStringLiteral("alice"), {{QStringLiteral("name"), QStringLiteral("alice")}}),
        entry(QStringLiteral("Users"), QStringLiteral("bob"), {{QStringLiteral("name"), QStringLiteral("bob")}}),
        // Conversation directe alice <-> bob
        entry(QStringLiteral("Messages"), QStringLiteral("m-ab"), {{QStringLiteral("senderUuid"), QStringLiteral("alice")},
            {QStringLiteral("participant1Uuid"), QStringLiteral("alice")}, {QStringLiteral("participant2Uuid"), QStringLiteral("bob")},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-ab")}}),
        // Conversation directe bob <-> chloe (alice n'y est pas)
        entry(QStringLiteral("Messages"), QStringLiteral("m-bc"), {{QStringLiteral("senderUuid"), QStringLiteral("bob")},
            {QStringLiteral("participant1Uuid"), QStringLiteral("bob")}, {QStringLiteral("participant2Uuid"), QStringLiteral("chloe")},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-bc")}}),
        // Groupe "projet" sans alice, puis alice ajoutee
        entry(QStringLiteral("Groups"), QStringLiteral("g-projet"), {{QStringLiteral("ownerUuid"), QStringLiteral("bob")},
            {QStringLiteral("memberUuids"), QJsonArray{QStringLiteral("bob"), QStringLiteral("chloe")}},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-projet")}}),
        entry(QStringLiteral("GroupMembers"), QStringLiteral("gm-1"), {{QStringLiteral("groupUuid"), QStringLiteral("g-projet")},
            {QStringLiteral("memberUuid"), QStringLiteral("alice")}}),
        entry(QStringLiteral("Messages"), QStringLiteral("m-projet"), {{QStringLiteral("senderUuid"), QStringLiteral("chloe")},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-projet")}}),
        // Groupe "rh" sans alice
        entry(QStringLiteral("Groups"), QStringLiteral("g-rh"), {{QStringLiteral("ownerUuid"), QStringLiteral("chloe")},
            {QStringLiteral("memberUuids"), QJsonArray{QStringLiteral("chloe")}},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-rh")}}),
        entry(QStringLiteral("Messages"), QStringLiteral("m-rh"), {{QStringLiteral("senderUuid"), QStringLiteral("chloe")},
            {QStringLiteral("conversationUuid"), QStringLiteral("conv-rh")}}),
        // Type inconnu : jamais transmis a un client
        entry(QStringLiteral("Secrets"), QStringLiteral("s-1"), {}),
    };
}
} // namespace

class TestSyncVisibility : public QObject
{
    Q_OBJECT

private slots:
    void clientReceivesOnlyItsOwnConversationsAndGroups()
    {
        const QStringList visible = records(syncEntriesVisibleTo(journal(), QStringLiteral("alice")));
        QCOMPARE(visible, QStringList({QStringLiteral("Users:alice"), QStringLiteral("Users:bob"),
                                       QStringLiteral("Messages:m-ab"), QStringLiteral("Groups:g-projet"),
                                       QStringLiteral("GroupMembers:gm-1"), QStringLiteral("Messages:m-projet")}));
    }

    void otherUserDoesNotSeeAlicesDirectConversation()
    {
        const QStringList visible = records(syncEntriesVisibleTo(journal(), QStringLiteral("chloe")));
        QVERIFY(!visible.contains(QStringLiteral("Messages:m-ab")));
        QVERIFY(visible.contains(QStringLiteral("Messages:m-bc")));
        QVERIFY(visible.contains(QStringLiteral("Messages:m-rh")));
        QVERIFY(!visible.contains(QStringLiteral("Secrets:s-1")));
    }

    void machineWithoutLoggedUserReceivesAccountsOnly()
    {
        const QStringList visible = records(syncEntriesVisibleTo(journal(), QString()));
        QCOMPARE(visible, QStringList({QStringLiteral("Users:alice"), QStringLiteral("Users:bob")}));
    }
};

QTEST_GUILESS_MAIN(TestSyncVisibility)
#include "test_syncvisibility.moc"
