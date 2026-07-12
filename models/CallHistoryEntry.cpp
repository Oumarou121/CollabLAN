#include "CallHistoryEntry.h"

namespace models {

CallHistoryEntry::CallHistoryEntry() = default;

QString callDirectionToString(CallDirection direction)
{
    switch (direction) {
    case CallDirection::Outgoing: return QStringLiteral("outgoing");
    case CallDirection::Incoming: return QStringLiteral("incoming");
    }
    return QStringLiteral("outgoing");
}

CallDirection callDirectionFromString(const QString &value)
{
    if (value == QStringLiteral("incoming"))
        return CallDirection::Incoming;
    return CallDirection::Outgoing;
}

QString callStatusToString(CallStatus status)
{
    switch (status) {
    case CallStatus::InProgress: return QStringLiteral("in_progress");
    case CallStatus::Completed:  return QStringLiteral("completed");
    case CallStatus::Missed:     return QStringLiteral("missed");
    case CallStatus::Rejected:   return QStringLiteral("rejected");
    case CallStatus::Cancelled:  return QStringLiteral("cancelled");
    case CallStatus::Failed:     return QStringLiteral("failed");
    }
    return QStringLiteral("in_progress");
}

CallStatus callStatusFromString(const QString &value)
{
    if (value == QStringLiteral("completed")) return CallStatus::Completed;
    if (value == QStringLiteral("missed")) return CallStatus::Missed;
    if (value == QStringLiteral("rejected")) return CallStatus::Rejected;
    if (value == QStringLiteral("cancelled")) return CallStatus::Cancelled;
    if (value == QStringLiteral("failed")) return CallStatus::Failed;
    return CallStatus::InProgress;
}

} // namespace models
