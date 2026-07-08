#ifndef APP_APPLICATION_H
#define APP_APPLICATION_H

#include <QObject>

/**
 * @brief Point d'entree logique de CollabLAN : initialise les services
 * (reseau, base de donnees, parametres) au demarrage de l'application.
 */
class Application : public QObject
{
    Q_OBJECT

public:
    explicit Application(QObject *parent = nullptr);
    ~Application();

    void initialize();

private:
    // TODO: instancier ici les services (Discovery, Database, Settings...)
};

#endif // APP_APPLICATION_H
