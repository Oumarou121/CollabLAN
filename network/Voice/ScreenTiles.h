#ifndef NETWORK_SCREENTILES_H
#define NETWORK_SCREENTILES_H

#include <QByteArray>
#include <QHash>
#include <QImage>
#include <QSize>
#include <QVector>

#include <memory>

namespace network {

/// Partage d'ecran : l'image est decoupee en carreaux de 128 px ; seuls les
/// carreaux modifies partent, en JPEG, par le canal de donnees WebRTC de
/// chaque participant. Un ecran de bureau change peu : la plupart du temps
/// quelques carreaux par seconde, un defilement en envoie davantage.
constexpr int kScreenTileSize = 128;
/// Largeur maximale transmise (un ecran plus large est reduit).
constexpr int kScreenMaxWidth = 1920;
constexpr int kScreenJpegQuality = 82;

/// « Mode mouvement » (video, defilement) : quand une grande part de l'ecran
/// change d'une image a l'autre, envoyer les carreaux revient a envoyer tout
/// l'ecran en 135 morceaux. Une seule image entiere, reduite et plus
/// compressee, part a la place ; les carreaux nets reviennent quand l'ecran
/// se calme.
constexpr int kScreenMotionWidth = 1280;
constexpr int kScreenMotionQuality = 60;
/// Au-dela, l'image en mouvement est reduite encore (canal limite a 256 Ko).
constexpr int kScreenMotionMaxBytes = 200 * 1024;

/// Ce qu'un spectateur a deja recu : empreinte de chaque carreau envoye.
/// Vide pour un nouveau venu, qui recoit donc l'image entiere.
struct ScreenViewerState {
    QSize frameSize;
    QHash<int, quint64> sent;
    quint32 lastMotionSequence = 0;     ///< derniere image en mouvement envoyee
    quint32 lastEndSequence = 0;        ///< derniere fin d'image envoyee
    bool lastEndComplete = true;        ///< ... et si elle etait complete
    void reset() { frameSize = QSize(); sent.clear(); lastMotionSequence = 0; lastEndSequence = 0; lastEndComplete = true; }
};

/**
 * @brief Cote presentateur : analyse une image capturee (empreinte de chaque
 * carreau) et fournit les messages a envoyer, encodes une seule fois par
 * image quel que soit le nombre de spectateurs.
 */
class ScreenTileEncoder
{
public:
    /// Nouvelle image capturee : reduite si besoin, carreaux recalcules.
    void setFrame(const QImage &frame);
    bool hasFrame() const { return !m_frame.isNull(); }
    QImage frame() const { return m_frame; }
    QSize frameSize() const { return m_frame.size(); }
    int tileCount() const { return static_cast<int>(m_hashes.size()); }
    quint64 tileHash(int index) const { return m_hashes.value(index); }
    /// Message « carreau » (en-tete + JPEG), mis en cache pour cette image.
    QByteArray tileMessage(int index);
    /// Carreaux encore a envoyer a ce spectateur.
    QVector<int> pendingTiles(const ScreenViewerState &viewer) const;
    quint32 sequence() const { return m_sequence; }

private:
    QImage m_frame;
    QVector<quint64> m_hashes;
    QHash<int, QByteArray> m_messages;
    int m_columns = 0;
    quint32 m_sequence = 0;
};

/// Image entiere reduite (mode mouvement) : en-tete + JPEG.
QByteArray screenMotionMessage(const QImage &frame);

/// Ce que le presentateur envoie pour une image capturee : des carreaux, ou
/// une image entiere en mouvement. Construit hors du fil de l'interface
/// (ScreenFrameAnalyzer), puis lu par VoiceService.
struct ScreenPacket {
    std::shared_ptr<ScreenTileEncoder> tiles;   ///< image analysee (toujours presente)
    QByteArray motion;                          ///< non vide : mode mouvement
    quint32 sequence = 0;
    bool motionEnded = false;                   ///< retour aux carreaux : tout l'ecran a renvoyer
    bool isEmpty() const { return !tiles; }
};

/**
 * @brief Analyse chaque capture : part de l'ecran qui a change depuis la
 * precedente, choix du mode (carreaux ou mouvement, avec hysteresis pour ne
 * pas osciller), et compression faite d'avance pour les carreaux modifies.
 * Concu pour tourner sur un fil a part.
 */
class ScreenFrameAnalyzer
{
public:
    /// full : compresse tous les carreaux (nouveau spectateur a servir).
    ScreenPacket analyze(const QImage &capture, bool full = false);
    bool inMotion() const { return m_motion; }
    void reset();

    static constexpr double kEnterMotionRatio = 0.33;
    static constexpr double kLeaveMotionRatio = 0.10;
    static constexpr int kCalmFramesToLeave = 3;

private:
    QVector<quint64> m_previous;
    QSize m_previousSize;
    bool m_motion = false;
    int m_calmFrames = 0;
    quint32 m_sequence = 0;
};

/// Fin d'image : complete = false si des carreaux n'ont pas pu partir
/// (spectateur trop lent) ; il affiche alors « connexion lente ».
QByteArray screenFrameEndMessage(quint32 sequence, bool complete);

/// Demande du spectateur : « renvoie-moi tout l'ecran » (il vient d'arriver,
/// ou des carreaux sont partis avant qu'il sache qui presente).
QByteArray screenRefreshRequest();
bool isScreenRefreshRequest(const QByteArray &message);

/**
 * @brief Cote spectateur : recompose l'ecran a partir des carreaux recus.
 */
class ScreenCanvas
{
public:
    /// Applique un message recu. Retourne true si l'image a change.
    bool apply(const QByteArray &message);
    QImage image() const { return m_image; }
    void clear();
    /// La derniere fin d'image recue etait incomplete (spectateur en retard).
    bool lastFrameIncomplete() const { return m_lastIncomplete; }

private:
    QImage m_image;
    bool m_lastIncomplete = false;
};

} // namespace network

#endif // NETWORK_SCREENTILES_H
