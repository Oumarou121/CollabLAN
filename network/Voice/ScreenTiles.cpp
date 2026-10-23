#include "ScreenTiles.h"

#include <QBuffer>
#include <QPainter>
#include <QtEndian>

#include <cstring>

namespace network {

namespace {

enum MessageType : quint8 { TileMessage = 1, FrameEndMessage = 2, RefreshRequest = 3, MotionMessage = 4 };
// type(1) + largeur, hauteur de l'image(2+2).
constexpr int kMotionHeaderBytes = 1 + 2 * 2;
// type(1) + largeur, hauteur de l'ecran(2+2) + x, y, w, h du carreau(4x2).
constexpr int kTileHeaderBytes = 1 + 2 * 6;

void putU16(char *at, int value) { qToBigEndian(static_cast<quint16>(value), at); }
int getU16(const char *at) { return qFromBigEndian<quint16>(at); }

} // namespace

void ScreenTileEncoder::setFrame(const QImage &frame)
{
    if (frame.isNull())
        return;
    QImage image = frame.width() > kScreenMaxWidth
        ? frame.scaledToWidth(kScreenMaxWidth, Qt::SmoothTransformation) : frame;
    // Format unique (32 bits, opaque) : empreinte stable d'une capture a l'autre.
    if (image.format() != QImage::Format_RGB32)
        image = image.convertToFormat(QImage::Format_RGB32);
    m_frame = image;
    m_messages.clear();
    ++m_sequence;

    m_columns = (image.width() + kScreenTileSize - 1) / kScreenTileSize;
    const int rows = (image.height() + kScreenTileSize - 1) / kScreenTileSize;
    m_hashes.resize(m_columns * rows);
    for (int row = 0; row < rows; ++row) {
        const int y0 = row * kScreenTileSize;
        const int y1 = qMin(y0 + kScreenTileSize, image.height());
        for (int col = 0; col < m_columns; ++col) {
            const int x0 = col * kScreenTileSize;
            const int w = qMin(kScreenTileSize, image.width() - x0);
            quint64 hash = 1469598103934665603ULL ^ static_cast<quint64>(w * 31 + (y1 - y0));
            for (int y = y0; y < y1; ++y) {
                const uchar *line = image.constScanLine(y) + x0 * 4;
                hash = hash * 1099511628211ULL ^ qHashBits(line, static_cast<size_t>(w) * 4, 0);
            }
            m_hashes[row * m_columns + col] = hash;
        }
    }
}

QVector<int> ScreenTileEncoder::pendingTiles(const ScreenViewerState &viewer) const
{
    QVector<int> pending;
    const bool fresh = viewer.frameSize != m_frame.size();
    for (int i = 0; i < m_hashes.size(); ++i) {
        const auto it = viewer.sent.constFind(i);
        if (fresh || it == viewer.sent.constEnd() || it.value() != m_hashes.at(i))
            pending.append(i);
    }
    return pending;
}

QByteArray ScreenTileEncoder::tileMessage(int index)
{
    const auto cached = m_messages.constFind(index);
    if (cached != m_messages.constEnd())
        return cached.value();
    if (m_columns <= 0 || index < 0 || index >= m_hashes.size())
        return QByteArray();

    const int x = (index % m_columns) * kScreenTileSize;
    const int y = (index / m_columns) * kScreenTileSize;
    const int w = qMin(kScreenTileSize, m_frame.width() - x);
    const int h = qMin(kScreenTileSize, m_frame.height() - y);

    QByteArray jpeg;
    QBuffer buffer(&jpeg);
    buffer.open(QIODevice::WriteOnly);
    m_frame.copy(x, y, w, h).save(&buffer, "JPG", kScreenJpegQuality);

    QByteArray message(kTileHeaderBytes, Qt::Uninitialized);
    char *d = message.data();
    d[0] = static_cast<char>(TileMessage);
    putU16(d + 1, m_frame.width());
    putU16(d + 3, m_frame.height());
    putU16(d + 5, x);
    putU16(d + 7, y);
    putU16(d + 9, w);
    putU16(d + 11, h);
    message.append(jpeg);
    m_messages.insert(index, message);
    return message;
}

QByteArray screenMotionMessage(const QImage &frame)
{
    if (frame.isNull())
        return QByteArray();
    // Reduite puis compressee ; encore plus petite si le canal ne la prend pas.
    int width = qMin(kScreenMotionWidth, frame.width());
    int quality = kScreenMotionQuality;
    QByteArray jpeg;
    QImage image;
    for (int attempt = 0; attempt < 3; ++attempt) {
        image = frame.width() > width ? frame.scaledToWidth(width, Qt::SmoothTransformation) : frame;
        jpeg.clear();
        QBuffer buffer(&jpeg);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "JPG", quality);
        if (jpeg.size() <= kScreenMotionMaxBytes)
            break;
        width = width * 3 / 4;
        quality -= 15;
    }
    QByteArray message(kMotionHeaderBytes, Qt::Uninitialized);
    char *d = message.data();
    d[0] = static_cast<char>(MotionMessage);
    putU16(d + 1, image.width());
    putU16(d + 3, image.height());
    message.append(jpeg);
    return message;
}

