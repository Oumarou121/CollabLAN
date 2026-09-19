#include "AudioService.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMediaDevices>
#include <QAudioDevice>
#include <QSettings>
#include <QSoundEffect>
#include <QStandardPaths>
#include <QUrl>

namespace services {

namespace {
// Identifiants de variantes disponibles par categorie, dans l'ordre
// d'affichage voulu pour SettingsView. Le premier de chaque liste est la
// valeur par defaut utilisee si aucun reglage n'est encore enregistre (ou
// si une valeur invalide/obsolete est trouvee dans QSettings).
QStringList variantsFor(AudioService::EventType type)
{
    switch (type) {
    case AudioService::EventType::Message:
        return {QStringLiteral("soft"), QStringLiteral("pop"), QStringLiteral("bell")};
    case AudioService::EventType::Transfer:
        return {QStringLiteral("rising"), QStringLiteral("ding"), QStringLiteral("done")};
    case AudioService::EventType::Call:
        return {QStringLiteral("classic"), QStringLiteral("soft"), QStringLiteral("upbeat")};
    }
    return {};
}

QString prefixFor(AudioService::EventType type)
{
    switch (type) {
    case AudioService::EventType::Message:  return QStringLiteral("message");
    case AudioService::EventType::Transfer: return QStringLiteral("transfer");
    case AudioService::EventType::Call:     return QStringLiteral("call");
    }
    return QString();
}

QString settingsKeyFor(AudioService::EventType type)
{
    switch (type) {
    case AudioService::EventType::Message:  return QStringLiteral("audio/messageSound");
    case AudioService::EventType::Transfer: return QStringLiteral("audio/transferSound");
    case AudioService::EventType::Call:     return QStringLiteral("audio/callSound");
    }
    return QString();
}
} // namespace

QString AudioService::resourcePathFor(EventType type, const QString &variantId)
{
    return QStringLiteral(":/sounds/%1_%2.wav").arg(prefixFor(type), variantId);
}

QString AudioService::soundKey(EventType type, const QString &variantId)
{
    return prefixFor(type) + QLatin1Char(':') + variantId;
}

QString AudioService::currentVariant(EventType type) const
{
    switch (type) {
    case EventType::Message:  return m_messageSound;
    case EventType::Transfer: return m_transferSound;
    case EventType::Call:     return m_callSound;
    }
    return QString();
}

QStringList AudioService::soundVariants(services::AudioService::EventType type) const
{
    return variantsFor(type);
}

AudioService::AudioService(QObject *parent)
    : QObject(parent)
{
    // CORRECTIF : soundEnabled/volume n'etaient jamais persistes -- reglages
    // remis a true/1.0 a chaque redemarrage de l'application, meme apres
    // que l'utilisateur les ait changes depuis Parametres > Sons &
    // notifications. On charge les valeurs sauvegardees avant de creer les
    // QSoundEffect (pour que le volume initial soit applique directement).
    {
        QSettings settings;
        m_soundEnabled = settings.value(QStringLiteral("audio/soundEnabled"), true).toBool();
        m_volume = qBound(0.0, settings.value(QStringLiteral("audio/volume"), 1.0).toReal(), 1.0);

        // Chaque categorie propose 3 variantes de son au choix (issue
        // "choix du son") ; on valide la valeur enregistree contre la
        // liste actuelle pour ne jamais se retrouver avec un identifiant
        // obsolete (ex. ancien reglage d'une version anterieure) qui ne
        // correspondrait a aucun son charge.
        auto loadVariant = [&settings](EventType type) {
            const QStringList valid = variantsFor(type);
            const QString stored = settings.value(settingsKeyFor(type), valid.first()).toString();
            return valid.contains(stored) ? stored : valid.first();
        };
        m_messageSound = loadVariant(EventType::Message);
        m_transferSound = loadVariant(EventType::Transfer);
        m_callSound = loadVariant(EventType::Call);
    }

    // Precharge les 3 variantes de chaque categorie (issue #56 + choix du
    // son) : previewSound() doit pouvoir jouer n'importe laquelle
    // immediatement, pas seulement celle actuellement selectionnee.
    for (EventType type : {EventType::Message, EventType::Transfer, EventType::Call}) {
        for (const QString &variantId : variantsFor(type)) {
            loadSound(type, variantId, resourcePathFor(type, variantId));
        }
    }

    // DIAGNOSTIC (postes ou aucun son de notification ne s'entend malgre
    // "Sons actives" coche) : QSoundEffect est cense suivre automatiquement
    // le peripherique de sortie par defaut du systeme, mais rien dans ce
    // code ne le forcait explicitement ni ne reagissait a un changement de
    // peripherique par defaut (casque deconnecte, sortie HDMI/Bluetooth
    // devenue "par defaut" alors qu'elle est eteinte, etc.) -- un scenario
    // ou QSoundEffect reste en status() Ready et "joue" sans jamais lever
    // d'erreur, tout en ne produisant aucun son audible. On lie
    // explicitement chaque effet au peripherique de sortie par defaut
    // courant (loadSound()), et on refait cette liaison sur tous les
    // effets a chaque changement de peripherique de sortie signale par
    // l'OS.
    m_mediaDevices = new QMediaDevices(this);
    connect(m_mediaDevices, &QMediaDevices::audioOutputsChanged, this, &AudioService::rebindAudioDevice);
}

void AudioService::rebindAudioDevice()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();
    qInfo() << "[AudioService] Peripherique de sortie par defaut change :"
             << outputDevice.description() << (outputDevice.isNull() ? "(aucun peripherique !)" : "");
    for (auto *effect : std::as_const(m_sounds)) {
        effect->setAudioDevice(outputDevice);
    }
#endif
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

