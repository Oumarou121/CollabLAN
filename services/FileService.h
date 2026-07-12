#ifndef SERVICES_FILESERVICE_H
#define SERVICES_FILESERVICE_H

#include <QObject>
#include <QString>
#include <QByteArray>

namespace services {

/**
 * @brief Operations sur le systeme de fichiers local (lecture/ecriture).
 */
class FileService : public QObject
{
    Q_OBJECT

public:
    explicit FileService(QObject *parent = nullptr);
    ~FileService();

    /// Lit le contenu d'un fichier texte
    Q_INVOKABLE QString readTextFile(const QString &filePath);

    /// Écrit du contenu dans un fichier texte
    Q_INVOKABLE bool writeTextFile(const QString &filePath, const QString &content);

    /// Lit le contenu binaire d'un fichier
    Q_INVOKABLE QByteArray readBinaryFile(const QString &filePath);

    /// Écrit du contenu binaire dans un fichier
    Q_INVOKABLE bool writeBinaryFile(const QString &filePath, const QByteArray &content);

    /// Vérifie si un fichier existe
    Q_INVOKABLE bool fileExists(const QString &filePath);

    /// Supprime un fichier
    Q_INVOKABLE bool deleteFile(const QString &filePath);

    /// Crée un répertoire
    Q_INVOKABLE bool createDirectory(const QString &dirPath);

    /// Vérifie si un répertoire existe
    Q_INVOKABLE bool directoryExists(const QString &dirPath);

    /// Retourne la taille d'un fichier en octets
    Q_INVOKABLE qint64 fileSize(const QString &filePath);

signals:
    void errorOccurred(const QString &errorString);
};

} // namespace services

#endif // SERVICES_FILESERVICE_H
