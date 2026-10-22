#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include "MessagingManager.h"
#include "DatabaseManager.h"
#include "UserManager.h"

using core::MessagingManager;
using core::MessagingManagerError;

class TestMessagingManager : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<core::UserManager> m_userManager;
    std::unique_ptr<MessagingManager> m_messagingManager;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-messagingmanager-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        // Creer les tables de base pour les tests
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery query(db);
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS Conversations ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "type TEXT NOT NULL, "
            "name TEXT, "
            "participant1_id INTEGER, "
            "participant2_id INTEGER, "
            "uuid TEXT)"
        )));
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS Messages")));
        // Schema aligne sur celui produit par les migrations reelles
        // (003_update_messages_table + 011_add_sync_uuid_columns + 033 + 034) : la
        // colonne uuid est requise par MessageRepository::insert(), sans
        // elle query.prepare() echoue silencieusement ("Parameter count
        // mismatch") faute de colonne correspondante.
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE Messages ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "conversationId INTEGER NOT NULL, "
            "senderId INTEGER NOT NULL, "
            "content TEXT NOT NULL, "
            "timestamp TEXT, "
            "is_read INTEGER DEFAULT 0, "
            "uuid TEXT, "
            "delivery_status TEXT NOT NULL DEFAULT 'sent', edited_at TEXT, deleted_at TEXT)"
        )));

        // Creer deux utilisateurs de test
        m_userManager = std::make_unique<core::UserManager>(m_dbManager.get());
        const auto user1 = m_userManager->createUser(QStringLiteral("alice"), QStringLiteral("password1"));
        const auto user2 = m_userManager->createUser(QStringLiteral("bob"), QStringLiteral("password2"));
        Q_ASSERT(user1.has_value());
        Q_ASSERT(user2.has_value());

        m_messagingManager = std::make_unique<MessagingManager>(m_dbManager.get());
    }

