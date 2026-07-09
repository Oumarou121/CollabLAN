#ifndef MODELS_GROUP_H
#define MODELS_GROUP_H

#include <QString>
#include <QVector>

namespace models {

/**
 * @brief Represente un groupe de discussion.
 */
class Group {
public:
    Group();
    Group(qint64 id, const QString &name);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    QString name() const { return m_name; }
    void setName(const QString &name) { m_name = name; }

    QVector<qint64> memberIds() const { return m_memberIds; }
    void setMemberIds(const QVector<qint64> &memberIds) { m_memberIds = memberIds; }
    void addMember(qint64 memberId) { m_memberIds.append(memberId); }
    void removeMember(qint64 memberId) { m_memberIds.removeAll(memberId); }

    qint64 ownerId() const { return m_ownerId; }
    void setOwnerId(qint64 ownerId) { m_ownerId = ownerId; }

private:
    qint64 m_id = 0;
    QString m_name;
    QVector<qint64> m_memberIds;
    qint64 m_ownerId = 0;  // Créateur du groupe
};

} // namespace models

#endif // MODELS_GROUP_H
