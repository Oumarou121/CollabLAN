#ifndef NETWORK_SCREENWORKERS_H
#define NETWORK_SCREENWORKERS_H

#include <QByteArray>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QTimer>
#include <QVideoFrame>

#include "ScreenTiles.h"

Q_DECLARE_METATYPE(network::ScreenPacket)

namespace network {

/**
 * @brief Partage d'ecran, cote presentateur : conversion de la capture,
 * analyse et compression sur un fil a part (ScreenFrameAnalyzer). Avant, tout
 * se faisait sur le fil de l'interface : jusqu'a 135 compressions JPEG par
 * image ralentissaient l'application et plafonnaient a quelques images/s.
 *
 * Seule la capture la plus recente compte : si une analyse est en cours, la
 * suivante remplace celle en attente au lieu de s'ajouter a une file.
 */
class ScreenEncodeWorker : public QObject
{
    Q_OBJECT

public:
    explicit ScreenEncodeWorker(QObject *parent = nullptr);

    /// Depuis n'importe quel fil.
    void submit(const QImage &frame);
    void submit(const QVideoFrame &frame);
    /// Nouvelle presentation : repart sans memoire de l'image precedente.
    void reset();
    /// La prochaine image compresse tout l'ecran (un spectateur doit tout recevoir).
    void requestFullEncode();

signals:
    void packetReady(const network::ScreenPacket &packet);

private:
    void schedule();
    void process();

    QMutex m_mutex;
    QImage m_pendingImage;
    QVideoFrame m_pendingVideo;
    bool m_hasPending = false;
    bool m_busy = false;
    bool m_resetRequested = false;
    bool m_fullRequested = false;
    ScreenFrameAnalyzer m_analyzer;
};

/**
 * @brief Partage d'ecran, cote spectateur : decompression des carreaux et des
 * images en mouvement sur un fil a part ; l'image recomposee est publiee au
 * plus une trentaine de fois par seconde.
 */
class ScreenDecodeWorker : public QObject
{
    Q_OBJECT

public:
    explicit ScreenDecodeWorker(QObject *parent = nullptr);

public slots:
    void apply(const QByteArray &message, int generation);
    void clear(int generation);

signals:
    /// generation : celle du presentateur en cours (les images d'un
    /// presentateur precedent arrivees en retard sont ignorees).
    void imageReady(const QImage &image, bool slow, int generation);

private:
    void flush();

    ScreenCanvas m_canvas;
    QTimer *m_flushTimer = nullptr;
    int m_generation = 0;
};

} // namespace network

#endif // NETWORK_SCREENWORKERS_H
