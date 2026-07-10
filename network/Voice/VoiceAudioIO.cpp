#include "VoiceAudioIO.h"

#include <QAudioSource>
#include <QAudioSink>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QAudioFormat>
#include <QIODevice>
#include <QDebug>

#include <array>

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
    if (m_active) {
        return true;
    }

    QAudioFormat format;
    format.setSampleRate(kVoiceSampleRate);
    format.setChannelCount(kVoiceChannelCount);
    format.setSampleFormat(QAudioFormat::Int16);

    const QAudioDevice inputDevice = QMediaDevices::defaultAudioInput();
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();

    if (inputDevice.isNull() || outputDevice.isNull()) {
        qWarning() << "VoiceAudioIO: aucun peripherique audio d'entree/sortie disponible";
        return false;
    }
    if (!inputDevice.isFormatSupported(format) || !outputDevice.isFormatSupported(format)) {
        qWarning() << "VoiceAudioIO: format audio 8kHz/mono/16bits non supporte par le peripherique,"
                    << "la capture/lecture pourrait etre degradee";
    }

    m_audioSource = new QAudioSource(inputDevice, format, this);
    m_captureDevice = m_audioSource->start();
    if (!m_captureDevice) {
        qWarning() << "VoiceAudioIO: impossible de demarrer la capture microphone";
        return false;
    }
    connect(m_captureDevice, &QIODevice::readyRead, this, &VoiceAudioIO::onCaptureReadyRead);

    m_audioSink = new QAudioSink(outputDevice, format, this);
    m_playbackDevice = m_audioSink->start();
    if (!m_playbackDevice) {
        qWarning() << "VoiceAudioIO: impossible de demarrer la lecture haut-parleur";
        m_audioSource->stop();
        return false;
    }

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
    m_active = false;
}

void VoiceAudioIO::onCaptureReadyRead()
{
    if (!m_captureDevice) {
        return;
    }

    m_captureBuffer.append(m_captureDevice->readAll());

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
    m_playbackDevice->write(pcm16);
}

} // namespace network
