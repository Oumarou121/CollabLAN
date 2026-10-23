#include "ScreenCapture.h"

#include <QCoreApplication>
#include <QDebug>
#include <QGuiApplication>
#include <QScreen>

namespace core {

namespace {
constexpr int kCaptureIntervalMs = 100;     // 10 images par seconde au plus

QString permissionHint()
{
#ifdef Q_OS_MACOS
    return QObject::tr("Autorisez LocaLink dans Réglages Système › Confidentialité et sécurité › "
                       "Enregistrement de l'écran, puis réessayez.");
#else
    return QString();
#endif
}
} // namespace

ScreenCapture::ScreenCapture(QObject *parent)
    : QObject(parent)
{
    m_session.setVideoSink(&m_sink);
    connect(&m_sink, &QVideoSink::videoFrameChanged, this, &ScreenCapture::onFrame);
    connect(&m_screenCapture, &QScreenCapture::errorOccurred, this,
            [this](QScreenCapture::Error, const QString &message) { onError(message); });
    connect(&m_windowCapture, &QWindowCapture::errorOccurred, this,
            [this](QWindowCapture::Error, const QString &message) { onError(message); });
    m_tick.setInterval(kCaptureIntervalMs);
    connect(&m_tick, &QTimer::timeout, this, &ScreenCapture::onTick);
}

ScreenCapture::~ScreenCapture()
{
    stop();
}

QList<ScreenCapture::Source> ScreenCapture::sources()
{
    QList<Source> out;
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (int i = 0; i < screens.size(); ++i) {
        const QScreen *screen = screens.at(i);
        const QSize pixels = screen->size() * screen->devicePixelRatio();
        const QString size = QStringLiteral("%1 × %2").arg(pixels.width()).arg(pixels.height());
        out.append({QStringLiteral("screen:%1").arg(i), QStringLiteral("screen"), tr("Écran %1").arg(i + 1),
                    screen == QGuiApplication::primaryScreen() ? tr("Principal · %1").arg(size) : size});
    }
    m_windows = QWindowCapture::capturableWindows();
    const QString self = QCoreApplication::applicationName();
    for (int i = 0; i < m_windows.size(); ++i) {
        const QString title = m_windows.at(i).description().trimmed();
        if (title.isEmpty())
            continue;   // fenetres techniques sans titre
        out.append({QStringLiteral("window:%1").arg(i), QStringLiteral("window"), title,
                    title.contains(self, Qt::CaseInsensitive) ? tr("Cette application") : tr("Fenêtre")});
    }
    return out;
}

QImage ScreenCapture::thumbnail(const QString &id, int width) const
{
    if (!id.startsWith(QLatin1String("screen:")))
        return QImage();
    const QList<QScreen *> screens = QGuiApplication::screens();
    const int index = id.mid(7).toInt();
    if (index < 0 || index >= screens.size())
        return QImage();
    const QImage shot = screens.at(index)->grabWindow(0).toImage();
    return shot.isNull() ? shot : shot.scaledToWidth(qMax(32, width), Qt::SmoothTransformation);
}

bool ScreenCapture::start(const QString &id)
{
    stop();
    m_latest = QVideoFrame();
    if (id.startsWith(QLatin1String("screen:"))) {
        const QList<QScreen *> screens = QGuiApplication::screens();
        const int index = id.mid(7).toInt();
        if (index < 0 || index >= screens.size())
            return false;
        m_title = tr("Écran %1").arg(index + 1);
        m_session.setWindowCapture(nullptr);
        m_session.setScreenCapture(&m_screenCapture);
        m_screenCapture.setScreen(screens.at(index));
        m_screenCapture.setActive(true);
    } else if (id.startsWith(QLatin1String("window:"))) {
        const int index = id.mid(7).toInt();
        if (index < 0 || index >= m_windows.size() || !m_windows.at(index).isValid())
            return false;
        m_title = m_windows.at(index).description().trimmed();
        m_session.setScreenCapture(nullptr);
        m_session.setWindowCapture(&m_windowCapture);
        m_windowCapture.setWindow(m_windows.at(index));
        m_windowCapture.setActive(true);
    } else {
        return false;
    }
    m_active = true;
    m_tick.start();
    return true;
}

void ScreenCapture::stop()
{
    m_tick.stop();
    m_screenCapture.setActive(false);
    m_windowCapture.setActive(false);
    m_session.setScreenCapture(nullptr);
    m_session.setWindowCapture(nullptr);
    m_latest = QVideoFrame();
    m_active = false;
}

void ScreenCapture::onFrame(const QVideoFrame &frame)
{
    if (m_active)
        m_latest = frame;
}

void ScreenCapture::onTick()
{
    if (!m_latest.isValid())
        return;
    const QImage image = m_latest.toImage();
    m_latest = QVideoFrame();
    if (!image.isNull())
        emit frameReady(image);
}

void ScreenCapture::onError(const QString &message)
{
    if (!m_active)
        return;
    qWarning() << "ScreenCapture:" << message;
    stop();
    const QString hint = permissionHint();
    emit failed(hint.isEmpty() ? message : hint);
}

} // namespace core
