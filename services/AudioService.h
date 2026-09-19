#ifndef SERVICES_AUDIOSERVICE_H
#define SERVICES_AUDIOSERVICE_H

#include <QObject>
#include <QHash>
#include <QStringList>

class QMediaDevices;
class QMediaPlayer;
class QAudioOutput;

namespace services {

/**
 * @brief Lecture des sons de notification (message, transfert, appel).
 *
 * Chaque categorie d'evenement propose plusieurs variantes de son que
 * l'utilisateur peut choisir depuis Parametres > Sons & notifications
 * (issue #56, extension "choix du son"). Toutes les variantes sont
 * prechargees au demarrage ; seule la variante selectionnee par
 * categorie est jouee par playMessageSound()/playTransferSound()/
 * playCallSound(). previewSound() permet d'ecouter n'importe quelle
 * variante avant de la choisir, sans changer la selection courante.
 *
 * CORRECTIF (sons de notification silencieux sur certaines cartes son,
 * ex. Realtek en partage WASAPI) : la lecture s'appuyait auparavant sur
 * QSoundEffect, qui exige que le peripherique de sortie accepte
 * nativement le format du fichier -- sinon QAudioSink::start echoue
 * ("QAudioFormat not supported by QAudioDevice"), silencieusement :
 * QSoundEffect::status() reste Ready et aucune erreur n'est remontee.
 * On utilise desormais QMediaPlayer (+ QAudioOutput), qui passe par le
 * pipeline de decodage/conversion FFmpeg deja utilise ailleurs dans
 * l'application (VoiceAudioIO) et convertit lui-meme vers le format
 * accepte par le peripherique, au lieu d'exiger un match natif. Reste
 * asynchrone, ne bloque jamais le thread de l'UI.
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
    /// Relie chaque QAudioOutput precharge au nouveau peripherique de
    /// sortie par defaut lorsque l'OS en signale le changement (casque
    /// deconnecte, nouvelle sortie par defaut, etc.). Sans quoi un effet
    /// peut rester silencieusement lie a un peripherique qui n'est plus
    /// celui utilise par le systeme.
    void rebindAudioDevice();

private:
    /// Un son precharge = un QMediaPlayer + son QAudioOutput dedie (le
    /// second ne peut pas etre partage entre plusieurs lecteurs). Les
    /// deux sont parentes a l'AudioService (destruction automatique).
    struct NotificationSound {
        QMediaPlayer *player = nullptr;
        QAudioOutput *output = nullptr;
    };

    void loadSound(EventType type, const QString &variantId, const QString &resourcePath);
    QString currentVariant(EventType type) const;
    static QString soundKey(EventType type, const QString &variantId);
    static QString resourcePathFor(EventType type, const QString &variantId);

    /// Copie une ressource embarquee (qrc) vers un fichier local (cache
    /// applicatif) et retourne son chemin, ou une chaine vide en cas
    /// d'echec. Voir le commentaire dans loadSound() / le .cpp.
    static QString extractToLocalFile(const QString &resourcePath);

    QHash<QString, NotificationSound> m_sounds;
    QMediaDevices *m_mediaDevices = nullptr;
    bool m_soundEnabled = true;
    qreal m_volume = 1.0;
    QString m_messageSound;
    QString m_transferSound;
    QString m_callSound;
};

} // namespace services

#endif // SERVICES_AUDIOSERVICE_H