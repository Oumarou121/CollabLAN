#include "AudioService.h"

#include <QAudioSink>
#include <QDebug>
#include <QFile>
#include <QIODevice>
#include <QMediaDevices>
#include <QSettings>

#include <cstddef>
#include <cstring>
#include <string>

// QtAudio remplace QAudio a partir de Qt 6.6 : alias pour rester compilable
// avec un Qt6 plus ancien.
#if QT_VERSION < QT_VERSION_CHECK(6, 6, 0)
namespace QtAudio = QAudio;
#endif

namespace services {

// Peripherique de lecture "tire" par QAudioSink : fournit les octets PCM
// deja convertis au format de la sortie, en boucle infinie pour la
// sonnerie d'appel. Utilise uniquement le thread principal pour l'ecriture
// (setClip() n'est appele qu'apres QAudioSink::stop()).
class PcmPlaybackDevice : public QIODevice
{
public:
    explicit PcmPlaybackDevice(QObject *parent = nullptr)
        : QIODevice(parent)
    {
    }

    void setClip(const QByteArray &pcm, bool loop)
    {
        m_data = pcm;
        m_pos = 0;
        m_loop = loop;
    }

    bool atEnd() const override
    {
        return !m_loop && m_pos >= m_data.size();
    }

    qint64 bytesAvailable() const override
    {
        const qint64 remaining = m_data.isEmpty() ? 0 : (m_loop ? m_data.size() : m_data.size() - m_pos);
        return remaining + QIODevice::bytesAvailable();
    }

protected:
    qint64 readData(char *out, qint64 maxLen) override
    {
        if (m_data.isEmpty())
            return 0;

        qint64 written = 0;
        while (written < maxLen) {
            if (m_pos >= m_data.size()) {
                if (!m_loop)
                    break;
                m_pos = 0;
            }
            const qint64 chunk = qMin(maxLen - written, static_cast<qint64>(m_data.size()) - m_pos);
            std::memcpy(out + written, m_data.constData() + m_pos, static_cast<std::size_t>(chunk));
            m_pos += chunk;
            written += chunk;
        }
        return written;
    }

    qint64 writeData(const char *, qint64) override
    {
        return -1; // lecture seule
    }

private:
    QByteArray m_data;
    qint64 m_pos = 0;
    bool m_loop = false;
};

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

std::size_t channelIndex(AudioService::EventType type)
{
    return static_cast<std::size_t>(type);
}

// Silence ajoute apres chaque son : evite que le peripherique tronque la
// fin quand il vide son tampon.
constexpr int kTailSilenceMs = 60;

bool toPcmFormat(const QAudioFormat &format, pcm::OutputFormat &out)
{
    out.sampleRate = format.sampleRate();
    out.channels = format.channelCount();
    switch (format.sampleFormat()) {
    case QAudioFormat::UInt8: out.sampleType = pcm::SampleType::UInt8; return true;
    case QAudioFormat::Int16: out.sampleType = pcm::SampleType::Int16; return true;
    case QAudioFormat::Int32: out.sampleType = pcm::SampleType::Int32; return true;
    case QAudioFormat::Float: out.sampleType = pcm::SampleType::Float; return true;
    default: return false;
    }
}

QAudioFormat makeFormat(int sampleRate, int channels, QAudioFormat::SampleFormat sampleFormat)
{
    QAudioFormat format;
    format.setSampleRate(sampleRate);
    format.setChannelCount(channels);
    format.setSampleFormat(sampleFormat);
    return format;
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
    // soundEnabled/volume sont persistes : on charge les valeurs sauvegardees
    // avant toute lecture pour que le volume initial soit applique directement.
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

    // Decode les 3 variantes de chaque categorie (issue #56 + choix du son) :
    // previewSound() doit pouvoir jouer n'importe laquelle immediatement,
    // pas seulement celle actuellement selectionnee.
    for (EventType type : {EventType::Message, EventType::Transfer, EventType::Call}) {
        for (const QString &variantId : variantsFor(type)) {
            loadSound(type, variantId, resourcePathFor(type, variantId));
        }
    }

    // La sortie doit suivre le peripherique par defaut du systeme (casque
    // deconnecte, sortie HDMI/Bluetooth devenue "par defaut", etc.).
    m_mediaDevices = new QMediaDevices(this);
    connect(m_mediaDevices, &QMediaDevices::audioOutputsChanged, this, &AudioService::rebindAudioDevice);

    // Resout tout de suite le peripherique et son format : le log de
    // demarrage indique immediatement si la carte accepte son format prefere.
    ensureOutput();
}

AudioService::~AudioService()
{
    // Les QAudioSink lisent les PcmPlaybackDevice : on les detruit d'abord.
    releaseOutput();
}

void AudioService::loadSound(EventType type, const QString &variantId, const QString &resourcePath)
{
    QFile file(resourcePath);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[AudioService] ressource introuvable" << resourcePath;
        return;
    }
    const QByteArray raw = file.readAll();

