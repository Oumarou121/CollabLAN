#ifndef CORE_CALLHISTORYMODEL_H
#define CORE_CALLHISTORYMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include <QString>

#include "models/CallHistoryEntry.h"

namespace core {

class CallHistoryManager;
class UserManager;

/**
 * @brief Modele QML pour afficher l'historique des appels
 * (ui/Call/CallHistoryView.qml), suivant le meme patron que AuditLogModel
 * pour AdminView.qml.
 *
 * Par defaut, affiche uniquement les appels de l'utilisateur local
 * actuellement connecte (userManager fourni) ; setShowAllUsers(true)
 * bascule sur l'historique complet (tous comptes locaux confondus), utile
 * pour un poste partage sans separation stricte par compte.
 */
class CallHistoryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QObject* callHistoryManager READ callHistoryManager WRITE setCallHistoryManager NOTIFY callHistoryManagerChanged)
    Q_PROPERTY(bool showAllUsers READ showAllUsers WRITE setShowAllUsers NOTIFY showAllUsersChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        DirectionRole,
        PeerAddressRole,
        PeerNameRole,
        StatusRole,
        StartedAtRole,
        DurationSecondsRole,
        ParticipantsRole,
    };

    explicit CallHistoryModel(QObject *parent = nullptr);
    ~CallHistoryModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QObject* callHistoryManager() const;
    void setCallHistoryManager(QObject *manager);

    /// Necessaire pour filtrer sur l'utilisateur local actuellement
    /// connecte (voir showAllUsers()).
    void setUserManager(UserManager *userManager);

    bool showAllUsers() const { return m_showAllUsers; }
    void setShowAllUsers(bool showAllUsers);

    int count() const { return m_entries.size(); }

    Q_INVOKABLE void refresh();

signals:
    void callHistoryManagerChanged();
    void showAllUsersChanged();
    void countChanged();

private:
    void loadEntries();

    core::CallHistoryManager *m_callHistoryManager = nullptr;
    core::UserManager *m_userManager = nullptr;
    QVector<models::CallHistoryEntry> m_entries;
    bool m_showAllUsers = false;
};

} // namespace core

#endif // CORE_CALLHISTORYMODEL_H
