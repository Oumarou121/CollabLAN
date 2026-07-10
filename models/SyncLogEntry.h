#ifndef MODELS_SYNCLOGENTRY_H
#define MODELS_SYNCLOGENTRY_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Une entree du journal de synchronisation (table SyncLog).
 *
 * Chaque ecriture faite localement pendant que ce poste fait autorite
 * (SERVER ou TEMP_SERVER, cf. HYBRID_SERVER_FAILOVER.md section 6) est
 * journalisee ici afin de pouvoir etre rejouee par le SERVER officiel a
 * son retour (section 7).
 */
class SyncLogEntry
{
public:
    SyncLogEntry();

    QString entryUuid() const { return m_entryUuid; }
    void setEntryUuid(const QString &uuid) { m_entryUuid = uuid; }

    QString tableName() const { return m_tableName; }
    void setTableName(const QString &name) { m_tableName = name; }

    QString recordUuid() const { return m_recordUuid; }
    void setRecordUuid(const QString &uuid) { m_recordUuid = uuid; }

    QString operation() const { return m_operation; }
    void setOperation(const QString &op) { m_operation = op; }

    QString payloadJson() const { return m_payloadJson; }
    void setPayloadJson(const QString &json) { m_payloadJson = json; }

    qint64 lamportClock() const { return m_lamportClock; }
    void setLamportClock(qint64 clock) { m_lamportClock = clock; }

    int epoch() const { return m_epoch; }
    void setEpoch(int epoch) { m_epoch = epoch; }

    QString originMachineId() const { return m_originMachineId; }
    void setOriginMachineId(const QString &id) { m_originMachineId = id; }

    QDateTime updatedAt() const { return m_updatedAt; }
    void setUpdatedAt(const QDateTime &dt) { m_updatedAt = dt; }

private:
    QString m_entryUuid;
    QString m_tableName;
    QString m_recordUuid;
    QString m_operation;
    QString m_payloadJson;
    qint64 m_lamportClock = 0;
    int m_epoch = 0;
    QString m_originMachineId;
    QDateTime m_updatedAt;
};

namespace SyncOperation {
inline const QString Insert = QStringLiteral("INSERT");
inline const QString Update = QStringLiteral("UPDATE");
inline const QString Delete = QStringLiteral("DELETE");
}

} // namespace models

#endif // MODELS_SYNCLOGENTRY_H
