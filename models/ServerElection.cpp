#include "ServerElection.h"

namespace models {

QString serverRoleToString(ServerRole role)
{
    switch (role) {
    case ServerRole::Server:
        return QStringLiteral("SERVER");
    case ServerRole::TempServer:
        return QStringLiteral("TEMP_SERVER");
    case ServerRole::Client:
    default:
        return QStringLiteral("CLIENT");
    }
}

ServerRole serverRoleFromString(const QString &value)
{
    if (value.compare(QStringLiteral("SERVER"), Qt::CaseInsensitive) == 0) {
        return ServerRole::Server;
    }
    if (value.compare(QStringLiteral("TEMP_SERVER"), Qt::CaseInsensitive) == 0) {
        return ServerRole::TempServer;
    }
    return ServerRole::Client;
}

ServerElection::ServerElection() = default;

ServerElectionLogEntry::ServerElectionLogEntry() = default;

ServerElectionLogEntry::ServerElectionLogEntry(int id,
                                                const QString &event,
                                                int epoch,
                                                const QString &machineUuid,
                                                const QDateTime &createdAt)
    : m_id(id)
    , m_event(event)
    , m_epoch(epoch)
    , m_machineUuid(machineUuid)
    , m_createdAt(createdAt)
{
}

} // namespace models
