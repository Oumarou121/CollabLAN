#ifndef NETWORK_SYNCPROTOCOL_H
#define NETWORK_SYNCPROTOCOL_H

#include <QJsonObject>
#include <QString>
#include <optional>

namespace network {

/**
 * @brief Messages du protocole de synchronisation des dossiers partages
 * (Phase 5 de "Shared Folder").
 *
 * Tous les messages sont des objets JSON plats, encodes en UTF-8 et
 * separes sur le flux TCP par un saut de ligne ('\n', aucun contenu
 * applicatif ne pouvant en contenir puisque QJsonDocument::Compact ne
 * produit pas de retours a la ligne). Chaque message porte un champ
 * "type" identifiant sa nature.
 */
namespace SyncProtocol {

enum class MessageType {
    Hello,
    SyncRequest,
    SyncResponse,
    FileInfo,
    FileRequest,
    FileChunk,
    DeleteFile,
    RenameFile,
    SyncFinished,
    Unknown
};

QString messageTypeToString(MessageType type);
MessageType messageTypeFromString(const QString &value);

// --- Construction des messages ---------------------------------------

// Premier message envoye a la connexion : identifie le poste emetteur.
QJsonObject makeHello(const QString &machineId, const QString &machineName);

// Demande la liste des fichiers connus d'un dossier partage (comparaison
// avant telechargement des fichiers manquants, Phase 6).
QJsonObject makeSyncRequest(const QString &folder);

// Reponse a SYNC_REQUEST : liste des fichiers connus (voir buildFileInfoArray).
QJsonObject makeSyncResponse(const QString &folder, const QJsonArray &files);

// Notifie une creation/modification (ou, avec deleted=true, redondant
// avec DELETE_FILE pour la reprise sur SYNC_RESPONSE).
QJsonObject makeFileInfo(const QString &folder,
                         const QString &path,
                         const QString &hash,
                         qint64 size,
                         int version);

QJsonObject makeFileRequest(const QString &folder, const QString &path, qint64 offset = 0);

QJsonObject makeFileChunk(const QString &folder,
                          const QString &path,
                          qint64 offset,
                          const QByteArray &data,
                          bool isLast);

QJsonObject makeDeleteFile(const QString &folder, const QString &path, int version);

QJsonObject makeRenameFile(const QString &folder,
                           const QString &oldPath,
                           const QString &newPath,
                           int version);

QJsonObject makeSyncFinished(const QString &folder);

// --- Serialisation / trame ---------------------------------------------

// Serialise en une ligne (JSON compact + '\n'), prete a etre ecrite sur
// un QTcpSocket.
QByteArray serialize(const QJsonObject &message);

// Extrait un message JSON complet du buffer (jusqu'au premier '\n'
// disponible) ; consomme les octets correspondants de buffer et renvoie
// le message parse, ou std::nullopt si aucune ligne complete n'est
// encore disponible.
std::optional<QJsonObject> takeNextMessage(QByteArray &buffer);

} // namespace SyncProtocol

} // namespace network

#endif // NETWORK_SYNCPROTOCOL_H
