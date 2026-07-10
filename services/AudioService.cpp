#include "AudioService.h"

#include <QDebug>
#include <QSoundEffect>
#include <QUrl>

namespace services {

AudioService::AudioService(QObject *parent)
    : QObject(parent)
{
    // Chargement des sons par type d'evenement (issue #56). Chaque
    // QSoundEffect est preload() des la construction pour que la
    // premiere lecture ne subisse pas le cout du decodage.
    loadSound(EventType::Message, QStringLiteral("qrc:/sounds/message.wav"));
    loadSound(EventType::Transfer, QStringLiteral("qrc:/sounds/transfer.wav"));
    loadSound(EventType::Call, QStringLiteral("qrc:/sounds/call.wav"));
}

AudioService::~AudioService() = default;

void AudioService::loadSound(EventType type, const QString &resourcePath)
{
    auto *effect = new QSoundEffect(this);
    effect->setSource(QUrl(resourcePath));
    effect->setVolume(m_volume);
    effect->setLoopCount(1);
    // Precharge le fichier pour eviter toute latence lors du premier play().

    connect(effect, &QSoundEffect::statusChanged, this, [effect, resourcePath]() {
        if (effect->status() == QSoundEffect::Error) {
            qWarning() << "AudioService : impossible de charger le son" << resourcePath;
        }
    });

    m_sounds.insert(type, effect);
}

void AudioService::setVolume(qreal volume)
{
    m_volume = qBound(0.0, volume, 1.0);
    for (auto *effect : std::as_const(m_sounds)) {
        effect->setVolume(m_volume);
    }
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

} // namespace services
