#ifndef NETWORK_VOICEAUDIOIO_H
#define NETWORK_VOICEAUDIOIO_H

#include <QObject>
#include <QByteArray>
#include <QAudioFormat>
#include <cstdint>

class QAudioSource;
class QAudioSink;
class QIODevice;

namespace network {

/// Parametres audio utilises pour l'appel (issue #61) : mono 8 kHz 16 bits,
/// compatible telephonie et suffisant pour de la voix sur LAN. Ce format
/// simple permet un encodage/decodage G.711 (mu-law) sans dependance a une
/// bibliotheque de codec externe (pas d'Opus, cf. README architecture).
constexpr int kVoiceSampleRate = 8000;
constexpr int kVoiceChannelCount = 1;
constexpr int kVoiceSampleSizeBits = 16;
/// Duree d'une trame audio envoyee par paquet RTP (20 ms, standard telephonie).
constexpr int kVoiceFrameMs = 20;
constexpr int kVoiceFrameSamples = kVoiceSampleRate * kVoiceFrameMs / 1000; // 160
/// Type de charge utile RTP standard pour PCMU/G.711 mu-law (RFC 3551).
constexpr std::uint8_t kRtpPayloadTypePcmu = 0;

/// Encode un bloc de PCM 16 bits signe (little-endian, mono) en G.711 mu-law.
QByteArray encodeMuLaw(const QByteArray &pcm16);

/// Decode un bloc G.711 mu-law en PCM 16 bits signe (little-endian, mono).
QByteArray decodeMuLaw(const QByteArray &muLaw);

/// Construit un paquet RTP complet (en-tete 12 octets + charge utile) a
/// partir d'une trame mu-law deja encodee.
QByteArray buildRtpPacket(const QByteArray &payload, std::uint8_t payloadType,
                          std::uint16_t sequenceNumber, std::uint32_t timestamp,
                          std::uint32_t ssrc, bool marker);

/// Resultat de l'analyse d'un paquet RTP recu.
struct RtpParsedPacket {
    bool valid = false;
    std::uint8_t payloadType = 0;
    std::uint16_t sequenceNumber = 0;
    std::uint32_t timestamp = 0;
    std::uint32_t ssrc = 0;
    QByteArray payload;
};

/// Extrait l'en-tete et la charge utile d'un paquet RTP recu du reseau.
RtpParsedPacket parseRtpPacket(const QByteArray &packet);

/**
 * @brief Capture le microphone local et lit le flux audio du correspondant.
 *
 * Encapsule QAudioSource (capture) et QAudioSink (lecture) de Qt Multimedia.
 * Emet des trames PCM pretes a etre encodees/envoyees toutes les 20 ms
 * (capturedFrame), et accepte des trames PCM decodees a jouer (playFrame).
 *
 * Cette classe ne connait rien de WebRTC/RTP : elle est reutilisable pour
 * n'importe quel transport audio, ce qui separe la logique media (issue #61)
 * de la logique de session/signalisation (issue #60), portee par VoiceService.
 */
class VoiceAudioIO : public QObject
{
    Q_OBJECT

public:
    explicit VoiceAudioIO(QObject *parent = nullptr);
    ~VoiceAudioIO() override;

    /// Demarre la capture microphone et la lecture haut-parleur/casque.
    /// Retourne false si aucun peripherique audio par defaut n'est disponible.
    bool start();

    /// Arrete la capture et la lecture, libere les peripheriques audio.
    void stop();

    bool isActive() const { return m_active; }

    /// Coupe/reactive l'envoi du micro sans arreter la capture (mute local).
    void setMuted(bool muted) { m_muted = muted; }
    bool isMuted() const { return m_muted; }

signals:
    /// Emis toutes les ~20 ms avec une trame PCM 16 bits captee du micro
    /// (vide si mute), prete a etre encodee et envoyee en RTP.
    void capturedFrame(const QByteArray &pcm16);

    /// Le backend audio a perdu le peripherique ou n'a pas pu le demarrer.
    /// VoiceService peut alors reinitialiser les peripheriques sans couper la
    /// session WebRTC, qui reste valide independamment de l'audio local.
    void audioFault(const QString &reason);

public slots:
    /// Fournit une trame PCM 16 bits (deja decodee) a jouer sur le
    /// haut-parleur/casque local.
    void playFrame(const QByteArray &pcm16);

private slots:
    void onCaptureReadyRead();

private:
    QAudioSource *m_audioSource = nullptr;
    QIODevice *m_captureDevice = nullptr;

    QAudioSink *m_audioSink = nullptr;
    QIODevice *m_playbackDevice = nullptr;

    QByteArray m_captureBuffer;
    bool m_active = false;
    bool m_muted = false;

    // Formats reellement negocies avec les peripheriques (peuvent differer
    // du format telephonique cible 8kHz/mono/16bits, cf. conversion dans
    // onCaptureReadyRead()/playFrame() ci-dessous -- voir le commentaire de
    // start() pour le detail du pourquoi).
    QAudioFormat m_captureFormat;
    QAudioFormat m_playbackFormat;
};

} // namespace network

#endif // NETWORK_VOICEAUDIOIO_H
