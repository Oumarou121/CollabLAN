#ifndef CORE_CALLCONTEXT_H
#define CORE_CALLCONTEXT_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QVariantList>
#include <QElapsedTimer>
#include <QImage>

#include "Voice/VoiceService.h"

namespace core {

class ScreenCapture;

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
    // Appel de groupe (4 personnes au plus, vous compris).
    Q_PROPERTY(QVariantList participants READ participants NOTIFY participantsChanged)
    Q_PROPERTY(QVariantList inviteRoster READ inviteRoster NOTIFY participantsChanged)
    Q_PROPERTY(bool groupCall READ isGroupCall NOTIFY participantsChanged)
    Q_PROPERTY(bool canInvite READ canInvite NOTIFY participantsChanged)
    Q_PROPERTY(bool localSpeaking READ isLocalSpeaking NOTIFY participantsChanged)
    Q_PROPERTY(int maxParticipants READ maxParticipants CONSTANT)
    // Partage d'ecran (une presentation a la fois).
    Q_PROPERTY(bool presenting READ isPresenting NOTIFY presentationChanged)
    Q_PROPERTY(bool canPresent READ canPresent NOTIFY presentationChanged)
    Q_PROPERTY(QString presentingTitle READ presentingTitle NOTIFY presentationChanged)
    Q_PROPERTY(QString presenterAddress READ presenterAddress NOTIFY presentationChanged)
    Q_PROPERTY(QString presenterTitle READ presenterTitle NOTIFY presentationChanged)
    Q_PROPERTY(int screenFrameId READ screenFrameId NOTIFY screenFrameChanged)
    Q_PROPERTY(bool screenSlow READ isScreenSlow NOTIFY screenFrameChanged)
    Q_PROPERTY(int localFrameId READ localFrameId NOTIFY localFrameChanged)

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

    /// Autres personnes de l'appel : [{ address, port, status, muted,
    /// speaking }], status valant "invited" | "inviting" | "connecting" |
    /// "joined" (cf. network::VoiceParticipant).
    QVariantList participants() const;
    /// Invitation en sonnerie : qui est deja dans l'appel [{ address, port }].
    QVariantList inviteRoster() const;
    bool isGroupCall() const;
    bool canInvite() const;
    bool isLocalSpeaking() const;
    int maxParticipants() const { return network::VoiceService::kMaxParticipants; }

    bool isPresenting() const;
    bool canPresent() const;
    QString presentingTitle() const;
    QString presenterAddress() const;
    QString presenterTitle() const;
    int screenFrameId() const { return m_screenFrameId; }
    bool isScreenSlow() const;
    int localFrameId() const { return m_localFrameId; }
    /// Images servies au QML par l'image provider « screenshare ».
    QImage remoteScreen() const;
    QImage localScreen() const;
    QImage sourceThumbnail(const QString &sourceId) const;

    /// Ecrans et fenetres presentables : [{ id, kind, title, detail }].
    Q_INVOKABLE QVariantList shareSources();
    Q_INVOKABLE bool startPresenting(const QString &sourceId);
    Q_INVOKABLE void stopPresenting();

    /// Initie un appel sortant vers l'adresse IP donnee (ex. depuis
    /// peersModel, voir UsersView.qml). Retourne false immediatement si
    /// aucun appel ne peut etre demarre (adresse invalide, service absent,
    /// appel deja en cours) : dans ce cas errorOccurred n'est pas forcement
    /// emis (l'appelant QML peut deja reagir sur la valeur de retour).
    Q_INVOKABLE bool call(const QString &address, int signalingPort = 0);

    /// Appel de groupe : 1 a 3 postes [{ address, signalingPort }].
    Q_INVOKABLE bool callGroup(const QVariantList &peers);

    /// Pendant un appel : invite une personne de plus.
    Q_INVOKABLE bool invite(const QString &address, int signalingPort = 0);

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

    void participantsChanged();
    void participantJoined(const QString &address);
    void participantLeft(const QString &address, const QString &reason);
    void participantDeclined(const QString &address, const QString &reason);

    void presentationChanged();
    void screenFrameChanged();
    void localFrameChanged();
    /// Un autre participant a commence / arrete de presenter.
    void presentationStarted(const QString &address);
    void presentationStopped(const QString &address);
    /// Votre presentation s'est arretee d'elle-meme ("conflict", "capture").
    void presentingStopped(const QString &reason);
    void screenUnsupported(const QString &address);

private slots:
    void onStateChanged(network::CallState state);
    void onIncomingCall(const QHostAddress &callerAddress);
    void onCallEnded(const QString &reason);
    void onErrorOccurred(const QString &message);

private:
    static QString stateToString(network::CallState state);

    void onPresentationChanged();

    network::VoiceService *m_voiceService = nullptr;
    QString m_callState = QStringLiteral("idle");
    QString m_remoteAddress;
    ScreenCapture *m_capture = nullptr;
    QString m_lastPresenter;
    int m_screenFrameId = 0;
    int m_localFrameId = 0;
    QElapsedTimer m_localFrameAge;
};

} // namespace core

#endif // CORE_CALLCONTEXT_H