    pcm::Clip clip;
    std::string error;
    if (!pcm::decodeWav(reinterpret_cast<const unsigned char *>(raw.constData()),
                        static_cast<std::size_t>(raw.size()), clip, &error)) {
        qWarning() << "[AudioService] impossible de decoder le son" << resourcePath
                   << "erreur:" << QString::fromStdString(error);
        return;
    }
    m_clips.insert(soundKey(type, variantId), std::move(clip));
}

QAudioFormat AudioService::chooseOutputFormat(const QAudioDevice &device)
{
    // Le format prefere du peripherique est, par definition, celui que le
    // mixeur de l'OS accepte sans conversion : c'est le premier choix (comme
    // VoiceAudioIO). Les autres ne servent que si preferredFormat() est
    // refuse ou inexploitable.
    const QAudioFormat preferred = device.preferredFormat();
    const QList<QAudioFormat> candidates = {
        preferred,
        makeFormat(48000, 2, QAudioFormat::Int16),
        makeFormat(44100, 2, QAudioFormat::Int16),
        makeFormat(48000, 2, QAudioFormat::Float),
        makeFormat(44100, 2, QAudioFormat::Float),
        makeFormat(48000, 1, QAudioFormat::Int16),
        makeFormat(44100, 1, QAudioFormat::Int16),
    };
    for (const QAudioFormat &candidate : candidates) {
        pcm::OutputFormat unused;
        if (candidate.isValid() && toPcmFormat(candidate, unused) && device.isFormatSupported(candidate))
            return candidate;
    }
    // Rien d'accepte : on tente quand meme le format prefere (le log de
    // startPlayback() montrera l'erreur du QAudioSink).
    return preferred;
}

bool AudioService::ensureOutput()
{
    if (m_outputReady)
        return true;

    const QAudioDevice device = QMediaDevices::defaultAudioOutput();
    if (device.isNull()) {
        qWarning() << "[AudioService] aucun peripherique de sortie audio par defaut : sons impossibles";
        return false;
    }

    const QAudioFormat preferred = device.preferredFormat();
    const QAudioFormat chosen = chooseOutputFormat(device);
    pcm::OutputFormat convertible;
    if (!chosen.isValid() || !toPcmFormat(chosen, convertible)) {
        qWarning() << "[AudioService] aucun format de sortie exploitable pour" << device.description();
        return false;
    }

    m_outputDevice = device;
    m_outputFormat = chosen;
    m_outputReady = true;

    // DIAGNOSTIC : ces lignes suffisent a comprendre un poste sans son (format
    // prefere refuse par la carte, nombre de canaux atypique, etc.).
    qInfo() << "[AudioService] sortie audio :" << device.description()
            << "| format prefere :" << preferred.sampleRate() << "Hz,"
            << preferred.channelCount() << "canaux (config" << static_cast<int>(preferred.channelConfig())
            << "), echantillon" << static_cast<int>(preferred.sampleFormat())
            << "accepte par la carte:" << device.isFormatSupported(preferred)
            << "| format utilise :" << chosen.sampleRate() << "Hz,"
            << chosen.channelCount() << "canaux, echantillon" << static_cast<int>(chosen.sampleFormat());
    return true;
}

void AudioService::destroySink(Channel &channel)
{
    if (!channel.sink)
        return;
    // QAudioSink emet stateChanged pendant sa destruction : sans cette
    // deconnexion, notre lambda de diagnostic relirait sink->error() sur un
    // objet en cours de destruction.
    QObject::disconnect(channel.sink, nullptr, this, nullptr);
    channel.sink->stop();
    delete channel.sink;
    channel.sink = nullptr;
}

void AudioService::releaseOutput()
{
    for (Channel &channel : m_channels)
        destroySink(channel);
    m_converted.clear();
    m_outputDevice = QAudioDevice();
    m_outputFormat = QAudioFormat();
    m_outputReady = false;
}