void ScreenFrameAnalyzer::reset()
{
    m_previous.clear();
    m_previousSize = QSize();
    m_motion = false;
    m_calmFrames = 0;
}

ScreenPacket ScreenFrameAnalyzer::analyze(const QImage &capture, bool full)
{
    ScreenPacket packet;
    if (capture.isNull())
        return packet;
    auto tiles = std::make_shared<ScreenTileEncoder>();
    tiles->setFrame(capture);
    packet.tiles = tiles;
    packet.sequence = ++m_sequence;

    // Part de l'ecran modifiee depuis la capture precedente.
    QVector<int> changed;
    const bool sameSize = m_previousSize == tiles->frameSize() && m_previous.size() == tiles->tileCount();
    for (int i = 0; i < tiles->tileCount(); ++i) {
        if (!sameSize || m_previous.at(i) != tiles->tileHash(i))
            changed.append(i);
    }
    const double ratio = tiles->tileCount() > 0 ? double(changed.size()) / tiles->tileCount() : 0.0;
    m_previous.resize(tiles->tileCount());
    for (int i = 0; i < tiles->tileCount(); ++i)
        m_previous[i] = tiles->tileHash(i);
    m_previousSize = tiles->frameSize();

    // Hysteresis : on entre en mouvement au-dela d'un tiers de l'ecran, on
    // n'en sort qu'apres quelques images calmes (une video qui marque une
    // courte pause ne fait pas basculer d'un mode a l'autre).
    const bool wasMotion = m_motion;
    if (!m_motion) {
        m_motion = sameSize && ratio > kEnterMotionRatio;
        m_calmFrames = 0;
    } else if (ratio < kLeaveMotionRatio) {
        if (++m_calmFrames >= kCalmFramesToLeave)
            m_motion = false;
    } else {
        m_calmFrames = 0;
    }

    if (m_motion) {
        packet.motion = screenMotionMessage(tiles->frame());
    } else {
        packet.motionEnded = wasMotion;
        // Compression faite ici, hors de l'interface : carreaux modifies (ou
        // tout l'ecran au retour du mode mouvement).
        if (packet.motionEnded || full) {
            for (int i = 0; i < tiles->tileCount(); ++i)
                tiles->tileMessage(i);
        } else {
            for (int i : changed)
                tiles->tileMessage(i);
        }
    }
    return packet;
}

QByteArray screenFrameEndMessage(quint32 sequence, bool complete)
{
    QByteArray message(6, Qt::Uninitialized);
    message[0] = static_cast<char>(FrameEndMessage);
    qToBigEndian(sequence, message.data() + 1);
    message[5] = complete ? 1 : 0;
    return message;
}

QByteArray screenRefreshRequest()
{
    return QByteArray(1, static_cast<char>(RefreshRequest));
}

bool isScreenRefreshRequest(const QByteArray &message)
{
    return message.size() == 1 && static_cast<quint8>(message.at(0)) == RefreshRequest;
}

bool ScreenCanvas::apply(const QByteArray &message)
{
    if (message.isEmpty())
        return false;
    const char *d = message.constData();
    const auto type = static_cast<quint8>(d[0]);
    if (type == FrameEndMessage) {
        if (message.size() >= 6)
            m_lastIncomplete = d[5] == 0;
        return false;
    }
    if (type == MotionMessage) {
        if (message.size() <= kMotionHeaderBytes)
            return false;
        QImage frame;
        if (!frame.loadFromData(reinterpret_cast<const uchar *>(d + kMotionHeaderBytes),
                                static_cast<int>(message.size() - kMotionHeaderBytes), "JPG"))
            return false;
        // L'image entiere remplace l'ecran (a sa taille reduite) ; l'affichage
        // l'agrandit. Les carreaux nets la recouvriront au retour au calme.
        m_image = frame.convertToFormat(QImage::Format_RGB32);
        return true;
    }
    if (type != TileMessage || message.size() <= kTileHeaderBytes)
        return false;

    const int frameW = getU16(d + 1), frameH = getU16(d + 3);
    const int x = getU16(d + 5), y = getU16(d + 7), w = getU16(d + 9), h = getU16(d + 11);
    if (frameW <= 0 || frameH <= 0 || frameW > 8192 || frameH > 8192
        || x + w > frameW || y + h > frameH || w <= 0 || h <= 0)
        return false;

    QImage tile;
    if (!tile.loadFromData(reinterpret_cast<const uchar *>(d + kTileHeaderBytes),
                           static_cast<int>(message.size() - kTileHeaderBytes), "JPG"))
        return false;

    if (m_image.size() != QSize(frameW, frameH)) {
        // Changement de taille (retour du mode mouvement, autre ecran) : la
        // derniere image, agrandie, sert de fond le temps que les carreaux
        // arrivent ; sinon un fond neutre.
        if (!m_image.isNull()) {
            m_image = m_image.scaled(frameW, frameH, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                          .convertToFormat(QImage::Format_RGB32);
        } else {
            m_image = QImage(frameW, frameH, QImage::Format_RGB32);
            m_image.fill(QColor(0x2a, 0x2c, 0x33));
        }
    }
    QPainter painter(&m_image);
    painter.drawImage(x, y, tile);
    return true;
}

void ScreenCanvas::clear()
{
    m_image = QImage();
    m_lastIncomplete = false;
}

} // namespace network
