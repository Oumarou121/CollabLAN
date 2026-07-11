#ifndef CORE_CALLCONTEXT_H
#define CORE_CALLCONTEXT_H

#include <QObject>
#include <QString>
#include <QHostAddress>

#include "Voice/VoiceService.h"

namespace core {

/**
 * @brief Wrapper pour exposer les appels vocaux a QML (issues #60/#61/#64).
 *
 * Relie network::VoiceService (signalisation WebRTC + session media,
 * cf. reseau/Voice/) a CallView.qml : demarrage/reception d'appel, etat en
 * temps reel (callState), identite de l'appelant entrant, et micro coupe/
 * actif. Suit exactement le meme patron que TransferContext/MessagingContext
 * (setXxxService() + Q_PROPERTY/NOTIFY), pour rester coherent avec le reste
 * du bootstrap QML (app/main.cpp).
 *
 * callState est expose comme une chaine plutot que l'enum network::CallState
 * directement : ca evite d'avoir a enregistrer l'enum aupres du moteur QML
 * (qmlRegisterUncreatableType, etc.) pour un simple affichage conditionnel
 * cote QML (ex. callState === "ringing").
 */
class CallContext : public QObject
{
    Q_OBJECT
    Q_PROPERTY(network::VoiceService* voiceService READ voiceService WRITE setVoiceService NOTIFY voiceServiceChanged)
    Q_PROPERTY(QString callState READ callState NOTIFY callStateChanged)
    Q_PROPERTY(QString remoteAddress READ remoteAddress NOTIFY remoteAddressChanged)
    Q_PROPERTY(bool muted READ isMuted WRITE setMuted NOTIFY mutedChanged)

public:
    explicit CallContext(QObject *parent = nullptr);
    ~CallContext() override;

    network::VoiceService* voiceService() const { return m_voiceService; }
    void setVoiceService(network::VoiceService *service);

    /// Etat courant sous forme de chaine stable, utilisable directement dans
    /// des bindings/comparaisons QML : "idle" | "calling" | "ringing" |
    /// "connecting" | "connected" | "ending".
    QString callState() const { return m_callState; }

    /// Adresse du correspondant courant (appelant pour un appel entrant,
    /// destinataire pour un appel sortant). Vide hors appel.
    QString remoteAddress() const { return m_remoteAddress; }

    bool isMuted() const;
    void setMuted(bool muted);

    /// Initie un appel sortant vers l'adresse IP donnee (ex. depuis
    /// peersModel, voir UsersView.qml). Retourne false immediatement si
    /// aucun appel ne peut etre demarre (adresse invalide, service absent,
    /// appel deja en cours) : dans ce cas errorOccurred n'est pas forcement
    /// emis (l'appelant QML peut deja reagir sur la valeur de retour).
    Q_INVOKABLE bool call(const QString &address);

    /// Accepte l'appel entrant actuellement en sonnerie (etat "ringing").
    Q_INVOKABLE void acceptCall();

    /// Refuse l'appel entrant en sonnerie, ou raccroche un appel en cours.
    Q_INVOKABLE void hangUp();

    Q_INVOKABLE void toggleMute();

signals:
    void voiceServiceChanged();
    void callStateChanged();
    void remoteAddressChanged();
    void mutedChanged();

    /// Relaye tel quel depuis VoiceService::incomingCall, pour que Main.qml
    /// puisse naviguer vers CallView des reception d'un appel entrant, meme
    /// si l'utilisateur est actuellement sur un autre ecran.
    void incomingCall(const QString &callerAddress);

    void callEnded(const QString &reason);
    void errorOccurred(const QString &message);

private slots:
    void onStateChanged(network::CallState state);
    void onIncomingCall(const QHostAddress &callerAddress);
    void onCallEnded(const QString &reason);
    void onErrorOccurred(const QString &message);

private:
    static QString stateToString(network::CallState state);

    network::VoiceService *m_voiceService = nullptr;
    QString m_callState = QStringLiteral("idle");
    QString m_remoteAddress;
};

} // namespace core

#endif // CORE_CALLCONTEXT_H
