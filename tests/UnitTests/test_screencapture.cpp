// Partage d'ecran : la capture reelle de l'ecran principal fournit des images
// (Qt Multimedia, QScreenCapture). Ignore sur une machine sans ecran (CI,
// plateforme offscreen) ou sans autorisation de capture.
#include <QtTest>
#include <QGuiApplication>
#include <QSignalSpy>

#include "ScreenCapture.h"

class TestScreenCapture : public QObject
{
    Q_OBJECT

private slots:
    void listsAtLeastTheScreens()
    {
        core::ScreenCapture capture;
        const auto sources = capture.sources();
        int screens = 0;
        for (const auto &s : sources)
            screens += s.kind == QStringLiteral("screen") ? 1 : 0;
        QCOMPARE(screens, QGuiApplication::screens().size());
        if (screens > 0)
            QCOMPARE(sources.first().title, QStringLiteral("Écran 1"));
    }

    void primaryScreenProducesFrames()
    {
        if (QGuiApplication::platformName() == QStringLiteral("offscreen") || QGuiApplication::screens().isEmpty())
            QSKIP("Pas d'ecran reel sur cette machine");
        core::ScreenCapture capture;
        capture.sources();
        QSignalSpy frames(&capture, &core::ScreenCapture::frameReady);
        QSignalSpy failed(&capture, &core::ScreenCapture::failed);
        QVERIFY(capture.start(QStringLiteral("screen:0")));
        QTRY_VERIFY_WITH_TIMEOUT(frames.count() > 0 || failed.count() > 0, 5000);
        if (failed.count() > 0)
            QSKIP(qPrintable(QStringLiteral("Capture refusee : ") + failed.first().at(0).toString()));
        const QImage image = frames.first().at(0).value<QImage>();
        QVERIFY(!image.isNull());
        QVERIFY(image.width() >= 320);
        capture.stop();
        QVERIFY(!capture.isActive());
    }
};

QTEST_MAIN(TestScreenCapture)
#include "test_screencapture.moc"
