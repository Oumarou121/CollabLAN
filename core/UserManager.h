#ifndef CORE_USERMANAGER_H
#define CORE_USERMANAGER_H

#include <QObject>
#include <QString>
#include <memory>

namespace database {
class DatabaseManager;
class UserRepository;
}

namespace core {

/**
 * @brief Gestion des utilisateurs (creation, authentification, statut).
 *
 * Expose a la QML (voir ui/Login/LoginView.qml, brancher via
 * `engine.rootContext()->setContextProperty("userManager", ...)`) une
 * API d'authentification reelle, adossee a database::UserRepository :
 * plus de mock, login() verifie le mot de passe (core::PasswordHasher)
 * contre la table Users.
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

    // Tente une authentification. Emet loginSucceeded(username) et met
    // a jour authenticated/currentUsername sur succes, sinon emet
    // loginFailed(reason) avec un message destine a l'utilisateur.
    // Retourne le resultat pour un usage synchrone eventuel en C++.
    Q_INVOKABLE bool login(const QString &username, const QString &password);

    Q_INVOKABLE void logout();

    bool isAuthenticated() const;
    QString currentUsername() const;
    bool isCurrentUserAdmin() const;
    bool isBusy() const;

signals:
    void loginSucceeded(const QString &username);
    void loginFailed(const QString &reason);
    void authenticationChanged();
    void busyChanged();

private:
    void setBusy(bool busy);

    database::DatabaseManager *m_databaseManager;
    std::unique_ptr<database::UserRepository> m_userRepository;

    bool m_authenticated = false;
    bool m_busy = false;
    QString m_currentUsername;
    bool m_currentUserIsAdmin = false;
};

} // namespace core

#endif // CORE_USERMANAGER_H
