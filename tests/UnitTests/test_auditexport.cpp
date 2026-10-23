// Export CSV du journal d'audit, dans les conditions de l'ecran Journal
// (AuditJournalView::reload : filtres remis a zero, periode, puis export).
#include <QtTest>
#include <QFile>
#include <QHostAddress>
#include <QTemporaryDir>

#include "AuditLogModel.h"
#include "AuditManager.h"
#include "DatabaseManager.h"

class TestAuditExport : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    std::unique_ptr<database::DatabaseManager> m_db;
    std::unique_ptr<core::AuditManager> m_audit;

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_db = std::make_unique<database::DatabaseManager>(QStringLiteral("auditexport"));
        QVERIFY(m_db->open(m_dir.filePath(QStringLiteral("audit.db"))));
        m_audit = std::make_unique<core::AuditManager>(m_db.get());
        for (int i = 0; i < 250; ++i)
            m_audit->logRefusedAttempt(QStringLiteral("Certificat inconnu, essai n°%1").arg(i),
                                       QHostAddress(QStringLiteral("192.168.1.77")));
        m_audit->logCall(std::nullopt, QHostAddress(QStringLiteral("192.168.1.21")), QStringLiteral("Terminé"), QStringLiteral("Entrant, Bureau 2"));
    }

    void exportsWhatTheJournalShows()
    {
        core::AuditLogModel model;
        model.setAuditManager(reinterpret_cast<QObject *>(m_audit.get()));
        // Meme sequence que AuditJournalView::reload() (periode de 7 jours).
        model.setUserIdFilter(0);
        model.setEventTypeFilter(QString());
        model.setDateRange(QDate::currentDate().addDays(-6).toString(Qt::ISODate) + QStringLiteral("T00:00:00"), QString());
        QVERIFY2(model.rowCount() > 0, "le journal ne lit aucune entree pour la periode");

        const QString path = m_dir.filePath(QStringLiteral("journal.csv"));
        QCOMPARE(model.exportToCsv(path), path);

        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray content = file.readAll();
        qInfo().noquote() << "DEBUT CSV" << QString::fromUtf8(content.mid(3, 300));
        // Excel (francais) : BOM UTF-8 pour les accents, point-virgule comme
        // separateur, champs contenant le separateur entre guillemets.
        QVERIFY2(content.startsWith("\xEF\xBB\xBF"), "pas de BOM : accents illisibles dans Excel");
        const QList<QByteArray> lines = content.mid(3).split('\n');
        QVERIFY(lines.first().contains(';'));
        // Toutes les entrees de la periode, pas seulement les 200 affichees.
        QVERIFY2(lines.size() - 2 >= 251, qPrintable(QStringLiteral("%1 lignes exportees").arg(lines.size() - 2)));
        // Chaque ligne a le meme nombre de colonnes que l'en-tete.
        const int columns = lines.first().count(';');
        for (const QByteArray &line : lines.mid(1)) {
            if (line.trimmed().isEmpty()) continue;
            int count = 0;
            bool quoted = false;
            for (char c : line) {
                if (c == '"') quoted = !quoted;
                else if (c == ';' && !quoted) ++count;
            }
            QCOMPARE(count, columns);
        }
    }
};

QTEST_MAIN(TestAuditExport)
#include "test_auditexport.moc"
