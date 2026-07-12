#include <QtTest>
#include <QSignalSpy>
#include "NotificationManager.h"
#include "NotificationService.h"

using core::NotificationManager;
using services::NotificationService;

class TestNotification : public QObject
{
    Q_OBJECT

private:
    NotificationManager *m_notificationManager;
    NotificationService *m_notificationService;

private slots:
    void initTestCase()
    {
        m_notificationManager = new NotificationManager(this);
        m_notificationService = new NotificationService(this);

        // Connecter NotificationManager à NotificationService
        connect(m_notificationManager, &NotificationManager::notificationRequested,
                m_notificationService, &NotificationService::showNotification);
    }

    void cleanupTestCase()
    {
        delete m_notificationManager;
        delete m_notificationService;
    }

    void notificationManager_emitsNotificationWhenEnabled()
    {
        m_notificationManager->setNotificationsEnabled(true);

        models::Message message(1, 100, 200, QStringLiteral("Hello World"));
        message.setTimestamp(QDateTime::currentDateTime());

        QSignalSpy spy(m_notificationManager, &NotificationManager::notificationRequested);

        m_notificationManager->onMessageReceived(message);

        QCOMPARE(spy.count(), 1);
        QList<QVariant> arguments = spy.takeFirst();
        QCOMPARE(arguments.at(0).toString(), QStringLiteral("Nouveau message"));
        QCOMPARE(arguments.at(1).toString(), QStringLiteral("Hello World"));
    }

    void notificationManager_doesNotEmitWhenDisabled()
    {
        m_notificationManager->setNotificationsEnabled(false);

        models::Message message(1, 100, 200, QStringLiteral("Hello World"));
        message.setTimestamp(QDateTime::currentDateTime());

        QSignalSpy spy(m_notificationManager, &NotificationManager::notificationRequested);

        m_notificationManager->onMessageReceived(message);

        QCOMPARE(spy.count(), 0);
    }

    void notificationService_emitsSignal()
    {
        QSignalSpy spy(m_notificationService, &NotificationService::notificationAvailable);

        m_notificationService->showNotification(QStringLiteral("Title"), QStringLiteral("Message"));

        QCOMPARE(spy.count(), 1);
        QList<QVariant> arguments = spy.takeFirst();
        QCOMPARE(arguments.at(0).toString(), QStringLiteral("Title"));
        QCOMPARE(arguments.at(1).toString(), QStringLiteral("Message"));
    }

    void notificationChain_works()
    {
        m_notificationManager->setNotificationsEnabled(true);

        models::Message message(1, 100, 200, QStringLiteral("Test message"));
        message.setTimestamp(QDateTime::currentDateTime());

        QSignalSpy serviceSpy(m_notificationService, &NotificationService::notificationAvailable);

        // Simuler la réception d'un message
        m_notificationManager->onMessageReceived(message);

        QCOMPARE(serviceSpy.count(), 1);
        QList<QVariant> arguments = serviceSpy.takeFirst();
        QCOMPARE(arguments.at(0).toString(), QStringLiteral("Nouveau message"));
        QCOMPARE(arguments.at(1).toString(), QStringLiteral("Test message"));
    }
};

QTEST_MAIN(TestNotification)
#include "test_notification.moc"
