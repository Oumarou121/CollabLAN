#ifndef CORE_USERMANAGER_H
#define CORE_USERMANAGER_H

#include <QObject>
#include <QString>
#include <optional>
#include <vector>

#include "database/Repositories/SessionRepository.h"
#include "database/Repositories/UserRepository.h"
#include "models/User.h"

namespace database {
class DatabaseManager;
}

namespace core {

/**
 * @brief Resultat d'une operation de creation/authentification.
 */
enum class UserManagerError {
    None,
    InvalidName,
    InvalidPassword,
    UserAlreadyExists,
    UserNotFound,
    WrongPassword,
    DatabaseError
};

/**
 * @brief Gestion des utilisateurs (creation, authentification, statut).
 *
 * Expose a la QML (voir ui/Login/LoginView.qml, branche via
 * `engine.rootContext()->setContextProperty("userManager", ...)`) une
 * API d'authentification reelle adossee a database::UserRepository,
 * ainsi qu'une API C++ plus riche (createUser/setStatus/allUsers) pour
 * les besoins d'administration.
 */
class UserManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool authenticated READ isAuthenticated NOTIFY authenticationChanged)
    Q_PROPERTY(QString currentUsername READ currentUsername NOTIFY authenticationChanged)
    Q_PROPERTY(bool currentUserIsAdmin READ isCurrentUserAdmin NOTIFY authenticationChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)

public:
    // databaseManager doit rester valide pendant toute la duree de vie
    // de UserManager (Application en est proprietaire).
    explicit UserManager(database::DatabaseManager *databaseManager, QObject *parent = nullptr);
    ~UserManager() override;

    // --- API QML (utilisee par LoginView.qml) ---------------------------

    // Tente une authentification. Emet loginSucceeded(username) et met
    // a jour authenticated/currentUsername sur succes, sinon emet
    // loginFailed(reason) avec un message destine a l'utilisateur.
    Q_INVOKABLE bool login(const QString &username, const QString &password);
    Q_INVOKABLE void logout();

    // --- "Se souvenir de moi" (migration #026, database::SessionRepository) --

    // A appeler juste apres un login() reussi si la case "Se souvenir de
    // moi" est cochee. Genere un jeton aleatoire haute-entropie, n'en
    // persiste que le hash SHA-256 en base (table UserSessions), et
    // retourne le jeton en clair pour que la QML le stocke localement
    // (settingsModel.rememberedSessionToken, jamais en base). Chaine vide
    // en cas d'echec (utilisateur non authentifie ou erreur base).
    Q_INVOKABLE QString rememberThisDevice();

    // Tentative d'auto-login silencieuse au demarrage (Main.qml), a partir
    // du nom d'utilisateur et du jeton persistes localement. Ne emet PAS
    // loginFailed en cas d'echec (jeton expire/invalide) : l'appelant doit
    // simplement retomber sur l'ecran Login sans afficher d'erreur. Emet
    // loginSucceeded sur reussite, exactement comme login().
    Q_INVOKABLE bool loginWithRememberedToken(const QString &username, const QString &token);

    // Invalide explicitement un jeton "Se souvenir de moi" (ex: la case
    // est decochee sans se deconnecter). N'affecte pas la session en cours.
    Q_INVOKABLE void forgetRememberedToken(const QString &token);

    bool isAuthenticated() const;
    QString currentUsername() const;
    bool isCurrentUserAdmin() const;
    bool isBusy() const;

    /// Id (table Users) de l'utilisateur actuellement authentifie, ou
    /// nullopt si personne n'est connecte. Utilise par ex. par
    /// core::TransferManager pour renseigner l'expediteur d'un transfert.
    std::optional<int> currentUserId() const;

    /// UUID (Users.uuid, migration #010) de l'utilisateur actuellement
    /// authentifie, ou chaine vide si personne n'est connecte. Utilise
    /// par ex. par core::TransferContext pour renseigner senderUuid d'un
    /// transfert (voir migration #017 : sender_id/recipient_id entiers
    /// remplaces par sender_uuid/recipient_uuid).
    QString currentUserUuid() const;

    /// Nom affiche pour un UUID Users.uuid, ou chaine vide si inconnu.
    QString userNameForUuid(const QString &uuid) const;

    // --- API C++ (administration) ---------------------------------------

    /**
     * @brief Cree un nouvel utilisateur local avec un mot de passe.
     *
     * Le mot de passe n'est jamais stocke en clair : il est sale puis
     * hache (SHA-256, core::PasswordHasher) avant persistance.
     */
    std::optional<models::User> createUser(const QString &name,
                                            const QString &password,
                                            bool isAdmin = false);

    /**
     * @brief Verifie les identifiants d'un utilisateur sans modifier
     * l'etat "authentifie" QML (utilise en interne par login()).
     */
    std::optional<models::User> authenticate(const QString &name, const QString &password);

    /**
     * @brief Change le statut (en ligne / hors ligne / absent) d'un utilisateur.
     */
    bool setStatus(int userId, models::UserStatus status);
    std::optional<models::UserStatus> status(int userId) const;

    /**
     * @brief Change le role (User/Admin) d'un utilisateur existant.
     *        Met a jour updated_at pour que le replay LWW cote reconciliation
     *        (SyncLogRepository::applyUserEntry) puisse dater ce changement.
     */
    bool changeRole(int userId, bool isAdmin);

    /**
     * @brief Remplace le mot de passe d'un utilisateur sans exposer l'ancien.
     */
    bool resetPassword(int userId, const QString &newPassword);

    /**
     * @brief Supprime definitivement un utilisateur (administration).
     */
    bool deleteUser(int userId);

    std::vector<models::User> allUsers() const;

    /// Resout le nom d'un utilisateur a partir de son id, ou une chaine
    /// vide si l'id est inconnu (utile pour enrichir des notifications
    /// avec le nom de l'expediteur sans dupliquer un lookup repository
    /// dans chaque appelant, cf. NotificationManager).
    QString usernameForId(qint64 userId) const;

    /**
     * @brief Emet le signal usersChanged() pour notifier que la liste
     *        d'utilisateurs a change (apres synchronisation par exemple).
     */
    void emitUsersChanged();

    /**
     * @brief Dernier message d'erreur SQL brut (debogage).
     */
    QString lastDatabaseErrorText() const;
    UserManagerError lastError() const;

signals:
    void loginSucceeded(const QString &username);
    void loginFailed(const QString &reason);
    void authenticationChanged();
    void busyChanged();

    /**
     * @brief Emis apres une ecriture reelle en base sur Users (creation,
     *        changement de role/statut). Utilise par Application pour
     *        journaliser dans SyncLog (cf. Application::appendUserSyncLog)
     *        quand ce poste fait autorite (SERVER ou TEMP_SERVER).
     */
    void userCreated(const models::User &user);
    void userUpdated(const models::User &user);
    void userDeleted(const QString &uuid, int id);

    /**
     * @brief Emis quand la liste des utilisateurs change (creation,
     *        suppression, ou synchronisation depuis un autre poste).
     */
    void usersChanged();

private:
    void setBusy(bool busy);

    database::DatabaseManager *m_databaseManager;
    database::UserRepository m_userRepository;
    database::SessionRepository m_sessionRepository;

    bool m_authenticated = false;
    bool m_busy = false;
    QString m_currentUsername;
    bool m_currentUserIsAdmin = false;
    std::optional<int> m_currentUserId;
    QString m_currentUserUuid;

    UserManagerError m_lastError = UserManagerError::None;
};

} // namespace core

#endif // CORE_USERMANAGER_H