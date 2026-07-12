#ifndef SERVICES_FILEHASHER_H
#define SERVICES_FILEHASHER_H

#include <QString>

namespace services {

/**
 * @brief Utilitaires de hachage de fichiers, utilises par core::SyncEngine
 * pour detecter les modifications et par core::ConflictResolver pour
 * comparer une version locale et une version distante.
 */
namespace FileHasher {

// Empreinte SHA-256 du contenu du fichier (chaine hexadecimale), ou une
// chaine vide si le fichier ne peut pas etre ouvert.
QString hashFile(const QString &absoluteFilePath);

} // namespace FileHasher

} // namespace services

#endif // SERVICES_FILEHASHER_H
