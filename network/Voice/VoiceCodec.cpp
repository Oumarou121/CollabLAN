#include "VoiceCodec.h"
#include "VoiceAudioIO.h"

#include <opus.h>

#include <QDebug>
#include <QtGlobal>

#include <cstdint>

namespace network {

namespace {
// 24 kbit/s : voix en bande elargie tres nette, negligeable sur un LAN.
constexpr int kOpusBitrate = 24000;
// Plus grand paquet Opus accepte en entree du decodeur : 120 ms.
constexpr int kOpusMaxFrameSamples = kVoiceSampleRate * 120 / 1000;
constexpr int kOpusMaxPacketBytes = 1275;
}

OpusVoiceEncoder::OpusVoiceEncoder()
{
    int error = OPUS_OK;
    m_encoder = opus_encoder_create(kVoiceSampleRate, kVoiceChannelCount, OPUS_APPLICATION_VOIP, &error);
    if (error != OPUS_OK || !m_encoder) {
        qWarning() << "OpusVoiceEncoder: creation impossible -" << opus_strerror(error);
        m_encoder = nullptr;
        return;
    }
    opus_encoder_ctl(m_encoder, OPUS_SET_BITRATE(kOpusBitrate));
    opus_encoder_ctl(m_encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    opus_encoder_ctl(m_encoder, OPUS_SET_INBAND_FEC(1));
    opus_encoder_ctl(m_encoder, OPUS_SET_PACKET_LOSS_PERC(5));
}

OpusVoiceEncoder::~OpusVoiceEncoder()
{
    if (m_encoder)
        opus_encoder_destroy(m_encoder);
}

QByteArray OpusVoiceEncoder::encode(const QByteArray &pcm16Frame)
{
    if (!m_encoder || pcm16Frame.size() != kVoiceFrameBytes)
        return QByteArray();
    QByteArray packet(kOpusMaxPacketBytes, Qt::Uninitialized);
    const int bytes = opus_encode(m_encoder, reinterpret_cast<const opus_int16 *>(pcm16Frame.constData()),
                                  kVoiceFrameSamples, reinterpret_cast<unsigned char *>(packet.data()),
                                  packet.size());
    if (bytes < 0)
        return QByteArray();
    packet.truncate(bytes);
    return packet;
}

OpusVoiceDecoder::OpusVoiceDecoder()
{
    int error = OPUS_OK;
    m_decoder = opus_decoder_create(kVoiceSampleRate, kVoiceChannelCount, &error);
    if (error != OPUS_OK || !m_decoder) {
        qWarning() << "OpusVoiceDecoder: creation impossible -" << opus_strerror(error);
        m_decoder = nullptr;
    }
}

OpusVoiceDecoder::~OpusVoiceDecoder()
{
    if (m_decoder)
        opus_decoder_destroy(m_decoder);
}

QByteArray OpusVoiceDecoder::decode(const QByteArray &packet)
{
    if (!m_decoder || packet.isEmpty())
        return QByteArray();
    QByteArray pcm(kOpusMaxFrameSamples * 2, Qt::Uninitialized);
    const int samples = opus_decode(m_decoder, reinterpret_cast<const unsigned char *>(packet.constData()),
                                    static_cast<opus_int32>(packet.size()),
                                    reinterpret_cast<opus_int16 *>(pcm.data()), kOpusMaxFrameSamples, 0);
    if (samples <= 0)
        return QByteArray();
    pcm.truncate(samples * 2);
    return pcm;
}

void VoiceMixer::push(int sourceId, const QByteArray &pcm16Frame)
{
    if (pcm16Frame.size() != kVoiceFrameBytes)
        return;
    Source &source = m_sources[sourceId];
    source.frames.push_back(pcm16Frame);
    // Retard accumule (horloges des postes, rafale apres une coupure) :
    // on repart de quelques trames d'avance au lieu de tout jouer en retard.
    if (static_cast<int>(source.frames.size()) > kMaxFrames) {
        while (static_cast<int>(source.frames.size()) > kPrimeFrames + 1)
            source.frames.pop_front();
    }
}

void VoiceMixer::remove(int sourceId)
{
    m_sources.erase(sourceId);
}

void VoiceMixer::clear()
{
    m_sources.clear();
}

int VoiceMixer::queued(int sourceId) const
{
    const auto it = m_sources.find(sourceId);
    return it == m_sources.end() ? 0 : static_cast<int>(it->second.frames.size());
}

QByteArray VoiceMixer::mixNext()
{
    std::int32_t sum[kVoiceFrameSamples] = {};
    for (auto &entry : m_sources) {
        Source &source = entry.second;
        if (!source.primed && static_cast<int>(source.frames.size()) >= kPrimeFrames)
            source.primed = true;
        if (!source.primed)
            continue;
        if (source.frames.empty()) {
            // Plus rien a jouer : on attend de nouveau deux trames d'avance.
            source.primed = false;
            continue;
        }
        const QByteArray frame = source.frames.front();
        source.frames.pop_front();
        const auto *samples = reinterpret_cast<const std::int16_t *>(frame.constData());
        for (int i = 0; i < kVoiceFrameSamples; ++i)
            sum[i] += samples[i];
    }
    QByteArray out(kVoiceFrameBytes, Qt::Uninitialized);
    auto *dst = reinterpret_cast<std::int16_t *>(out.data());
    for (int i = 0; i < kVoiceFrameSamples; ++i)
        dst[i] = static_cast<std::int16_t>(qBound<std::int32_t>(-32768, sum[i], 32767));
    return out;
}

} // namespace network