void AudioService::rebindAudioDevice()
{
    const bool wasRinging = m_callRinging;
    releaseOutput();

    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();
    qInfo() << "[AudioService] Peripherique de sortie par defaut change :"
            << outputDevice.description() << (outputDevice.isNull() ? "(aucun peripherique !)" : "");
    ensureOutput();

    // Une sonnerie en cours etait liee a l'ancien peripherique : on la
    // relance sur le nouveau plutot que de la laisser muette.
    if (wasRinging && m_soundEnabled)
        playSound(EventType::Call);
}

QByteArray AudioService::convertedFor(const QString &key)
{
    const auto cached = m_converted.constFind(key);
    if (cached != m_converted.constEnd())
        return cached.value();

    const auto clip = m_clips.constFind(key);
    pcm::OutputFormat format;
    if (clip == m_clips.constEnd() || !toPcmFormat(m_outputFormat, format))
        return QByteArray();

    const std::vector<unsigned char> bytes = pcm::convertClip(clip.value(), format, kTailSilenceMs);
    const QByteArray data(reinterpret_cast<const char *>(bytes.data()), static_cast<qsizetype>(bytes.size()));
    m_converted.insert(key, data);
    return data;
}

void AudioService::startPlayback(EventType type, const QString &variantId, bool loop)
{
    const QString key = soundKey(type, variantId);
    if (!m_clips.contains(key)) {
        qWarning() << "[AudioService] playSound : aucun son trouve pour" << key;
        return;
    }
    if (!ensureOutput())
        return;

    const QByteArray data = convertedFor(key);
    if (data.isEmpty()) {
        qWarning() << "[AudioService] playSound : conversion impossible pour" << key
                   << "vers" << m_outputFormat.sampleRate() << "Hz," << m_outputFormat.channelCount() << "canaux";
        return;
    }

    Channel &channel = m_channels[channelIndex(type)];
    if (!channel.device) {
        channel.device = new PcmPlaybackDevice(this);
        channel.device->open(QIODevice::ReadOnly);
    }

    // Un QAudioSink neuf a chaque lecture : les notifications sont rares, et
    // cela evite tout etat residuel d'un sink arrive en fin de flux (Idle).
    destroySink(channel);
    channel.sink = new QAudioSink(m_outputDevice, m_outputFormat, this);
    channel.sink->setVolume(m_volume);
    connect(channel.sink, &QAudioSink::stateChanged, this, [sink = channel.sink, key](QtAudio::State state) {
        qDebug() << "[AudioService] etat du lecteur pour" << key << ":" << static_cast<int>(state);
        if (sink->error() != QtAudio::NoError) {
            qWarning() << "[AudioService] erreur de lecture pour" << key
                       << "code:" << static_cast<int>(sink->error());
        }
    });

    channel.device->setClip(data, loop);

    qDebug() << "[AudioService] playSound : lecture de" << key
             << "volume:" << m_volume << "boucle:" << loop
             << "peripherique:" << m_outputDevice.description()
             << "format:" << m_outputFormat.sampleRate() << "Hz," << m_outputFormat.channelCount() << "canaux";

    // start(QIODevice*) est asynchrone : QAudioSink tire les donnees dans son
    // propre fil audio, donc aucun gel de l'UI (criteres de l'issue #56).
    channel.sink->start(channel.device);

    if (channel.sink->error() != QtAudio::NoError) {
        qWarning() << "[AudioService] playSound : echec du demarrage pour" << key
                   << "code:" << static_cast<int>(channel.sink->error());
    }

    if (type == EventType::Call)
        m_callRinging = loop;
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
    for (const Channel &channel : m_channels) {
        if (channel.sink)
            channel.sink->setVolume(m_volume);
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

    // Seule la sonnerie d'appel boucle tant que l'appel n'est pas traite.
    startPlayback(type, currentVariant(type), type == EventType::Call);
}

void AudioService::previewSound(services::AudioService::EventType type, const QString &variantId)
{
    // Ecoute volontaire d'une variante avant de la choisir : jouee une seule
    // fois (jamais en boucle, meme pour "call") et sans tenir compte de
    // soundEnabled, pour qu'on puisse comparer les sons meme interrupteur
    // "Sons actives" desactive.
    if (!variantsFor(type).contains(variantId))
        return;
    startPlayback(type, variantId, false);
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
    m_callRinging = false;
    Channel &channel = m_channels[channelIndex(EventType::Call)];
    if (channel.sink)
        channel.sink->stop();
}

} // namespace services
