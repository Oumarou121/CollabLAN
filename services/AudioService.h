#ifndef SERVICES_AUDIOSERVICE_H
#define SERVICES_AUDIOSERVICE_H

#include <QObject>
#include <QHash>

class QSoundEffect;

namespace services {

/**
 * @brief Lecture des sons de notification (message, transfert, appel).
 *
 * Un son distinct est precharge pour chaque type d'evenement
 * (issue #56). La lecture s'appuie sur QSoundEffect, dont l'API est
 * asynchrone : play() retourne immediatement et ne bloque jamais le
 * thread de l'UI.
 */
class AudioService : public QObject
{
    Q_OBJECT

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
    void setSoundEnabled(bool enabled) { m_soundEnabled = enabled; }
    bool isSoundEnabled() const { return m_soundEnabled; }

    /// Regle le volume de lecture (0.0 a 1.0) applique a tous les sons.
    void setVolume(qreal volume);
    qreal volume() const { return m_volume; }

public slots:
    /// Joue de maniere asynchrone le son associe au type d'evenement.
    void playSound(services::AudioService::EventType type);

    /// Raccourcis pratiques a connecter directement aux signaux des
    /// autres services (NotificationManager, TransferService, ...).
    void playMessageSound();
    void playTransferSound();
    void playCallSound();

    /// Arrete la sonnerie d'appel en cours (boucle infinie declenchee par
    /// playCallSound()) : a appeler des que l'appel entrant est traite
    /// (decroche, refuse, raccroche par l'appelant, timeout...).
    void stopCallSound();

private:
    void loadSound(EventType type, const QString &resourcePath);

    /// Copie une ressource embarquee (qrc) vers un fichier local (cache
    /// applicatif) et retourne son chemin, ou une chaine vide en cas
    /// d'echec. Voir le commentaire dans loadSound() / le .cpp.
    static QString extractToLocalFile(const QString &resourcePath);

    QHash<EventType, QSoundEffect *> m_sounds;
    bool m_soundEnabled = true;
    qreal m_volume = 1.0;
};

} // namespace services

#endif // SERVICES_AUDIOSERVICE_H