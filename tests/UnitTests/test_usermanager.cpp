#include <QtTest>
#include "core/UserManager.h"

class TestUserManager : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase() {}
    void testPlaceholder()
    {
        QVERIFY(true); // TODO: remplacer par de vrais tests
    }
};

QTEST_MAIN(TestUserManager)
#include "test_usermanager.moc"
