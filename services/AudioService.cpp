#include "AudioService.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSoundEffect>
#include <QStandardPaths>
#include <QUrl>

namespace services {

AudioService::AudioService(QObject *parent)
    : QObject(parent)
{
    // Chargement des sons par type d'evenement (issue #56). Chaque
    // QSoundEffect est preload() des la construction pour que la
    // premiere lecture ne subisse pas le cout du decodage.
    loadSound(EventType::Message, QStringLiteral(":/sounds/message.wav"));
    loadSound(EventType::Transfer, QStringLiteral(":/sounds/transfer.wav"));
    loadSound(EventType::Call, QStringLiteral(":/sounds/call.wav"));

    // Contrairement aux sons message/transfert (notifications ponctuelles,
    // une seule lecture), la sonnerie d'appel entrant doit se repeter tant
    // que l'appel n'a pas ete traite (decroche/refuse/raccroche par
    // l'appelant) - sinon elle ne sonne qu'une fois et l'appel devient
    // silencieux alors qu'il continue de sonner a l'ecran. La lecture est
    // arretee explicitement par stopCallSound() (cf. Application.cpp, des
    // que l'etat de l'appel quitte "Ringing").
    if (QSoundEffect *callEffect = m_sounds.value(EventType::Call)) {
        callEffect->setLoopCount(QSoundEffect::Infinite);
    }
}

AudioService::~AudioService() = default;

QString AudioService::extractToLocalFile(const QString &resourcePath)
{
    // Le backend FFmpeg de Qt Multimedia (utilise notamment sous Windows)
    // echoue parfois a decoder un fichier lu directement depuis les
    // ressources Qt (qrc:/...), meme quand le WAV source est parfaitement
    // valide (QSoundEffect: Error decoding source). Contournement connu :
    // extraire le son vers un vrai fichier sur disque une seule fois, puis
    // charger QSoundEffect depuis ce chemin local plutot que depuis qrc.
    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                              + QStringLiteral("/sounds");
    QDir().mkpath(cacheDir);

    const QString fileName = QFileInfo(resourcePath).fileName();
    const QString localPath = cacheDir + QLatin1Char('/') + fileName;

    // Ne recopie pas si deja present (evite une ecriture disque a chaque
    // demarrage) : le contenu embarque dans le binaire ne change pas hors
    // mise a jour de l'application.
    if (!QFile::exists(localPath)) {
        QFile resourceFile(resourcePath);
        if (!resourceFile.open(QIODevice::ReadOnly)) {
            qWarning() << "AudioService : ressource introuvable" << resourcePath;
            return QString();
        }
        QFile localFile(localPath);
        if (!localFile.open(QIODevice::WriteOnly)) {
            qWarning() << "AudioService : impossible d'ecrire" << localPath;
            return QString();
        }
        localFile.write(resourceFile.readAll());
    }

    return localPath;
}

void AudioService::loadSound(EventType type, const QString &resourcePath)
{
    const QString localPath = extractToLocalFile(resourcePath);
    const QUrl source = localPath.isEmpty() ? QUrl(resourcePath) : QUrl::fromLocalFile(localPath);

    auto *effect = new QSoundEffect(this);
    effect->setSource(source);
    effect->setVolume(m_volume);
    effect->setLoopCount(1);
    // Precharge le fichier pour eviter toute latence lors du premier play().

    connect(effect, &QSoundEffect::statusChanged, this, [effect, source]() {
        if (effect->status() == QSoundEffect::Error) {
            qWarning() << "AudioService : impossible de charger le son" << source;
        }
    });

    m_sounds.insert(type, effect);
}

void AudioService::setSoundEnabled(bool enabled)
{
    if (m_soundEnabled == enabled)
        return;
    m_soundEnabled = enabled;
    emit soundEnabledChanged();
}

void AudioService::setVolume(qreal volume)
{
    const qreal clamped = qBound(0.0, volume, 1.0);
    if (qFuzzyCompare(m_volume, clamped))
        return;
    m_volume = clamped;
    for (auto *effect : std::as_const(m_sounds)) {
        effect->setVolume(m_volume);
    }
    emit volumeChanged();
}

void AudioService::playSound(services::AudioService::EventType type)
{
    if (!m_soundEnabled) {
        return;
    }

    auto it = m_sounds.constFind(type);
    if (it == m_sounds.constEnd()) {
        qWarning() << "AudioService : aucun son enregistre pour ce type d'evenement";
        return;
    }

    QSoundEffect *effect = it.value();
    if (effect->status() == QSoundEffect::Error) {
        return;
    }

    // QSoundEffect::play() est asynchrone : la lecture est geree par le
    // backend audio de Qt et ne bloque jamais le thread appelant (donc
    // pas de gel de l'UI, cf. criteres d'acceptation de l'issue #56).
    effect->play();
}

void AudioService::playMessageSound()
{
    playSound(EventType::Message);
}

void AudioService::playTransferSound()
{
    playSound(EventType::Transfer);
}

void AudioService::playCallSound()
{
    playSound(EventType::Call);
}

void AudioService::stopCallSound()
{
    auto it = m_sounds.constFind(EventType::Call);
    if (it != m_sounds.constEnd()) {
        it.value()->stop();
    }
}

} // namespace services