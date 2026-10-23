#ifndef NETWORK_SCREENTILES_H
#define NETWORK_SCREENTILES_H

#include <QByteArray>
#include <QHash>
#include <QImage>
#include <QSize>
#include <QVector>

namespace network {

/// Partage d'ecran : l'image est decoupee en carreaux de 128 px ; seuls les
/// carreaux modifies partent, en JPEG, par le canal de donnees WebRTC de
/// chaque participant. Un ecran de bureau change peu : la plupart du temps
/// quelques carreaux par seconde, un defilement en envoie davantage.
constexpr int kScreenTileSize = 128;
/// Largeur maximale transmise (un ecran plus large est reduit).
constexpr int kScreenMaxWidth = 1920;
constexpr int kScreenJpegQuality = 82;

/// Ce qu'un spectateur a deja recu : empreinte de chaque carreau envoye.
/// Vide pour un nouveau venu, qui recoit donc l'image entiere.
struct ScreenViewerState {
    QSize frameSize;
    QHash<int, quint64> sent;
    void reset() { frameSize = QSize(); sent.clear(); }
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
