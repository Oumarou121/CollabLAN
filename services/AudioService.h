#ifndef SERVICES_AUDIOSERVICE_H
#define SERVICES_AUDIOSERVICE_H

#include <QAudioDevice>
#include <QAudioFormat>
#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QStringList>

#include <array>

#include "PcmConverter.h"

class QAudioSink;
class QMediaDevices;

namespace services {

class PcmPlaybackDevice;

/**
 * @brief Lecture des sons de notification (message, transfert, appel).
 *
 * Chaque categorie d'evenement propose plusieurs variantes de son que
 * l'utilisateur peut choisir depuis Parametres > Sons & notifications
 * (issue #56, extension "choix du son"). Toutes les variantes sont
 * decodees au demarrage ; seule la variante selectionnee par categorie est
 * jouee par playMessageSound()/playTransferSound()/playCallSound().
 * previewSound() permet d'ecouter n'importe quelle variante avant de la
 * choisir, sans changer la selection courante.
 *
 * CORRECTIF (sons de notification muets sur certaines cartes son, ex.
 * Realtek en partage WASAPI) : la lecture passait par QSoundEffect puis
 * QMediaPlayer. Sur ce materiel, les deux echouent SILENCIEUSEMENT :
 *   "QAudioSink::start: QAudioFormat not supported by QAudioDevice"
 *   "[SWR] Output channel layout "" is invalid or unsupported"
 * (le format prefere de la carte n'a pas de disposition de canaux que le
 * convertisseur FFmpeg de QMediaPlayer sache utiliser) ; error() reste a
 * NoError et rien ne sort. On decode donc les WAV nous-memes (PcmConverter)
 * et on les joue avec un QAudioSink ouvert sur preferredFormat() du
 * peripherique, apres conversion logicielle -- exactement la technique de
 * VoiceAudioIO, qui fonctionne sur ces memes postes pour les appels.
 * Reste asynchrone : QAudioSink tire les donnees dans son propre thread
 * audio, sans jamais bloquer le thread de l'UI.
 */
class AudioService : public QObject
{
    Q_OBJECT

    // Proprietes bindables depuis QML (SettingsView).
    Q_PROPERTY(bool soundEnabled READ isSoundEnabled WRITE setSoundEnabled NOTIFY soundEnabledChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QString messageSound READ messageSound WRITE setMessageSound NOTIFY messageSoundChanged)
    Q_PROPERTY(QString transferSound READ transferSound WRITE setTransferSound NOTIFY transferSoundChanged)
    Q_PROPERTY(QString callSound READ callSound WRITE setCallSound NOTIFY callSoundChanged)

public:
    /// Types d'evenements notifiables pouvant declencher un son.
    enum class EventType {
        Message,
        Transfer,
        Call
    };
    Q_ENUM(EventType)

    explicit AudioService(QObject *parent = nullptr);
    ~AudioService() override;

    /// Active ou desactive globalement la lecture des sons.
    void setSoundEnabled(bool enabled);
    bool isSoundEnabled() const { return m_soundEnabled; }

    /// Regle le volume de lecture (0.0 a 1.0) applique a tous les sons.
    void setVolume(qreal volume);
    qreal volume() const { return m_volume; }

    /// Identifiant de la variante actuellement selectionnee pour chaque
    /// categorie (ex. "soft", "pop", "bell" pour les messages). Voir
    /// soundVariants() pour la liste des identifiants valides.
    QString messageSound() const { return m_messageSound; }
    void setMessageSound(const QString &variantId);

    QString transferSound() const { return m_transferSound; }
    void setTransferSound(const QString &variantId);

    QString callSound() const { return m_callSound; }
    void setCallSound(const QString &variantId);

    /// Liste ordonnee des identifiants de variantes disponibles pour une
    /// categorie donnee. Utilise par SettingsView pour construire la
    /// liste des choix sans dupliquer les noms de fichiers en QML.
    Q_INVOKABLE QStringList soundVariants(services::AudioService::EventType type) const;

public slots:
    /// Joue de maniere asynchrone le son (variante selectionnee) associe
    /// au type d'evenement.
    void playSound(services::AudioService::EventType type);

