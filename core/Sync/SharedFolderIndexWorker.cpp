#include "SharedFolderIndexWorker.h"

#include <QDebug>
#include <QUuid>

namespace core::sync {

SharedFolderIndexWorker::SharedFolderIndexWorker(QString dbFilePath, QObject *parent)
    : QObject(parent)
    , m_dbFilePath(std::move(dbFilePath))
{
}

SharedFolderIndexWorker::~SharedFolderIndexWorker() = default;

bool SharedFolderIndexWorker::ensureDatabaseOpen()
{
    if (m_dbManager && m_dbManager->isOpen()) {
        return true;
    }

    // Nom de connexion Qt unique a ce worker (un seul worker/QThread pour
    // toute la duree de vie de SyncEngine, mais on garde un suffixe unique
    // pour eviter toute collision si jamais plusieurs instances de
    // SyncEngine coexistaient, ex: tests). Les migrations sont deja
    // appliquees par la connexion principale du thread UI au demarrage de
    // l'appli : ouvrir ici ne fait que rejouer la verification "deja
    // applique" (schema_migrations), sans effet de bord.
    const QString connectionName =
        QStringLiteral("localink_db_index_worker_%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

    m_dbManager = std::make_unique<database::DatabaseManager>(connectionName);
    if (!m_dbManager->open(m_dbFilePath)) {
        qWarning() << "[SharedFolderIndexWorker] Echec ouverture connexion SQLite dediee :"
                   << m_dbManager->lastError();
        m_dbManager.reset();
        return false;
    }

    m_folderManager = std::make_unique<core::SharedFolderManager>(m_dbManager.get());
    return true;
}

void SharedFolderIndexWorker::indexFolder(qint64 folderId)
{
    if (!ensureDatabaseOpen()) {
        emit finished(folderId, false, {}, QStringLiteral("Connexion base de donnees indisponible (worker)"));
        return;
    }

    // C'est ICI, et uniquement ici, que le parcours recursif + hash
    // SHA-256 + upserts SQLite couteux se produisent desormais -- sur ce
    // thread dedie, jamais sur le thread UI.
    const auto changes = m_folderManager->shareFolder(folderId);
    if (!changes.has_value()) {
        emit finished(folderId, false, {}, m_folderManager->lastErrorString());
        return;
    }

    emit finished(folderId, true, *changes, QString());
}

} // namespace core::sync
