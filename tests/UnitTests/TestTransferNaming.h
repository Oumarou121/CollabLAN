#ifndef TESTS_TESTTRANSFERNAMING_H
#define TESTS_TESTTRANSFERNAMING_H

#include <QByteArray>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QString>

/// Nom du fichier temporaire ecrit pendant une reception, tel que le calcule TransferService.
///
/// Ce nom depend du TRANSFERT LOGIQUE (qui envoie quoi a qui, et de quelle taille), pas de la
/// connexion : c'est ce qui permet de reprendre un transfert coupe. Il portait auparavant un
/// identifiant de connexion tire au hasard, regenere a chaque tentative -- les octets deja recus
/// n'etaient alors jamais retrouves et tout repartait de zero.
///
/// Les tests qui simulent une coupure doivent fabriquer le fichier partiel sous ce nom exact.
inline QString testPartialFileName(const QString &senderMachineId, const QString &senderUuid,
                                    const QString &recipientUuid, const QString &fileName,
                                    qint64 fileSize)
{
    const QByteArray identity = senderMachineId.toUtf8() + '\0' + senderUuid.toUtf8() + '\0'
        + recipientUuid.toUtf8() + '\0' + fileName.toUtf8() + '\0' + QByteArray::number(fileSize);
    return fileName + QStringLiteral(".part-")
        + QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex().left(16));
}

/// Fichier partiel present dans `dir` (chaine vide s'il n'y en a aucun).
///
/// Pour les tests qui verifient seulement qu'une reception a ete interrompue : ils n'ont pas a
/// reconstruire le nom exact, seulement a constater qu'un fichier temporaire subsiste.
inline QString testFindPartialFile(const QString &dir)
{
    QDirIterator it(dir, QStringList{QStringLiteral("*.part-*")}, QDir::Files, QDirIterator::Subdirectories);
    return it.hasNext() ? it.next() : QString();
}

#endif // TESTS_TESTTRANSFERNAMING_H
