#include "FileService.h"

#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QFileInfo>
#include <QDebug>

namespace services {

FileService::FileService(QObject *parent)
    : QObject(parent)
{
}

FileService::~FileService()
{
}

QString FileService::readTextFile(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Impossible d'ouvrir le fichier en lecture : %1").arg(filePath));
        return QString();
    }

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);
    const QString content = in.readAll();
    file.close();

    return content;
}

bool FileService::writeTextFile(const QString &filePath, const QString &content)
{
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Impossible d'ouvrir le fichier en écriture : %1").arg(filePath));
        return false;
    }

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << content;
    file.close();

    return true;
}

QByteArray FileService::readBinaryFile(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit errorOccurred(tr("Impossible d'ouvrir le fichier binaire en lecture : %1").arg(filePath));
        return QByteArray();
    }

    const QByteArray content = file.readAll();
    file.close();

    return content;
}

bool FileService::writeBinaryFile(const QString &filePath, const QByteArray &content)
{
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit errorOccurred(tr("Impossible d'ouvrir le fichier binaire en écriture : %1").arg(filePath));
        return false;
    }

    file.write(content);
    file.close();

    return true;
}

bool FileService::fileExists(const QString &filePath)
{
    return QFile::exists(filePath);
}

bool FileService::deleteFile(const QString &filePath)
{
    if (!QFile::exists(filePath)) {
        return true; // Déjà supprimé
    }

    if (!QFile::remove(filePath)) {
        emit errorOccurred(tr("Impossible de supprimer le fichier : %1").arg(filePath));
        return false;
    }

    return true;
}

bool FileService::createDirectory(const QString &dirPath)
{
    QDir dir;
    if (!dir.mkpath(dirPath)) {
        emit errorOccurred(tr("Impossible de créer le répertoire : %1").arg(dirPath));
        return false;
    }
    return true;
}

bool FileService::directoryExists(const QString &dirPath)
{
    QDir dir(dirPath);
    return dir.exists();
}

qint64 FileService::fileSize(const QString &filePath)
{
    QFileInfo info(filePath);
    if (!info.exists()) {
        return -1;
    }
    return info.size();
}

} // namespace services