private slots:
    void cleanup()
    {
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_messagingManager.reset();
        m_userManager.reset();
        m_dbManager.reset();
        m_dir.reset();
    }

    void initTestCase()
    {
        // Initialisation Qt
    }

    void getOrCreateConversation_createsNewConversation()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());
        QVERIFY(conv->id() > 0);
        QCOMPARE(conv->type(), models::ConversationType::Individual);
        QCOMPARE(conv->participant1Id(), user1Id);
        QCOMPARE(conv->participant2Id(), user2Id);
    }

    void getOrCreateConversation_reusesExistingConversation()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv1 = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv1.has_value());

        const auto conv2 = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv2.has_value());

        QCOMPARE(conv1->id(), conv2->id());
    }

    void getOrCreateConversation_rejectsSameUser()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user1Id);
        QVERIFY(!conv.has_value());
        QCOMPARE(m_messagingManager->lastError(), MessagingManagerError::InvalidUser);
    }

    void sendMessage_succeeds()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QSignalSpy messageSentSpy(m_messagingManager.get(), &MessagingManager::messageSent);

        const auto msg = m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Hello Bob"));
        QVERIFY(msg.has_value());
        QVERIFY(msg->id() > 0);
        QCOMPARE(msg->conversationId(), conv->id());
        QCOMPARE(msg->senderId(), user1Id);
        QCOMPARE(msg->content(), QStringLiteral("Hello Bob"));

        QCOMPARE(messageSentSpy.count(), 1);
    }

    void sendMessage_rejectsEmptyContent()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        const auto msg = m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral(""));
        QVERIFY(!msg.has_value());
        QCOMPARE(m_messagingManager->lastError(), MessagingManagerError::InvalidContent);
    }

    void sendMessage_toGroupConversation_succeeds()
    {
        // sendMessage()/getMessages() ne discriminent que par conversationId :
        // une conversation de type 'group' doit donc fonctionner exactement
        // comme une conversation individuelle, sans aucun changement de code.
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        QSqlQuery query(m_dbManager->database());
        query.prepare(QStringLiteral(
            "INSERT INTO Conversations (type, name) VALUES ('group', 'Groupe Test')"));
        QVERIFY(query.exec());
        const qint64 groupConversationId = query.lastInsertId().toLongLong();

        const auto msg = m_messagingManager->sendMessage(groupConversationId, user1Id, QStringLiteral("Salut a tous"));
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), groupConversationId);

        m_messagingManager->sendMessage(groupConversationId, user2Id, QStringLiteral("Salut !"));

        const auto messages = m_messagingManager->getMessages(groupConversationId);
        QCOMPARE(messages.size(), 2);
    }

    void getMessages_returnsMessages()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Message 1"));
        m_messagingManager->sendMessage(conv->id(), user2Id, QStringLiteral("Message 2"));
        m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Message 3"));

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 3);
        QCOMPARE(messages[0].content(), QStringLiteral("Message 1"));
        QCOMPARE(messages[1].content(), QStringLiteral("Message 2"));
        QCOMPARE(messages[2].content(), QStringLiteral("Message 3"));
    }

    void getUserConversations_returnsUserConversations()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        const auto user1Convs = m_messagingManager->getUserConversations(user1Id);
        QCOMPARE(user1Convs.size(), 1);
        QCOMPARE(user1Convs[0].id(), conv->id());

        const auto user2Convs = m_messagingManager->getUserConversations(user2Id);
        QCOMPARE(user2Convs.size(), 1);
        QCOMPARE(user2Convs[0].id(), conv->id());
    }

    void receiveMessage_persistsAndEmitsSignal()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QSignalSpy messageReceivedSpy(m_messagingManager.get(), &MessagingManager::messageReceived);

        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationUuid\":\"%1\",\"senderUuid\":\"%2\",\"messageUuid\":\"%3\",\"content\":\"Salut Alice\"}")
            .arg(conv->uuid()).arg(users[1].uuid()).arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), conv->id());
        QCOMPARE(msg->senderId(), user2Id);
        QCOMPARE(msg->content(), QStringLiteral("Salut Alice"));
        QCOMPARE(messageReceivedSpy.count(), 1);

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 1);
    }

    // File d'envoi : sans connexion, le message est garde "en attente" (l'UI est
    // prevenue qu'il partira a la reconnexion) jusqu'a l'accuse du serveur.
    void sendMessage_withoutConnection_isPendingUntilAcknowledged()
    {
        freshDatabase();
        const auto users = m_userManager->allUsers();
        const auto conv = m_messagingManager->getOrCreateConversation(users[0].id(), users[1].id());
        QVERIFY(conv.has_value());

        QSignalSpy failed(m_messagingManager.get(), &MessagingManager::messageSendFailed);
        QSignalSpy queued(m_messagingManager.get(), &MessagingManager::messageQueued);
        QSignalSpy delivery(m_messagingManager.get(), &MessagingManager::messageDeliveryChanged);
        const auto msg = m_messagingManager->sendMessage(conv->id(), users[0].id(), QStringLiteral("hors ligne"));
        QVERIFY(msg.has_value());
        QVERIFY(msg->isPending());
        // Pas un echec (le texte n'est pas rendu a l'UI) : mis en attente.
        QCOMPARE(failed.count(), 0);
        QCOMPARE(queued.count(), 1);
        QCOMPARE(queued.first().at(0).toLongLong(), conv->id());
        // Rien a renvoyer tant qu'il n'y a pas de connexion.
        QCOMPARE(m_messagingManager->resendPendingMessages(users[0].id()), 0);

        QVERIFY(m_messagingManager->markMessageSent(msg->uuid()));
        QCOMPARE(delivery.count(), 1);
        QCOMPARE(delivery.first().at(1).toString(), models::Message::Sent);
        QVERIFY(!m_messagingManager->markMessageSent(msg->uuid())); // accuse en double : sans effet
        QVERIFY(m_messagingManager->takeOverPendingMessages().isEmpty());
    }

    // Modification / suppression : reservees a l'auteur, et seulement si le
    // Modification / suppression : reservees a l'auteur, possibles hors
    // connexion (le changement est propage par l'appelant, a la reconnexion) ;
    // un message pas encore parti change ou disparait sur place.
    void editAndDeleteMessage_byAuthorEvenOffline()
    {
        freshDatabase();
        const auto users = m_userManager->allUsers();
        const auto conv = m_messagingManager->getOrCreateConversation(users[0].id(), users[1].id());
        QVERIFY(conv.has_value());
        QSignalSpy outgoing(m_messagingManager.get(), &MessagingManager::messageChangeOutgoing);
        QSignalSpy removed(m_messagingManager.get(), &MessagingManager::messageRemoved);

        // Pas encore parti : modifie sur place, rien a propager (le renvoi portera le texte).
        const auto pending = m_messagingManager->sendMessage(conv->id(), users[0].id(), QStringLiteral("brouillon"));
        QVERIFY(pending.has_value());
        QVERIFY(m_messagingManager->editMessage(pending->uuid(), QStringLiteral("brouillon corrige"), users[0].id()));
        QCOMPARE(outgoing.count(), 0);
        QCOMPARE(m_messagingManager->resendPendingMessages(users[0].id()), 0); // hors connexion
        // Supprime avant de partir : simplement retire.
        QVERIFY(m_messagingManager->deleteMessage(pending->uuid(), users[0].id()));
        QCOMPARE(removed.count(), 1);
        QCOMPARE(outgoing.count(), 0);
        QVERIFY(m_messagingManager->getMessages(conv->id()).isEmpty());

        // Deja parti : la modification est propagee, meme sans connexion.
        const auto msg = m_messagingManager->sendMessage(conv->id(), users[0].id(), QStringLiteral("version 1"));
        QVERIFY(msg.has_value());
        QVERIFY(m_messagingManager->markMessageSent(msg->uuid()));
        QVERIFY(!m_messagingManager->editMessage(msg->uuid(), QStringLiteral("pirate"), users[1].id())); // pas l'auteur
        QVERIFY(m_messagingManager->editMessage(msg->uuid(), QStringLiteral("version 2"), users[0].id()));
        QCOMPARE(outgoing.count(), 1);
        QCOMPARE(outgoing.last().at(0).toJsonObject().value(QStringLiteral("action")).toString(), QStringLiteral("edit"));
        QCOMPARE(outgoing.last().at(0).toJsonObject().value(QStringLiteral("content")).toString(), QStringLiteral("version 2"));
        QVERIFY(m_messagingManager->deleteMessage(msg->uuid(), users[0].id()));
        QCOMPARE(outgoing.count(), 2);
        QCOMPARE(outgoing.last().at(0).toJsonObject().value(QStringLiteral("action")).toString(), QStringLiteral("delete"));
        QVERIFY(!m_messagingManager->editMessage(msg->uuid(), QStringLiteral("revient"), users[0].id())); // supprime
    }

    // Modification recue : appliquee seulement si elle vient de l'auteur ;
    // suppression : texte efface, ligne gardee.
    void receiveMessageUpdate_appliesOnlyFromAuthor()
    {
        freshDatabase();
        const auto users = m_userManager->allUsers();
        const auto conv = m_messagingManager->getOrCreateConversation(users[0].id(), users[1].id());
        QVERIFY(conv.has_value());
        const QString uuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationUuid\":\"%1\",\"senderUuid\":\"%2\",\"messageUuid\":\"%3\",\"content\":\"original\"}")
            .arg(conv->uuid(), users[1].uuid(), uuid);
        QVERIFY(m_messagingManager->receiveMessage(payload).has_value());

        QSignalSpy updated(m_messagingManager.get(), &MessagingManager::messageUpdated);
        QJsonObject edit{{QStringLiteral("type"), QStringLiteral("message_update")}, {QStringLiteral("action"), QStringLiteral("edit")},
                         {QStringLiteral("messageUuid"), uuid}, {QStringLiteral("content"), QStringLiteral("corrige")},
                         {QStringLiteral("editedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
                         {QStringLiteral("senderUuid"), users[0].uuid()}};
        QVERIFY(!m_messagingManager->receiveMessageUpdate(edit)); // pas l'auteur
        edit.insert(QStringLiteral("senderUuid"), users[1].uuid());
        QVERIFY(m_messagingManager->receiveMessageUpdate(edit));
        QCOMPARE(updated.count(), 1);
        auto stored = updated.first().at(0).value<models::Message>();
        QCOMPARE(stored.content(), QStringLiteral("corrige"));
        QVERIFY(stored.editedAt().isValid());

        QJsonObject del = edit;
        del.insert(QStringLiteral("action"), QStringLiteral("delete"));
        del.insert(QStringLiteral("deletedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        QVERIFY(m_messagingManager->receiveMessageUpdate(del));
        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 1);
        QVERIFY(messages[0].isDeleted());
        QVERIFY(messages[0].content().isEmpty());
        // Une modification apres suppression ne fait pas revivre le texte.
        QVERIFY(!m_messagingManager->receiveMessageUpdate(edit));
    }

    // Accuses : "remis" puis "lu" par le destinataire -> etat d'envoi de
    // l'expediteur ; l'etat "lu" est propre a chaque utilisateur.
    void receipts_drivesDeliveryStatusAndPerUserRead()
    {
        freshDatabase();
        const auto users = m_userManager->allUsers();
        const qint64 alice = users[0].id(), bob = users[1].id();
        const auto conv = m_messagingManager->getOrCreateConversation(alice, bob);
        QVERIFY(conv.has_value());
        const auto msg = m_messagingManager->sendMessage(conv->id(), alice, QStringLiteral("bonjour"));
        QVERIFY(msg.has_value());
        QVERIFY(m_messagingManager->markMessageSent(msg->uuid()));

        QSignalSpy delivery(m_messagingManager.get(), &MessagingManager::messageDeliveryChanged);
        const QDateTime now = QDateTime::currentDateTimeUtc();
        m_messagingManager->applyReceipts({{msg->uuid(), users[1].uuid(), now, {}}});
        QCOMPARE(delivery.count(), 1);
        QCOMPARE(delivery.last().at(1).toString(), models::Message::Delivered);
        m_messagingManager->applyReceipts({{msg->uuid(), users[1].uuid(), now, now}});
        QCOMPARE(delivery.last().at(1).toString(), models::Message::Read);
        // Un accuse en retard ne fait pas reculer l'etat.
        m_messagingManager->applyReceipts({{msg->uuid(), users[1].uuid(), now, {}}});
        QCOMPARE(delivery.count(), 2);

        // Etat "lu" par utilisateur : bob n'a rien lu tant qu'il n'a pas ouvert.
        const auto reply = m_messagingManager->sendMessage(conv->id(), bob, QStringLiteral("salut"));
        QVERIFY(reply.has_value());
        QCOMPARE(m_messagingManager->getUnreadCount(conv->id(), alice), 1);
        QSignalSpy pending(m_messagingManager.get(), &MessagingManager::receiptsPending);
        QVERIFY(m_messagingManager->markConversationAsRead(conv->id(), alice));
        QCOMPARE(pending.count(), 1); // accuse "lu" a transmettre
        QCOMPARE(m_messagingManager->getUnreadCount(conv->id(), alice), 0);
        const auto receipts = m_messagingManager->pendingReceipts();
        QCOMPARE(receipts.size(), 1);
        QCOMPARE(receipts[0].userUuid, users[0].uuid());
        QVERIFY(receipts[0].readAt.isValid());
        m_messagingManager->clearPendingReceipt(receipts[0].messageUuid, receipts[0].userUuid);
        QVERIFY(m_messagingManager->pendingReceipts().isEmpty());
    }

    // Le destinataire garde l'heure d'ENVOI transmise (message remis en retard),
    // sauf si elle est dans le futur.
    void receiveMessage_keepsSenderTimestamp()
    {
        freshDatabase();
        const auto users = m_userManager->allUsers();
        const auto conv = m_messagingManager->getOrCreateConversation(users[0].id(), users[1].id());
        QVERIFY(conv.has_value());

        const QDateTime sentAt = QDateTime::currentDateTimeUtc().addSecs(-7200);
        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationUuid\":\"%1\",\"senderUuid\":\"%2\",\"messageUuid\":\"%3\","
            "\"content\":\"envoye il y a deux heures\",\"timestamp\":\"%4\"}")
            .arg(conv->uuid(), users[1].uuid(), QUuid::createUuid().toString(QUuid::WithoutBraces),
                 sentAt.toString(Qt::ISODate));
        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QVERIFY(qAbs(msg->timestamp().secsTo(sentAt)) <= 1);

        const QString future = QStringLiteral(
            "{\"type\":\"message\",\"conversationUuid\":\"%1\",\"senderUuid\":\"%2\",\"messageUuid\":\"%3\","
            "\"content\":\"horloge en avance\",\"timestamp\":\"%4\"}")
            .arg(conv->uuid(), users[1].uuid(), QUuid::createUuid().toString(QUuid::WithoutBraces),
                 QDateTime::currentDateTimeUtc().addDays(1).toString(Qt::ISODate));
        const auto clamped = m_messagingManager->receiveMessage(future);
        QVERIFY(clamped.has_value());
        QVERIFY(clamped->timestamp() <= QDateTime::currentDateTimeUtc().addSecs(1));
    }

    void receiveMessage_survivesApostropheInContent()
    {
        // Regression : l'ancienne implementation construisait le SQL par
        // concatenation de chaines ('%3'), ce qui cassait (ou permettait une
        // injection SQL) des qu'une apostrophe apparaissait dans le contenu.
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QJsonObject payloadObj;
        payloadObj.insert(QStringLiteral("type"), QStringLiteral("message"));
        payloadObj.insert(QStringLiteral("conversationUuid"), conv->uuid());
        payloadObj.insert(QStringLiteral("senderUuid"), users[1].uuid());
        payloadObj.insert(QStringLiteral("messageUuid"), QUuid::createUuid().toString(QUuid::WithoutBraces));
        payloadObj.insert(QStringLiteral("content"), QStringLiteral("C'est l'ami d'Alice"));
        const QString payload = QString::fromUtf8(QJsonDocument(payloadObj).toJson(QJsonDocument::Compact));

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->content(), QStringLiteral("C'est l'ami d'Alice"));

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 1);
        QCOMPARE(messages[0].content(), QStringLiteral("C'est l'ami d'Alice"));
    }

    void receiveMessage_forGroupConversation_persists()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user2Id = users[1].id();

        QSqlQuery query(m_dbManager->database());
        query.prepare(QStringLiteral(
            "INSERT INTO Conversations (type, name, uuid) VALUES ('group', 'Groupe Test', :uuid)"));
        query.bindValue(QStringLiteral(":uuid"), QUuid::createUuid().toString(QUuid::WithoutBraces));
        QVERIFY(query.exec());
        const qint64 groupConversationId = query.lastInsertId().toLongLong();
        QSqlQuery uuidQuery(m_dbManager->database());
        uuidQuery.prepare(QStringLiteral("SELECT uuid FROM Conversations WHERE id = :id"));
        uuidQuery.bindValue(QStringLiteral(":id"), groupConversationId);
        QVERIFY(uuidQuery.exec());
        QVERIFY(uuidQuery.next());
        const QString groupConversationUuid = uuidQuery.value(0).toString();

        QSignalSpy messageReceivedSpy(m_messagingManager.get(), &MessagingManager::messageReceived);

        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationUuid\":\"%1\",\"senderUuid\":\"%2\",\"messageUuid\":\"%3\",\"content\":\"Salut le groupe\"}")
            .arg(groupConversationUuid).arg(users[1].uuid())
            .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), groupConversationId);
        QCOMPARE(messageReceivedSpy.count(), 1);

        const auto messages = m_messagingManager->getMessages(groupConversationId);
        QCOMPARE(messages.size(), 1);
    }

    void receiveMessage_rejectsInvalidJson()
    {
        freshDatabase();

        const auto msg = m_messagingManager->receiveMessage(QStringLiteral("not json"));
        QVERIFY(!msg.has_value());
    }

    void receiveMessage_rejectsUnknownType()
    {
        freshDatabase();

        const auto msg = m_messagingManager->receiveMessage(
            QStringLiteral("{\"type\":\"ping\"}"));
        QVERIFY(!msg.has_value());
    }
};

QTEST_MAIN(TestMessagingManager)
#include "test_messagingmanager.moc"
