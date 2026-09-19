#include "VoiceAudioIO.h"

#include <QAudioSource>
#include <QAudioSink>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QAudioFormat>
#include <QIODevice>
#include <QDebug>
#include <QVector>
#include <QtGlobal>

#include <array>
#include <cstring>

namespace network {

// ---------------------------------------------------------------------
// Codec G.711 mu-law (RFC 3551 / ITU-T G.711). Implementation autonome,
// sans dependance externe : la table de correspondance est generee au
// premier appel puis reutilisee (cout negligeable, format telephonique
// choisi precisement pour eviter d'avoir a embarquer/lier libopus).
// ---------------------------------------------------------------------
namespace {

constexpr int kMuLawBias = 0x84;
constexpr int kMuLawClip = 32635;

std::uint8_t linearToMuLawSample(std::int16_t sample)
{
    int sign = (sample >> 8) & 0x80;
    if (sign != 0) {
        sample = static_cast<std::int16_t>(-sample);
    }
    if (sample > kMuLawClip) {
        sample = kMuLawClip;
    }
    sample += kMuLawBias;

    int exponent = 7;
    for (int mask = 0x4000; (sample & mask) == 0 && exponent > 0; mask >>= 1) {
        --exponent;
    }
    const int mantissa = (sample >> (exponent + 3)) & 0x0F;
    const std::uint8_t muLawByte = static_cast<std::uint8_t>(~(sign | (exponent << 4) | mantissa));
    return muLawByte;
}

std::int16_t muLawToLinearSample(std::uint8_t muLawByte)
{
    muLawByte = static_cast<std::uint8_t>(~muLawByte);
    const int sign = muLawByte & 0x80;
    const int exponent = (muLawByte >> 4) & 0x07;
    const int mantissa = muLawByte & 0x0F;

    int sample = ((mantissa << 3) + kMuLawBias) << exponent;
    sample -= kMuLawBias;
    return static_cast<std::int16_t>(sign != 0 ? -sample : sample);
}

} // namespace

// ---------------------------------------------------------------------
// Conversion de format audio (issue voix : "audio desactive" quand le
// peripherique ne supporte pas nativement 8kHz/mono/16bits).
//
// Beaucoup de peripheriques Windows (WASAPI, ex: "Realtek(R) Audio" des
// logs) refusent purement et simplement un format personnalise comme le
// telephonique 8kHz/mono/16bits via isFormatSupported() -- meme un
// fallback a 44.1/48kHz EN MONO peut echouer, la plupart des cartes son
// grand public n'exposant qu'un flux stereo natif. Le code precedent
// abandonnait alors completement l'audio de l'appel des que ces
// tentatives echouaient.
//
// Plutot que d'exiger que le peripherique parle nativement notre format
// telephonique, on capture/lit desormais le peripherique dans SON PROPRE
// format prefere (preferredFormat(), quasi toujours accepte -- c'est le
// format natif du mixeur), et on convertit nous-memes en logiciel :
//   - a la capture : downmix vers mono, puis reechantillonnage vers 8kHz,
//     puis conversion de l'echantillon vers Int16 si besoin (Float est
//     frequent en partage WASAPI) -- exactement le format que le reste du
//     pipeline (encodeMuLaw, RTP) attend deja, sans aucun changement cote
//     VoiceService.
//   - a la lecture : chemin inverse (Int16 mono 8kHz reçu/decode -> format
//     du peripherique de sortie).
namespace {

QVector<float> toFloatSamples(const QByteArray &pcm, QAudioFormat::SampleFormat sampleFormat)
{
    QVector<float> out;
    if (sampleFormat == QAudioFormat::Int16) {
        const int count = pcm.size() / 2;
        out.resize(count);
        const auto *src = reinterpret_cast<const std::int16_t *>(pcm.constData());
        for (int i = 0; i < count; ++i) {
            out[i] = static_cast<float>(src[i]) / 32768.0f;
        }
    } else if (sampleFormat == QAudioFormat::Float) {
        const int count = pcm.size() / 4;
        out.resize(count);
        std::memcpy(out.data(), pcm.constData(), static_cast<size_t>(count) * sizeof(float));
    } else if (sampleFormat == QAudioFormat::UInt8) {
        const int count = pcm.size();
        out.resize(count);
        const auto *src = reinterpret_cast<const std::uint8_t *>(pcm.constData());
        for (int i = 0; i < count; ++i) {
            out[i] = (static_cast<float>(src[i]) - 128.0f) / 128.0f;
        }
    } else if (sampleFormat == QAudioFormat::Int32) {
        const int count = pcm.size() / 4;
        out.resize(count);
        const auto *src = reinterpret_cast<const std::int32_t *>(pcm.constData());
        for (int i = 0; i < count; ++i) {
            out[i] = static_cast<float>(src[i]) / 2147483648.0f;
        }
    }
    return out;
}

QByteArray fromFloatSamplesInt16(const QVector<float> &samples)
{
    QByteArray out;
    out.resize(samples.size() * 2);
    auto *dst = reinterpret_cast<std::int16_t *>(out.data());
    for (int i = 0; i < samples.size(); ++i) {
        float v = samples[i] * 32768.0f;
        v = qBound(-32768.0f, v, 32767.0f);
        dst[i] = static_cast<std::int16_t>(v);
    }
    return out;
}

QByteArray fromFloatSamplesFormat(const QVector<float> &samples, QAudioFormat::SampleFormat sampleFormat)
{
    if (sampleFormat == QAudioFormat::Int16) {
        return fromFloatSamplesInt16(samples);
    }
    if (sampleFormat == QAudioFormat::Float) {
        QByteArray out;
        out.resize(samples.size() * 4);
        std::memcpy(out.data(), samples.constData(), static_cast<size_t>(samples.size()) * sizeof(float));
        return out;
    }
    if (sampleFormat == QAudioFormat::UInt8) {
        QByteArray out;
        out.resize(samples.size());
        auto *dst = reinterpret_cast<std::uint8_t *>(out.data());
        for (int i = 0; i < samples.size(); ++i) {
            const float v = qBound(-1.0f, samples[i], 1.0f);
            dst[i] = static_cast<std::uint8_t>((v * 128.0f) + 128.0f);
        }
        return out;
    }
    if (sampleFormat == QAudioFormat::Int32) {
        QByteArray out;
        out.resize(samples.size() * 4);
        auto *dst = reinterpret_cast<std::int32_t *>(out.data());
        for (int i = 0; i < samples.size(); ++i) {
            const float v = qBound(-1.0f, samples[i], 1.0f);
            dst[i] = static_cast<std::int32_t>(v * 2147483647.0f);
        }
        return out;
    }
    return QByteArray();
}

QVector<float> downmixToMono(const QVector<float> &interleaved, int channelCount)
{
    if (channelCount <= 1) {
        return interleaved;
    }
    const int frameCount = interleaved.size() / channelCount;
    QVector<float> mono(frameCount);
    for (int i = 0; i < frameCount; ++i) {
        float sum = 0.0f;
        for (int c = 0; c < channelCount; ++c) {
            sum += interleaved[i * channelCount + c];
        }
        mono[i] = sum / static_cast<float>(channelCount);
    }
    return mono;
}

QVector<float> upmixFromMono(const QVector<float> &mono, int channelCount)
{
    if (channelCount <= 1) {
        return mono;
    }
    QVector<float> interleaved(mono.size() * channelCount);
    for (int i = 0; i < mono.size(); ++i) {
        for (int c = 0; c < channelCount; ++c) {
            interleaved[i * channelCount + c] = mono[i];
        }
    }
    return interleaved;
}

// Reechantillonnage lineaire simple (suffisant pour de la voix telephonique
// -- pas de qualite musicale requise ici, juste eviter le silence total).
QVector<float> resampleLinear(const QVector<float> &input, int srcRate, int dstRate)
{
    if (input.isEmpty() || srcRate == dstRate || srcRate <= 0) {
        return input;
    }
    const int outCount = static_cast<int>(static_cast<qint64>(input.size()) * dstRate / srcRate);
    QVector<float> output(outCount);
    const double ratio = static_cast<double>(srcRate) / static_cast<double>(dstRate);
    for (int i = 0; i < outCount; ++i) {
        const double srcPos = i * ratio;
        const int idx0 = static_cast<int>(srcPos);
        const int idx1 = qMin(idx0 + 1, input.size() - 1);
        const double frac = srcPos - idx0;
        output[i] = static_cast<float>(input[idx0] * (1.0 - frac) + input[idx1] * frac);
    }
    return output;
}

QByteArray convertCaptureToTelephony(const QByteArray &raw, const QAudioFormat &deviceFormat)
{
    if (deviceFormat.sampleRate() == kVoiceSampleRate && deviceFormat.channelCount() == kVoiceChannelCount
        && deviceFormat.sampleFormat() == QAudioFormat::Int16) {
        return raw; // deja dans le format cible, aucune conversion necessaire
    }
    QVector<float> samples = toFloatSamples(raw, deviceFormat.sampleFormat());
    samples = downmixToMono(samples, deviceFormat.channelCount());
    samples = resampleLinear(samples, deviceFormat.sampleRate(), kVoiceSampleRate);
    return fromFloatSamplesInt16(samples);
}

QByteArray convertTelephonyToPlayback(const QByteArray &pcm16Mono8k, const QAudioFormat &deviceFormat)
{
    if (deviceFormat.sampleRate() == kVoiceSampleRate && deviceFormat.channelCount() == kVoiceChannelCount
        && deviceFormat.sampleFormat() == QAudioFormat::Int16) {
        return pcm16Mono8k;
    }
    QVector<float> samples = toFloatSamples(pcm16Mono8k, QAudioFormat::Int16);
    samples = resampleLinear(samples, kVoiceSampleRate, deviceFormat.sampleRate());
    samples = upmixFromMono(samples, deviceFormat.channelCount());
    return fromFloatSamplesFormat(samples, deviceFormat.sampleFormat());
}

} // namespace

QByteArray encodeMuLaw(const QByteArray &pcm16)
{
    const int sampleCount = pcm16.size() / 2;
    QByteArray out;
    out.resize(sampleCount);

    const auto *samples = reinterpret_cast<const std::int16_t *>(pcm16.constData());
    auto *dst = reinterpret_cast<std::uint8_t *>(out.data());
    for (int i = 0; i < sampleCount; ++i) {
        dst[i] = linearToMuLawSample(samples[i]);
    }
    return out;
}

QByteArray decodeMuLaw(const QByteArray &muLaw)
{
    QByteArray out;
    out.resize(muLaw.size() * 2);

    const auto *src = reinterpret_cast<const std::uint8_t *>(muLaw.constData());
    auto *samples = reinterpret_cast<std::int16_t *>(out.data());
    for (int i = 0; i < muLaw.size(); ++i) {
        samples[i] = muLawToLinearSample(src[i]);
    }
    return out;
}

// ---------------------------------------------------------------------
// RTP (RFC 3550) : en-tete minimal fixe (12 octets, sans extensions ni
// CSRC), suffisant pour une session audio point-a-point.
// ---------------------------------------------------------------------

QByteArray buildRtpPacket(const QByteArray &payload, std::uint8_t payloadType,
                          std::uint16_t sequenceNumber, std::uint32_t timestamp,
                          std::uint32_t ssrc, bool marker)
{
    QByteArray packet;
    packet.resize(12 + payload.size());
    auto *bytes = reinterpret_cast<std::uint8_t *>(packet.data());

    bytes[0] = 0x80; // version=2, padding=0, extension=0, CC=0
    bytes[1] = static_cast<std::uint8_t>((marker ? 0x80 : 0x00) | (payloadType & 0x7F));
    bytes[2] = static_cast<std::uint8_t>((sequenceNumber >> 8) & 0xFF);
    bytes[3] = static_cast<std::uint8_t>(sequenceNumber & 0xFF);
    bytes[4] = static_cast<std::uint8_t>((timestamp >> 24) & 0xFF);
    bytes[5] = static_cast<std::uint8_t>((timestamp >> 16) & 0xFF);
    bytes[6] = static_cast<std::uint8_t>((timestamp >> 8) & 0xFF);
    bytes[7] = static_cast<std::uint8_t>(timestamp & 0xFF);
    bytes[8] = static_cast<std::uint8_t>((ssrc >> 24) & 0xFF);
    bytes[9] = static_cast<std::uint8_t>((ssrc >> 16) & 0xFF);
    bytes[10] = static_cast<std::uint8_t>((ssrc >> 8) & 0xFF);
    bytes[11] = static_cast<std::uint8_t>(ssrc & 0xFF);

    std::memcpy(bytes + 12, payload.constData(), static_cast<size_t>(payload.size()));
    return packet;
}

RtpParsedPacket parseRtpPacket(const QByteArray &packet)
{
    RtpParsedPacket result;
    if (packet.size() < 12) {
        return result;
    }

    const auto *bytes = reinterpret_cast<const std::uint8_t *>(packet.constData());
    const int version = (bytes[0] >> 6) & 0x03;
    if (version != 2) {
        return result;
    }

    result.payloadType = bytes[1] & 0x7F;
    result.sequenceNumber = static_cast<std::uint16_t>((bytes[2] << 8) | bytes[3]);
    result.timestamp = (static_cast<std::uint32_t>(bytes[4]) << 24) | (static_cast<std::uint32_t>(bytes[5]) << 16)
                        | (static_cast<std::uint32_t>(bytes[6]) << 8) | static_cast<std::uint32_t>(bytes[7]);
    result.ssrc = (static_cast<std::uint32_t>(bytes[8]) << 24) | (static_cast<std::uint32_t>(bytes[9]) << 16)
                  | (static_cast<std::uint32_t>(bytes[10]) << 8) | static_cast<std::uint32_t>(bytes[11]);

    const int csrcCount = bytes[0] & 0x0F;
    const int headerSize = 12 + csrcCount * 4;
    if (packet.size() < headerSize) {
        return result;
    }

    result.payload = packet.mid(headerSize);
    result.valid = true;
    return result;
}

// ---------------------------------------------------------------------
// VoiceAudioIO
// ---------------------------------------------------------------------

VoiceAudioIO::VoiceAudioIO(QObject *parent)
    : QObject(parent)
{
}

VoiceAudioIO::~VoiceAudioIO()
{
    stop();
}

bool VoiceAudioIO::start()
{
    if (isFullyActive()) {
        return true;
    }
    // Un sens est deja actif. Le conserver pendant les tentatives de
    // VoiceService plutot que de recreer le peripherique restant.
    if (m_active) {
        return false;
    }

    QAudioFormat telephonyFormat;
    telephonyFormat.setSampleRate(kVoiceSampleRate);
    telephonyFormat.setChannelCount(kVoiceChannelCount);
    telephonyFormat.setSampleFormat(QAudioFormat::Int16);

    const QAudioDevice inputDevice = QMediaDevices::defaultAudioInput();
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();

    if (inputDevice.isNull() || outputDevice.isNull()) {
        // Diagnostic separe entree/sortie : le message combine ne permettait
        // pas de savoir lequel des deux manquait (utile notamment si le
        // probleme ne touche que l'entree -- pas de micro -- sur un poste
        // donne).
        if (inputDevice.isNull())
            qWarning() << "VoiceAudioIO: aucun peripherique d'entree (microphone) disponible";
        if (outputDevice.isNull())
            qWarning() << "VoiceAudioIO: aucun peripherique de sortie (haut-parleur) disponible";
        if (inputDevice.isNull() && outputDevice.isNull())
            return false;

        // Ne jamais couper l'autre sens : l'absence de microphone sur un
        // poste ne doit pas l'empecher d'entendre son correspondant.
        if (inputDevice.isNull()) {
            m_playbackFormat = outputDevice.isFormatSupported(telephonyFormat)
                ? telephonyFormat : outputDevice.preferredFormat();
            if (outputDevice.isFormatSupported(m_playbackFormat)) {
                m_audioSink = new QAudioSink(outputDevice, m_playbackFormat, this);
                m_playbackDevice = m_audioSink->start();
                if (m_playbackDevice) {
                    connect(m_audioSink, &QAudioSink::stateChanged, this, [this](QtAudio::State state) {
                        if (state == QtAudio::StoppedState && m_audioSink
                            && m_audioSink->error() != QtAudio::NoError)
                            emit audioFault(QStringLiteral("Le haut-parleur ou casque est devenu indisponible."));
                    });
                } else {
                    m_audioSink->deleteLater();
                    m_audioSink = nullptr;
                }
            }
        } else {
            m_captureFormat = inputDevice.isFormatSupported(telephonyFormat)
                ? telephonyFormat : inputDevice.preferredFormat();
            if (inputDevice.isFormatSupported(m_captureFormat)) {
                m_audioSource = new QAudioSource(inputDevice, m_captureFormat, this);
                m_captureDevice = m_audioSource->start();
                if (m_captureDevice) {
                    connect(m_captureDevice, &QIODevice::readyRead, this, &VoiceAudioIO::onCaptureReadyRead);
                    connect(m_audioSource, &QAudioSource::stateChanged, this, [this](QtAudio::State state) {
                        if (state == QtAudio::StoppedState && m_audioSource
                            && m_audioSource->error() != QtAudio::NoError)
                            emit audioFault(QStringLiteral("Le microphone est devenu indisponible."));
                    });
                } else {
                    m_audioSource->deleteLater();
                    m_audioSource = nullptr;
                }
            }
        }
        m_active = hasCapture() || hasPlayback();
        return false;
    }

    // CORRECTIF (debrief : "micro/haut-parleur non disponible", appel
    // connecte mais completement muet) : le format telephonique
    // 8kHz/mono/16bits n'est accepte que par une minorite de peripheriques
    // -- beaucoup de cartes son grand public (ex: "Realtek(R) Audio" en
    // WASAPI partage sous Windows) rejettent aussi bien 8kHz que les
    // anciens repli 44.1/48kHz DES QUE le format demande est mono, la
    // plupart n'exposant qu'un flux stereo natif. L'ancien code abandonnait
    // alors purement et simplement l'audio.
    //
    // Desormais, si le format telephonique n'est pas supporte tel quel, on
    // utilise le format PREFERE de CHAQUE peripherique separement (entree
    // et sortie peuvent differer) -- preferredFormat() reflete le format
    // natif du mixeur du peripherique et est donc pratiquement toujours
    // accepte -- et on convertit nous-memes en logiciel vers/depuis notre
    // format telephonique (cf. convertCaptureToTelephony()/
    // convertTelephonyToPlayback() ci-dessus : downmix/upmix + reechantillonnage
    // + conversion Int16/Float/UInt8/Int32). m_captureFormat/m_playbackFormat
    // retiennent le format REELLEMENT negocie avec chaque peripherique pour
    // que onCaptureReadyRead()/playFrame() sachent quelle conversion appliquer.
    m_captureFormat = telephonyFormat;
    m_playbackFormat = telephonyFormat;

    if (!inputDevice.isFormatSupported(telephonyFormat)) {
        m_captureFormat = inputDevice.preferredFormat();
        if (!inputDevice.isFormatSupported(m_captureFormat)) {
            qWarning() << "VoiceAudioIO: aucun format audio supporte en entree (micro), audio desactive";
            return false;
        }
        qInfo() << "VoiceAudioIO: capture en" << m_captureFormat.sampleRate() << "Hz /"
                << m_captureFormat.channelCount() << "canal(aux) au lieu de 8kHz mono (conversion logicielle)";
    }

    if (!outputDevice.isFormatSupported(telephonyFormat)) {
        m_playbackFormat = outputDevice.preferredFormat();
        if (!outputDevice.isFormatSupported(m_playbackFormat)) {
            qWarning() << "VoiceAudioIO: aucun format audio supporte en sortie (haut-parleur), audio desactive";
            return false;
        }
        qInfo() << "VoiceAudioIO: lecture en" << m_playbackFormat.sampleRate() << "Hz /"
                << m_playbackFormat.channelCount() << "canal(aux) au lieu de 8kHz mono (conversion logicielle)";
    }

    m_audioSource = new QAudioSource(inputDevice, m_captureFormat, this);
    m_captureDevice = m_audioSource->start();
    if (!m_captureDevice) {
        qWarning() << "VoiceAudioIO: impossible de demarrer la capture microphone";
        stop();
        return false;
    }
    connect(m_captureDevice, &QIODevice::readyRead, this, &VoiceAudioIO::onCaptureReadyRead);
    connect(m_audioSource, &QAudioSource::stateChanged, this, [this](QtAudio::State state) {
        if (state == QtAudio::StoppedState && m_audioSource
            && m_audioSource->error() != QtAudio::NoError) {
            emit audioFault(QStringLiteral("Le microphone est devenu indisponible."));
        }
    });

    m_audioSink = new QAudioSink(outputDevice, m_playbackFormat, this);
    m_playbackDevice = m_audioSink->start();
    if (!m_playbackDevice) {
        qWarning() << "VoiceAudioIO: impossible de demarrer la lecture haut-parleur";
        stop();
        return false;
    }
    connect(m_audioSink, &QAudioSink::stateChanged, this, [this](QtAudio::State state) {
        if (state == QtAudio::StoppedState && m_audioSink
            && m_audioSink->error() != QtAudio::NoError) {
            emit audioFault(QStringLiteral("Le haut-parleur ou casque est devenu indisponible."));
        }
    });

    m_captureBuffer.clear();
    m_active = true;
    return true;
}

void VoiceAudioIO::stop()
{
    if (m_audioSource) {
        m_audioSource->stop();
        m_audioSource->deleteLater();
        m_audioSource = nullptr;
    }
    if (m_audioSink) {
        m_audioSink->stop();
        m_audioSink->deleteLater();
        m_audioSink = nullptr;
    }
    m_captureDevice = nullptr;
    m_playbackDevice = nullptr;
    m_captureBuffer.clear();
    m_captureFormat = QAudioFormat();
    m_playbackFormat = QAudioFormat();
    m_active = false;
}

void VoiceAudioIO::onCaptureReadyRead()
{
    if (!m_captureDevice) {
        return;
    }

    // Convertit d'abord le buffer brut du peripherique (son format reel,
    // cf. m_captureFormat/start()) en mono 8kHz Int16 -- format telephonique
    // que le reste du pipeline (encodage mu-law, RTP) attend. No-op si le
    // peripherique parlait deja nativement ce format.
    const QByteArray telephonyPcm = convertCaptureToTelephony(m_captureDevice->readAll(), m_captureFormat);
    m_captureBuffer.append(telephonyPcm);

    // Regroupe la capture en trames fixes de 20 ms (issue #61) pour un
    // paquetage RTP regulier, quelle que soit la granularite de livraison
    // du backend audio de Qt.
    constexpr int frameBytes = kVoiceFrameSamples * (kVoiceSampleSizeBits / 8);
    while (m_captureBuffer.size() >= frameBytes) {
        const QByteArray frame = m_captureBuffer.left(frameBytes);
        m_captureBuffer.remove(0, frameBytes);

        if (!m_muted) {
            emit capturedFrame(frame);
        }
    }
}

void VoiceAudioIO::playFrame(const QByteArray &pcm16)
{
    if (!m_playbackDevice || pcm16.isEmpty()) {
        return;
    }
    // pcm16 est mono 8kHz Int16 (contrat inchange de ce slot, cf. header) --
    // converti ici vers le format REEL du peripherique de sortie
    // (m_playbackFormat/start()) avant l'ecriture. No-op si le peripherique
    // acceptait deja nativement le format telephonique.
    m_playbackDevice->write(convertTelephonyToPlayback(pcm16, m_playbackFormat));
}

} // namespace network
