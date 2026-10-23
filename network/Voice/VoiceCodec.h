#ifndef NETWORK_VOICECODEC_H
#define NETWORK_VOICECODEC_H

#include <QByteArray>
#include <deque>
#include <map>

struct OpusEncoder;
struct OpusDecoder;

namespace network {

/**
 * @brief Encodeur Opus de la voix locale : trames de 20 ms en mono 16 kHz
 * (format interne de VoiceAudioIO), mode VoIP, correction d'erreur integree.
 * Un seul encodeur par appel : la meme trame encodee part vers chaque
 * participant qui parle Opus.
 */
class OpusVoiceEncoder
{
public:
    OpusVoiceEncoder();
    ~OpusVoiceEncoder();
    OpusVoiceEncoder(const OpusVoiceEncoder &) = delete;
    OpusVoiceEncoder &operator=(const OpusVoiceEncoder &) = delete;

    bool isValid() const { return m_encoder != nullptr; }
    /// Trame PCM 16 bits de kVoiceFrameSamples echantillons -> paquet Opus
    /// (vide en cas d'echec).
    QByteArray encode(const QByteArray &pcm16Frame);

private:
    OpusEncoder *m_encoder = nullptr;
};

/// Decodeur Opus d'un participant (un par flux : le decodeur garde un etat).
class OpusVoiceDecoder
{
public:
    OpusVoiceDecoder();
    ~OpusVoiceDecoder();
    OpusVoiceDecoder(const OpusVoiceDecoder &) = delete;
    OpusVoiceDecoder &operator=(const OpusVoiceDecoder &) = delete;

    bool isValid() const { return m_decoder != nullptr; }
    /// Paquet Opus -> PCM 16 bits mono 16 kHz (vide en cas d'echec).
    QByteArray decode(const QByteArray &packet);

private:
    OpusDecoder *m_decoder = nullptr;
};

/**
 * @brief Melange les voix des participants d'un appel.
 *
 * Chaque participant a sa file de trames (20 ms, mono 16 kHz) : elle amortit
 * l'irregularite d'arrivee des paquets (deux trames d'avance avant de jouer,
 * reprise apres un manque) et se vide de ses plus vieilles trames quand elle
 * s'allonge, pour que le retard ne s'accumule pas. mixNext() prend une trame
 * de chacun et les additionne : c'est le haut-parleur qui donne le rythme
 * (VoiceService ecrit tant que son tampon est court).
 */
class VoiceMixer
{
public:
    void push(int sourceId, const QByteArray &pcm16Frame);
    void remove(int sourceId);
    void clear();
    bool isEmpty() const { return m_sources.empty(); }
    /// Trame mixee de kVoiceFrameBytes octets (silence si personne ne parle).
    QByteArray mixNext();
    /// Trames en attente pour un participant (tests).
    int queued(int sourceId) const;

    static constexpr int kPrimeFrames = 2;
    static constexpr int kMaxFrames = 8;

private:
    struct Source {
        std::deque<QByteArray> frames;
        bool primed = false;
    };
    std::map<int, Source> m_sources;
};

} // namespace network

#endif // NETWORK_VOICECODEC_H