    // Ne recopie que si absent OU si le contenu embarque a change (mise a
    // jour de l'application avec de nouveaux sons) : comparer uniquement
    // l'existence du fichier local faisait qu'un son mis a jour dans les
    // ressources restait invisible indefiniment pour une installation
    // existante, puisque le cache d'une version precedente gardait
    // toujours la priorite.
    QFile resourceFile(resourcePath);
    if (!resourceFile.open(QIODevice::ReadOnly)) {
        qWarning() << "AudioService : ressource introuvable" << resourcePath;
        return QString();
    }
    const QByteArray resourceData = resourceFile.readAll();

    bool needsWrite = true;
    if (QFile::exists(localPath)) {
        QFile existingFile(localPath);
        if (existingFile.open(QIODevice::ReadOnly)) {
            needsWrite = existingFile.readAll() != resourceData;
        }
    }

    if (needsWrite) {
        QFile localFile(localPath);
        if (!localFile.open(QIODevice::WriteOnly)) {
            qWarning() << "AudioService : impossible d'ecrire" << localPath;
            return QString();
        }
        localFile.write(resourceData);
    }

    return localPath;
}

void AudioService::loadSound(EventType type, const QString &variantId, const QString &resourcePath)
{
    const QString localPath = extractToLocalFile(resourcePath);
    const QUrl source = localPath.isEmpty() ? QUrl(resourcePath) : QUrl::fromLocalFile(localPath);

    auto *effect = new QSoundEffect(this);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    // Liaison explicite au peripherique de sortie par defaut courant (cf.
    // rebindAudioDevice()) plutot que de compter sur une resolution
    // implicite qui peut ne pas suivre un changement de peripherique par
    // defaut sur certains postes.
    effect->setAudioDevice(QMediaDevices::defaultAudioOutput());
#endif
    effect->setSource(source);
    effect->setVolume(m_volume);
    effect->setLoopCount(1);
    // Precharge le fichier pour eviter toute latence lors du premier play().

    connect(effect, &QSoundEffect::statusChanged, this, [effect, source]() {
        if (effect->status() == QSoundEffect::Error) {
            qWarning() << "AudioService : impossible de charger le son" << source;
        }
    });

    m_sounds.insert(soundKey(type, variantId), effect);
}

