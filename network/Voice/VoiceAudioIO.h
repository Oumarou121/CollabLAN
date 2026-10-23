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

/// Format interne de la voix (capture, mixage, lecture) : mono 16 kHz 16 bits,
/// la bande elargie d'Opus. Les postes d'une version anterieure ne parlent
/// que G.711 (PCMU, 8 kHz) : leur flux est converti a l'envoi et a la
/// reception (cf. VoiceService).
constexpr int kVoiceSampleRate = 16000;
constexpr int kVoiceChannelCount = 1;
constexpr int kVoiceSampleSizeBits = 16;
/// Duree d'une trame audio envoyee par paquet RTP (20 ms, standard telephonie).
constexpr int kVoiceFrameMs = 20;
constexpr int kVoiceFrameSamples = kVoiceSampleRate * kVoiceFrameMs / 1000; // 320
constexpr int kVoiceFrameBytes = kVoiceFrameSamples * (kVoiceSampleSizeBits / 8);
/// G.711 : 8 kHz, horloge RTP 8000, 160 echantillons par trame.
constexpr int kPcmuSampleRate = 8000;
constexpr int kPcmuFrameSamples = kPcmuSampleRate * kVoiceFrameMs / 1000; // 160
/// Type de charge utile RTP standard pour PCMU/G.711 mu-law (RFC 3551).
constexpr std::uint8_t kRtpPayloadTypePcmu = 0;
/// Opus (RFC 7587) : type dynamique, horloge RTP toujours a 48 kHz.
constexpr std::uint8_t kRtpPayloadTypeOpus = 111;
constexpr int kOpusRtpClockRate = 48000;
constexpr int kOpusFrameTicks = kOpusRtpClockRate * kVoiceFrameMs / 1000; // 960

/// Reechantillonne du PCM 16 bits mono (ex. 16 kHz -> 8 kHz pour G.711).
QByteArray resamplePcm16(const QByteArray &pcm16, int srcRate, int dstRate);

/// Niveau RMS d'une trame PCM 16 bits, entre 0 et 1 (detection de la parole).
float pcm16Level(const QByteArray &pcm16);

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

    /// Demarre independamment la capture et la lecture. Retourne true
    /// seulement si les deux sens sont disponibles.
    bool start();

    /// Arrete la capture et la lecture, libere les peripheriques audio.
    void stop();

    bool isActive() const { return m_active; }
    bool hasCapture() const { return m_captureDevice != nullptr; }
    bool hasPlayback() const { return m_playbackDevice != nullptr; }
    bool isFullyActive() const { return hasCapture() && hasPlayback(); }

    /// Duree de son deja ecrite mais pas encore jouee par le haut-parleur, en
    /// ms (-1 si inconnue) : le mixage de VoiceService ecrit au rythme du
    /// peripherique au lieu de son propre minuteur.
    int playbackBufferedMs() const;

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
    /// Fournit une trame PCM 16 bits mono 16 kHz (deja decodee et mixee) a
    /// jouer sur le haut-parleur/casque local.
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
