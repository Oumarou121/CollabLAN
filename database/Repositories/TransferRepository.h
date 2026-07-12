#ifndef DATABASE_TRANSFERREPOSITORY_H
#define DATABASE_TRANSFERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/Transfer.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table Transfers.
 *
 * Couche fine au-dessus de QSqlDatabase (requetes preparees, aucune
 * logique reseau) : network::TransferService s'en sert pour
 * enregistrer la progression/le resultat de chaque transfert.
 */
class TransferRepository {
public:
    explicit TransferRepository(QSqlDatabase database);
    ~TransferRepository();

    /**
     * @brief Insere un nouveau transfert en base (statut initial: pending).
     * @return l'id genere, ou -1 en cas d'echec (voir lastError()).
     */
    int create(const models::Transfer &transfer);

    std::optional<models::Transfer> findById(int id) const;
    std::vector<models::Transfer> findAll() const;
    std::vector<models::Transfer> findByUser(int userId) const;

    /**
     * @brief Met a jour uniquement le statut d'un transfert.
     */
    bool updateStatus(int id, models::TransferStatus status);

    /**
     * @brief Renseigne/ecrase le chemin local du fichier (voir models::Transfer::filePath()).
     *
     * Utilise notamment par core::TransferManager une fois la reception
     * terminee, quand le chemin de destination final n'est connu qu'a cet
     * instant (dossier de reception + nom de fichier).
     */
    bool updateFilePath(int id, const QString &filePath);

    bool remove(int id);

    QString lastError() const;

private:
    models::Transfer transferFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_TRANSFERREPOSITORY_H