void AudioService::setSoundEnabled(bool enabled)
{
    if (m_soundEnabled == enabled)
        return;
    m_soundEnabled = enabled;
    QSettings().setValue(QStringLiteral("audio/soundEnabled"), m_soundEnabled);
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
    QSettings().setValue(QStringLiteral("audio/volume"), m_volume);
    emit volumeChanged();
}

void AudioService::setMessageSound(const QString &variantId)
{
    if (m_messageSound == variantId || !variantsFor(EventType::Message).contains(variantId))
        return;
    m_messageSound = variantId;
    QSettings().setValue(settingsKeyFor(EventType::Message), m_messageSound);
    emit messageSoundChanged();
}

void AudioService::setTransferSound(const QString &variantId)
{
    if (m_transferSound == variantId || !variantsFor(EventType::Transfer).contains(variantId))
        return;
    m_transferSound = variantId;
    QSettings().setValue(settingsKeyFor(EventType::Transfer), m_transferSound);
    emit transferSoundChanged();
}

void AudioService::setCallSound(const QString &variantId)
{
    if (m_callSound == variantId || !variantsFor(EventType::Call).contains(variantId))
        return;
    m_callSound = variantId;
    QSettings().setValue(settingsKeyFor(EventType::Call), m_callSound);
    emit callSoundChanged();
}

void AudioService::playSound(services::AudioService::EventType type)
{
    if (!m_soundEnabled) {
        qDebug() << "[AudioService] playSound ignore : sons desactives";
        return;
    }

    QSoundEffect *effect = m_sounds.value(soundKey(type, currentVariant(type)));
    if (!effect) {
        qWarning() << "[AudioService] playSound : aucun QSoundEffect trouve pour"
                   << soundKey(type, currentVariant(type));
        return;
    }
    if (effect->status() == QSoundEffect::Error) {
        qWarning() << "[AudioService] playSound : QSoundEffect en erreur pour"
                   << soundKey(type, currentVariant(type)) << "source:" << effect->source();
        return;
    }

    // Seule la sonnerie d'appel doit boucler tant que l'appel n'est pas
    // traite ; previewSound() peut avoir laisse loopCount a 1 sur ce meme
    // effet lors d'une ecoute prealable, donc on le reimpose explicitement
    // ici a chaque lecture reelle plutot qu'une seule fois a la creation.
    effect->setLoopCount(type == EventType::Call ? QSoundEffect::Infinite : 1);

    qDebug() << "[AudioService] playSound : lecture de" << soundKey(type, currentVariant(type))
             << "status:" << effect->status() << "volume:" << effect->volume()
             << "isPlaying (avant play):" << effect->isPlaying()
             << "isMuted:" << effect->isMuted()
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
             << "peripherique:" << effect->audioDevice().description()
#endif
             ;

    // QSoundEffect::play() est asynchrone : la lecture est geree par le
    // backend audio de Qt et ne bloque jamais le thread appelant (donc
    // pas de gel de l'UI, cf. criteres d'acceptation de l'issue #56).
    effect->play();
}

void AudioService::previewSound(services::AudioService::EventType type, const QString &variantId)
{
    // Ecoute volontaire d'une variante avant de la choisir : jouee une
    // seule fois (jamais en boucle, meme pour "call") et sans tenir
    // compte de soundEnabled, pour qu'on puisse comparer les sons meme
    // interrupteur "Sons actives" desactive.
    QSoundEffect *effect = m_sounds.value(soundKey(type, variantId));
    if (!effect || effect->status() == QSoundEffect::Error) {
        return;
    }
    effect->setLoopCount(1);
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
    QSoundEffect *effect = m_sounds.value(soundKey(EventType::Call, currentVariant(EventType::Call)));
    if (effect) {
        effect->stop();
    }
}

} // namespace services