    /// Joue une variante specifique une seule fois, quelle que soit la
    /// selection courante et sans tenir compte de soundEnabled -- permet
    /// a l'utilisateur d'ecouter un choix avant de le valider, meme si
    /// les sons sont globalement desactives.
    void previewSound(services::AudioService::EventType type, const QString &variantId);

    /// Raccourcis pratiques a connecter directement aux signaux des
    /// autres services (NotificationManager, TransferService, ...).
    void playMessageSound();
    void playTransferSound();
    void playCallSound();

    /// Arrete la sonnerie d'appel en cours (boucle infinie declenchee par
    /// playCallSound()) : a appeler des que l'appel entrant est traite
    /// (decroche, refuse, raccroche par l'appelant, timeout...).
    void stopCallSound();

signals:
    void soundEnabledChanged();
    void volumeChanged();
    void messageSoundChanged();
    void transferSoundChanged();
    void callSoundChanged();

private slots:
    /// Reconstruit la sortie audio quand l'OS signale un changement de
    /// peripherique (casque deconnecte, nouvelle sortie par defaut, etc.) :
    /// les QAudioSink sont detruits et recrees, au format du nouveau
    /// peripherique, a la prochaine lecture. Une sonnerie d'appel en cours
    /// est relancee sur la nouvelle sortie.
    void rebindAudioDevice();

private:
    /// Une "voie" de lecture par categorie (message / transfert / appel) :
    /// un message peut ainsi arriver pendant que la sonnerie d'appel
    /// boucle, sans la couper. Le QAudioSink est cree a la demande et
    /// detruit quand le peripherique de sortie change.
    struct Channel {
        QAudioSink *sink = nullptr;
        PcmPlaybackDevice *device = nullptr;
    };

    /// Decode chaque WAV embarque (qrc) en memoire. Ne depend pas du
    /// peripherique de sortie, donc fait une seule fois au demarrage.
    void loadSound(EventType type, const QString &variantId, const QString &resourcePath);

    /// Resout le peripherique de sortie par defaut et le format a utiliser
    /// (preferredFormat() si accepte, sinon un format courant accepte).
    /// Retourne false s'il n'y a aucun peripherique exploitable.
    bool ensureOutput();

    /// Detruit proprement le QAudioSink d'une voie (deconnecte ses signaux
    /// avant : il emet stateChanged pendant sa destruction). Utilise
    /// deleteLater() : ne jamais detruire immediatement un QAudioSink,
    /// son thread audio interne peut ne pas etre completement arrete
    /// (cf. correctif "VoiceAudioIO: aucun peripherique audio disponible"
    /// juste apres une sonnerie -- ouvrir/detruire des QAudioSink en rafale
    /// sur le meme peripherique semblait corrompre l'etat WASAPI cote Qt).
    void destroySink(Channel &channel);

    /// Cree le QAudioSink d'une voie s'il n'existe pas encore pour le
    /// peripherique/format courant.
    void ensureSink(Channel &channel);

    /// Detruit les QAudioSink, oublie les conversions et le format : tout
    /// est recalcule paresseusement pour le nouveau peripherique.
    void releaseOutput();

    /// Joue @p variantId sur la voie de @p type ; @p loop = boucle infinie
    /// (sonnerie d'appel).
    void startPlayback(EventType type, const QString &variantId, bool loop);

    /// Donnees PCM d'une variante converties pour le peripherique courant
    /// (mises en cache jusqu'au prochain changement de peripherique).
    QByteArray convertedFor(const QString &key);

    QString currentVariant(EventType type) const;
    static QString soundKey(EventType type, const QString &variantId);
    static QString resourcePathFor(EventType type, const QString &variantId);
    static QAudioFormat chooseOutputFormat(const QAudioDevice &device);

    QHash<QString, pcm::Clip> m_clips;         ///< sons decodes, cle = soundKey()
    QHash<QString, QByteArray> m_converted;    ///< PCM au format du peripherique courant
    std::array<Channel, 3> m_channels;         ///< indexe par EventType

    QMediaDevices *m_mediaDevices = nullptr;
    QAudioDevice m_outputDevice;
    QAudioFormat m_outputFormat;
    bool m_outputReady = false;
    bool m_callRinging = false;

    bool m_soundEnabled = true;
    qreal m_volume = 1.0;
    QString m_messageSound;
    QString m_transferSound;
    QString m_callSound;
};

} // namespace services

#endif // SERVICES_AUDIOSERVICE_H