#include "ScreenWorkers.h"

#include <QMutexLocker>

namespace network {

ScreenEncodeWorker::ScreenEncodeWorker(QObject *parent)
    : QObject(parent)
{
}

void ScreenEncodeWorker::submit(const QImage &frame)
{
    QMutexLocker lock(&m_mutex);
    m_pendingImage = frame;
    m_pendingVideo = QVideoFrame();
    m_hasPending = true;
    schedule();
}

void ScreenEncodeWorker::submit(const QVideoFrame &frame)
{
    QMutexLocker lock(&m_mutex);
    m_pendingVideo = frame;
    m_pendingImage = QImage();
    m_hasPending = true;
    schedule();
}

void ScreenEncodeWorker::reset()
{
    QMutexLocker lock(&m_mutex);
    m_resetRequested = true;
    m_hasPending = false;
    m_pendingImage = QImage();
    m_pendingVideo = QVideoFrame();
}

void ScreenEncodeWorker::requestFullEncode()
{
    QMutexLocker lock(&m_mutex);
    m_fullRequested = true;
}

void ScreenEncodeWorker::schedule()
{
    // Appele sous verrou.
    if (m_busy)
        return;
    m_busy = true;
    QMetaObject::invokeMethod(this, &ScreenEncodeWorker::process, Qt::QueuedConnection);
}

void ScreenEncodeWorker::process()
{
    for (;;) {
        QImage image;
        QVideoFrame video;
        bool full = false;
        {
            QMutexLocker lock(&m_mutex);
            if (m_resetRequested) {
                m_analyzer.reset();
                m_resetRequested = false;
            }
            if (!m_hasPending) {
                m_busy = false;
                return;
            }
            image = m_pendingImage;
            video = m_pendingVideo;
            m_pendingImage = QImage();
            m_pendingVideo = QVideoFrame();
            m_hasPending = false;
            full = m_fullRequested;
            m_fullRequested = false;
        }
        // Conversion de l'image capturee ici aussi, hors de l'interface.
        if (video.isValid())
            image = video.toImage();
        if (image.isNull())
            continue;
        const ScreenPacket packet = m_analyzer.analyze(image, full);
        if (!packet.isEmpty())
            emit packetReady(packet);
    }
}

ScreenDecodeWorker::ScreenDecodeWorker(QObject *parent)
    : QObject(parent)
{
}

void ScreenDecodeWorker::apply(const QByteArray &message, int generation)
{
    if (generation != m_generation)
        return;
    if (!m_flushTimer) {
        // Cree sur le fil du decodeur (premier message) : il y vit.
        m_flushTimer = new QTimer(this);
        m_flushTimer->setSingleShot(true);
        m_flushTimer->setInterval(33);
        connect(m_flushTimer, &QTimer::timeout, this, &ScreenDecodeWorker::flush);
    }
    const bool wasSlow = m_canvas.lastFrameIncomplete();
    const bool changed = m_canvas.apply(message);
    if ((changed || wasSlow != m_canvas.lastFrameIncomplete()) && !m_flushTimer->isActive())
        m_flushTimer->start();
}

void ScreenDecodeWorker::clear(int generation)
{
    m_generation = generation;
    m_canvas.clear();
    if (m_flushTimer)
        m_flushTimer->stop();
}

void ScreenDecodeWorker::flush()
{
    // Copie partagee : le prochain carreau peint detache l'image du canevas.
    emit imageReady(m_canvas.image(), m_canvas.lastFrameIncomplete(), m_generation);
}

} // namespace network
