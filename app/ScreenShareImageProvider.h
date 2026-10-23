#ifndef APP_SCREENSHAREIMAGEPROVIDER_H
#define APP_SCREENSHAREIMAGEPROVIDER_H

#include <QPointer>
#include <QQuickImageProvider>

#include "CallContext.h"

/**
 * @brief Images du partage d'ecran pour le QML :
 *   image://screenshare/remote/<n>       ecran du participant qui presente
 *   image://screenshare/local/<n>        votre ecran (apercu de la bande)
 *   image://screenshare/thumb/<id>/<n>   apercu d'un ecran dans le choix
 * <n> change a chaque nouvelle image pour que l'Image QML la recharge
 * (cache: false). Servies sur le thread de l'interface : rien a verrouiller.
 */
class ScreenShareImageProvider : public QQuickImageProvider
{
public:
    explicit ScreenShareImageProvider(core::CallContext *call)
        : QQuickImageProvider(QQuickImageProvider::Image)
        , m_call(call)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        QImage image;
        if (m_call) {
            const QStringList parts = id.split(QLatin1Char('/'));
            const QString kind = parts.value(0);
            if (kind == QLatin1String("remote"))
                image = m_call->remoteScreen();
            else if (kind == QLatin1String("local"))
                image = m_call->localScreen();
            else if (kind == QLatin1String("thumb"))
                image = m_call->sourceThumbnail(parts.value(1));
        }
        if (image.isNull()) {
            // Image vide plutot qu'une erreur : l'ecran attend sa premiere image.
            image = QImage(16, 9, QImage::Format_RGB32);
            image.fill(QColor(0x2a, 0x2c, 0x33));
        }
        if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.width() < image.width())
            image = image.scaledToWidth(requestedSize.width(), Qt::SmoothTransformation);
        if (size)
            *size = image.size();
        return image;
    }

private:
    QPointer<core::CallContext> m_call;
};

#endif // APP_SCREENSHAREIMAGEPROVIDER_H
