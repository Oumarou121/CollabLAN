#include "AudioService.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMediaDevices>
#include <QAudioDevice>
#include <QAudioOutput>
#include <QMediaPlayer>
#include <QSettings>
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

    // Chaque QAudioOutput doit suivre le peripherique de sortie par
    // defaut du systeme (casque deconnecte, sortie HDMI/Bluetooth
    // devenue "par defaut" alors qu'elle est eteinte, etc.) -- sans quoi
    // un son peut rester silencieusement lie a un peripherique qui n'est
    // plus celui utilise par l'OS. On lie explicitement chaque sortie au
    // peripherique par defaut courant (loadSound()), et on refait cette
    // liaison sur toutes les sorties a chaque changement signale par l'OS.
    m_mediaDevices = new QMediaDevices(this);
    connect(m_mediaDevices, &QMediaDevices::audioOutputsChanged, this, &AudioService::rebindAudioDevice);
}

void AudioService::rebindAudioDevice()
{
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();
    qInfo() << "[AudioService] Peripherique de sortie par defaut change :"
             << outputDevice.description() << (outputDevice.isNull() ? "(aucun peripherique !)" : "");
    for (const NotificationSound &sound : std::as_const(m_sounds)) {
        sound.output->setDevice(outputDevice);
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

    // QAudioOutput ne peut pas etre partage entre plusieurs QMediaPlayer :
    // chaque son precharge a le sien, comme chaque QSoundEffect avait
    // auparavant son propre backend.
    auto *output = new QAudioOutput(this);
    // Liaison explicite au peripherique de sortie par defaut courant (cf.
    // rebindAudioDevice()) plutot que de compter sur une resolution
    // implicite qui peut ne pas suivre un changement de peripherique par
    // defaut sur certains postes.
    output->setDevice(QMediaDevices::defaultAudioOutput());
    output->setVolume(m_volume);

    auto *player = new QMediaPlayer(this);
    player->setAudioOutput(output);
    player->setSource(source);
    player->setLoops(QMediaPlayer::Once);
    // Precharge le fichier pour eviter toute latence lors du premier play().

    connect(player, &QMediaPlayer::errorOccurred, this,
            [source](QMediaPlayer::Error error, const QString &errorString) {
                qWarning() << "AudioService : impossible de charger le son" << source
                           << "erreur:" << error << errorString;
            });

    m_sounds.insert(soundKey(type, variantId), NotificationSound{player, output});
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
    for (const NotificationSound &sound : std::as_const(m_sounds)) {
        sound.output->setVolume(m_volume);
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

    const NotificationSound sound = m_sounds.value(soundKey(type, currentVariant(type)));
    if (!sound.player) {
        qWarning() << "[AudioService] playSound : aucun son trouve pour"
                   << soundKey(type, currentVariant(type));
        return;
    }
    if (sound.player->error() != QMediaPlayer::NoError) {
        qWarning() << "[AudioService] playSound : lecteur en erreur pour"
                   << soundKey(type, currentVariant(type)) << "source:" << sound.player->source()
                   << "erreur:" << sound.player->errorString();
        return;
    }

    // Seule la sonnerie d'appel doit boucler tant que l'appel n'est pas
    // traite ; previewSound() peut avoir laisse loops a Once sur ce meme
    // lecteur lors d'une ecoute prealable, donc on le reimpose explicitement
    // ici a chaque lecture reelle plutot qu'une seule fois a la creation.
    sound.player->setLoops(type == EventType::Call ? QMediaPlayer::Infinite : QMediaPlayer::Once);
    // QMediaPlayer::play() repart de la position courante, pas du debut :
    // sans ce reset, rejouer un son deja arrive a la fin ne produirait rien.
    sound.player->setPosition(0);

    qDebug() << "[AudioService] playSound : lecture de" << soundKey(type, currentVariant(type))
             << "mediaStatus:" << sound.player->mediaStatus() << "volume:" << sound.output->volume()
             << "playbackState (avant play):" << sound.player->playbackState()
             << "isMuted:" << sound.output->isMuted()
             << "peripherique:" << sound.output->device().description();

    // QMediaPlayer::play() est asynchrone : la lecture est geree par le
    // backend audio de Qt et ne bloque jamais le thread appelant (donc
    // pas de gel de l'UI, cf. criteres d'acceptation de l'issue #56).
    sound.player->play();
}

void AudioService::previewSound(services::AudioService::EventType type, const QString &variantId)
{
    // Ecoute volontaire d'une variante avant de la choisir : jouee une
    // seule fois (jamais en boucle, meme pour "call") et sans tenir
    // compte de soundEnabled, pour qu'on puisse comparer les sons meme
    // interrupteur "Sons actives" desactive.
    const NotificationSound sound = m_sounds.value(soundKey(type, variantId));
    if (!sound.player || sound.player->error() != QMediaPlayer::NoError) {
        return;
    }
    sound.player->setLoops(QMediaPlayer::Once);
    sound.player->setPosition(0);
    sound.player->play();
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
    const NotificationSound sound = m_sounds.value(soundKey(EventType::Call, currentVariant(EventType::Call)));
    if (sound.player) {
        sound.player->stop();
    }
}

} // namespace services