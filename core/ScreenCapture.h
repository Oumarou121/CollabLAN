#ifndef CORE_SCREENCAPTURE_H
#define CORE_SCREENCAPTURE_H

#include <QCapturableWindow>
#include <QImage>
#include <QList>
#include <QMediaCaptureSession>
#include <QObject>
#include <QScreenCapture>
#include <QTimer>
#include <QVideoFrame>
#include <QVideoSink>
#include <QWindowCapture>

namespace core {

/**
 * @brief Capture d'un ecran entier ou d'une fenetre pour le partage d'ecran
 * (Qt Multimedia : QScreenCapture / QWindowCapture vers un QVideoSink).
 *
 * Les images arrivent au rythme de l'ecran ; seule la plus recente est
 * gardee et convertie au plus 10 fois par seconde (frameReady), ce que le
 * partage envoie ensuite par carreaux (network::VoiceService).
 */
class ScreenCapture : public QObject
{
    Q_OBJECT

public:
    struct Source {
        QString id;         ///< "screen:<n>" ou "window:<n>"
        QString kind;       ///< "screen" | "window"
        QString title;      ///< « Écran 1 », titre de la fenetre
        QString detail;     ///< « Principal · 1920 × 1080 »...
    };

    explicit ScreenCapture(QObject *parent = nullptr);
    ~ScreenCapture() override;

    /// Ecrans et fenetres qu'on peut presenter (la liste des fenetres est
    /// gardee : start() designe une fenetre par son rang dans cette liste).
    QList<Source> sources();
    /// Apercu d'un ecran (vide pour une fenetre : Qt n'en fournit pas).
    QImage thumbnail(const QString &id, int width) const;

    bool start(const QString &id);
    void stop();
    bool isActive() const { return m_active; }
    QString title() const { return m_title; }

signals:
    void frameReady(const QImage &frame);
    /// La capture a echoue ou s'est arretee (autorisation refusee, fenetre fermee...).
    void failed(const QString &message);

private:
    void onFrame(const QVideoFrame &frame);
    void onTick();
    void onError(const QString &message);

    QMediaCaptureSession m_session;
    QScreenCapture m_screenCapture;
    QWindowCapture m_windowCapture;
    QVideoSink m_sink;
    QTimer m_tick;
    QVideoFrame m_latest;
    QList<QCapturableWindow> m_windows;
    bool m_active = false;
    QString m_title;
};

} // namespace core

#endif // CORE_SCREENCAPTURE_H
