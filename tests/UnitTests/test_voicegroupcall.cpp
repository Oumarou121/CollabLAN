// Appels de groupe (4 personnes au plus, vous compris) : chaque poste se
// relie directement a chacun des autres. Plusieurs VoiceService tournent ici
// sur la meme machine, chacun sur son port de signalisation ; les sessions
// WebRTC s'etablissent reellement (candidats ICE locaux).
#include <QtTest>
#include <QHostAddress>
#include <QSignalSpy>
#include <QTemporaryDir>

#include <cmath>
#include <cstdint>

#include "Security/SecurityService.h"
#include "Voice/VoiceAudioIO.h"
#include "Voice/VoiceCodec.h"
#include "Voice/VoiceService.h"
#include "Voice/ScreenTiles.h"

using network::CallState;
using network::SecurityService;
using network::VoiceService;

namespace {

struct Station {
    QTemporaryDir dir;
    std::unique_ptr<SecurityService> security;
    std::unique_ptr<VoiceService> voice;
    quint16 port = 0;
};

int joinedCount(VoiceService *voice)
{
    int n = 0;
    for (const auto &p : voice->participants())
        n += p.status == QStringLiteral("joined") ? 1 : 0;
    return n;
}

QByteArray sineFrame(double frequency, double amplitude, int frameIndex)
{
    QByteArray frame(network::kVoiceFrameBytes, Qt::Uninitialized);
    auto *samples = reinterpret_cast<std::int16_t *>(frame.data());
    for (int i = 0; i < network::kVoiceFrameSamples; ++i) {
        const double t = (frameIndex * network::kVoiceFrameSamples + i) / double(network::kVoiceSampleRate);
        samples[i] = static_cast<std::int16_t>(amplitude * 32767.0 * std::sin(6.283185307179586 * frequency * t));
    }
    return frame;
}

QByteArray constantFrame(std::int16_t value)
{
    QByteArray frame(network::kVoiceFrameBytes, Qt::Uninitialized);
    auto *samples = reinterpret_cast<std::int16_t *>(frame.data());
    for (int i = 0; i < network::kVoiceFrameSamples; ++i)
        samples[i] = value;
    return frame;
}

std::int16_t firstSample(const QByteArray &frame)
{
    return *reinterpret_cast<const std::int16_t *>(frame.constData());
}

} // namespace

class TestVoiceGroupCall : public QObject
{
    Q_OBJECT

    std::vector<std::unique_ptr<Station>> m_stations;
    quint16 m_nextPort = 23701;

    Station *station(int i) { return m_stations.at(static_cast<size_t>(i)).get(); }
    VoiceService *voice(int i) { return station(i)->voice.get(); }

    void makeStations(int count)
    {
        m_stations.clear();
        for (int i = 0; i < count; ++i) {
            auto s = std::make_unique<Station>();
            s->security = std::make_unique<SecurityService>(s->dir.path());
            QVERIFY(s->security->initialize());
            s->voice = std::make_unique<VoiceService>(s->security.get());
            s->port = m_nextPort++;
            QVERIFY(s->voice->startListening(s->port));
            m_stations.push_back(std::move(s));
        }
    }

    QPair<QHostAddress, quint16> target(int i) { return qMakePair(QHostAddress(QHostAddress::LocalHost), station(i)->port); }

    // Accepte l'invitation en sonnerie chez chacun des postes donnes.
    void acceptAll(const QList<int> &who)
    {
        for (int i : who) {
            QTRY_COMPARE_WITH_TIMEOUT(voice(i)->state(), CallState::Ringing, 10000);
            voice(i)->acceptCall();
        }
    }

    // Les postes donnes forment un groupe complet : chacun voit les autres.
    void expectMesh(const QList<int> &who)
    {
        for (int i : who) {
            QTRY_COMPARE_WITH_TIMEOUT(joinedCount(voice(i)), static_cast<int>(who.size()) - 1, 20000);
            QCOMPARE(voice(i)->state(), CallState::Connected);
        }
    }

private slots:
    void cleanup()
    {
        for (auto &s : m_stations)
            s->voice->hangUp();
        QTest::qWait(200);
        m_stations.clear();
    }

    // ---- Melange et codec ---------------------------------------------------

    void mixer_waitsForTwoFramesThenSums()
    {
        network::VoiceMixer mixer;
        mixer.push(1, constantFrame(1000));
        QCOMPARE(firstSample(mixer.mixNext()), std::int16_t(0));   // une seule trame : pas encore
        mixer.push(1, constantFrame(1000));
        mixer.push(2, constantFrame(500));
        mixer.push(2, constantFrame(500));
        QCOMPARE(firstSample(mixer.mixNext()), std::int16_t(1500)); // les deux voix additionnees
        QCOMPARE(firstSample(mixer.mixNext()), std::int16_t(1500));
        QCOMPARE(firstSample(mixer.mixNext()), std::int16_t(0));    // files vides : silence
    }

    void mixer_clipsAndDropsBacklog()
    {
        network::VoiceMixer mixer;
        for (int i = 0; i < 2; ++i) {
            mixer.push(1, constantFrame(30000));
            mixer.push(2, constantFrame(30000));
        }
        QCOMPARE(firstSample(mixer.mixNext()), std::int16_t(32767));
        for (int i = 0; i < 20; ++i)
            mixer.push(3, constantFrame(1));
        QVERIFY(mixer.queued(3) <= network::VoiceMixer::kMaxFrames);
    }

    void opus_roundTripKeepsTheVoice()
    {
        network::OpusVoiceEncoder encoder;
        network::OpusVoiceDecoder decoder;
        QVERIFY(encoder.isValid() && decoder.isValid());
        float lastLevel = 0.0f;
        for (int i = 0; i < 25; ++i) {
            const QByteArray packet = encoder.encode(sineFrame(440.0, 0.3, i));
            QVERIFY(!packet.isEmpty());
            QVERIFY(packet.size() < network::kVoiceFrameBytes / 4);   // bien plus leger que le PCM
            const QByteArray pcm = decoder.decode(packet);
            QCOMPARE(pcm.size(), network::kVoiceFrameBytes);
            lastLevel = network::pcm16Level(pcm);
        }
        // Une sinusoide d'amplitude 0,3 a un niveau RMS d'environ 0,21.
        QVERIFY2(lastLevel > 0.12f && lastLevel < 0.3f, qPrintable(QString::number(lastLevel)));
    }

    void pcmu_resamplingKeepsFrameSizes()
    {
        const QByteArray frame = sineFrame(300.0, 0.2, 0);
        const QByteArray narrow = network::resamplePcm16(frame, network::kVoiceSampleRate, network::kPcmuSampleRate);
        QCOMPARE(narrow.size(), network::kPcmuFrameSamples * 2);
        const QByteArray wide = network::resamplePcm16(network::decodeMuLaw(network::encodeMuLaw(narrow)),
                                                       network::kPcmuSampleRate, network::kVoiceSampleRate);
        QCOMPARE(wide.size(), network::kVoiceFrameBytes);
    }

    // ---- Appels -------------------------------------------------------------

    void duoCall_connectsAndEndsForBoth()
    {
        makeStations(2);
        QSignalSpy ended(voice(1), &VoiceService::callEnded);
        QVERIFY(voice(0)->call(QHostAddress::LocalHost, station(1)->port));
        acceptAll({1});
        expectMesh({0, 1});
        QVERIFY(!voice(0)->isGroupCall());

        voice(0)->hangUp();
        QTRY_COMPARE_WITH_TIMEOUT(voice(1)->state(), CallState::Idle, 10000);
        QCOMPARE(ended.count(), 1);
        QCOMPARE(ended.first().at(0).toString(), QStringLiteral("remote-hangup"));
    }

    void groupCall_everyoneIsLinkedToEveryone()
    {
        makeStations(3);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        QVERIFY(voice(0)->isGroupCall());
        acceptAll({1, 2});
        // B et C ne se sont jamais appeles : A les a presentes l'un a l'autre.
        expectMesh({0, 1, 2});
        QVERIFY(voice(1)->isGroupCall());
        QCOMPARE(voice(1)->callParticipantAddresses().size(), 1);   // meme adresse locale pour tous
    }

    void groupCall_invitationShowsWhoIsAlreadyThere()
    {
        makeStations(3);
        QVERIFY(voice(0)->call(QHostAddress::LocalHost, station(1)->port));
        acceptAll({1});
        expectMesh({0, 1});
        QVERIFY(voice(0)->invite(QHostAddress::LocalHost, station(2)->port));
        QTRY_COMPARE_WITH_TIMEOUT(voice(2)->state(), CallState::Ringing, 10000);
        QVERIFY(voice(2)->isGroupCall());
        QCOMPARE(voice(2)->inviteRoster().size(), 1);
        QCOMPARE(voice(2)->inviteRoster().first().port, station(1)->port);
    }

    void leaving_letsTheOthersContinue()
    {
        makeStations(3);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        acceptAll({1, 2});
        expectMesh({0, 1, 2});

        QSignalSpy leftAtA(voice(0), &VoiceService::participantLeft);
        voice(2)->hangUp();
        QTRY_COMPARE_WITH_TIMEOUT(joinedCount(voice(0)), 1, 10000);
        QTRY_COMPARE_WITH_TIMEOUT(joinedCount(voice(1)), 1, 10000);
        QCOMPARE(voice(0)->state(), CallState::Connected);
        QCOMPARE(voice(1)->state(), CallState::Connected);
        QVERIFY(leftAtA.count() >= 1);

        // Il ne reste plus personne avec qui parler : l'appel s'arrete.
        voice(1)->hangUp();
        QTRY_COMPARE_WITH_TIMEOUT(voice(0)->state(), CallState::Idle, 10000);
    }

    void anyParticipantCanInvite()
    {
        makeStations(3);
        QVERIFY(voice(0)->call(QHostAddress::LocalHost, station(1)->port));
        acceptAll({1});
        expectMesh({0, 1});
        // B, invite par A, invite C a son tour : l'appel a deux devient un groupe.
        QVERIFY(voice(1)->invite(QHostAddress::LocalHost, station(2)->port));
        acceptAll({2});
        expectMesh({0, 1, 2});
        QVERIFY(voice(0)->isGroupCall());
    }

    void groupIsLimitedToFourPeople()
    {
        makeStations(5);
        QVERIFY(voice(0)->callGroup({target(1), target(2), target(3)}));
        acceptAll({1, 2, 3});
        expectMesh({0, 1, 2, 3});
        QVERIFY(!voice(0)->canInvite());
        QSignalSpy declined(voice(2), &VoiceService::participantDeclined);
        QVERIFY(!voice(2)->invite(QHostAddress::LocalHost, station(4)->port));
        QCOMPARE(declined.count(), 1);
        QCOMPARE(declined.first().at(1).toString(), QStringLiteral("full"));
        QTest::qWait(500);
        QCOMPARE(voice(4)->state(), CallState::Idle);
    }

    void stationInAnotherCallAnswersBusy()
    {
        makeStations(3);
        QVERIFY(voice(0)->call(QHostAddress::LocalHost, station(1)->port));
        acceptAll({1});
        expectMesh({0, 1});

        QSignalSpy declined(voice(2), &VoiceService::participantDeclined);
        QVERIFY(voice(2)->call(QHostAddress::LocalHost, station(1)->port));
        QTRY_COMPARE_WITH_TIMEOUT(declined.count(), 1, 10000);
        QCOMPARE(declined.first().at(1).toString(), QStringLiteral("busy"));
        QTRY_COMPARE_WITH_TIMEOUT(voice(2)->state(), CallState::Idle, 10000);
        QCOMPARE(voice(1)->state(), CallState::Connected);
        QCOMPARE(joinedCount(voice(1)), 1);
    }

    void oneRefusalDoesNotStopTheGroup()
    {
        makeStations(3);
        QSignalSpy declined(voice(0), &VoiceService::participantDeclined);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        QTRY_COMPARE_WITH_TIMEOUT(voice(1)->state(), CallState::Ringing, 10000);
        voice(1)->hangUp();                       // B refuse
        acceptAll({2});
        expectMesh({0, 2});
        QTRY_COMPARE_WITH_TIMEOUT(declined.count(), 1, 10000);
        QCOMPARE(declined.first().at(1).toString(), QStringLiteral("declined"));
        QCOMPARE(voice(0)->participants().size(), 1);
    }

    // ---- Partage d'ecran ----------------------------------------------------

    void screenTiles_onlyChangedTilesAreResent()
    {
        QImage frame(640, 360, QImage::Format_RGB32);
        frame.fill(Qt::white);
        network::ScreenTileEncoder encoder;
        encoder.setFrame(frame);
        QCOMPARE(encoder.tileCount(), 5 * 3);
        network::ScreenViewerState viewer;
        QCOMPARE(encoder.pendingTiles(viewer).size(), 15);   // nouveau venu : tout l'ecran

        network::ScreenCanvas canvas;
        viewer.frameSize = encoder.frameSize();
        for (int i : encoder.pendingTiles(network::ScreenViewerState{})) {
            QVERIFY(canvas.apply(encoder.tileMessage(i)));
            viewer.sent.insert(i, encoder.tileHash(i));
        }
        QCOMPARE(canvas.image().size(), QSize(640, 360));
        QVERIFY(encoder.pendingTiles(viewer).isEmpty());

        // Un rectangle rouge dans un seul carreau : seul celui-ci repart.
        for (int y = 140; y < 160; ++y)
            for (int x = 300; x < 330; ++x)
                frame.setPixel(x, y, qRgb(220, 0, 0));
        encoder.setFrame(frame);
        const QVector<int> changed = encoder.pendingTiles(viewer);
        QCOMPARE(changed.size(), 1);
        QVERIFY(canvas.apply(encoder.tileMessage(changed.first())));
        const QColor pixel = canvas.image().pixelColor(315, 150);
        QVERIFY2(pixel.red() > 180 && pixel.green() < 60, qPrintable(pixel.name()));
        QVERIFY(qGray(canvas.image().pixel(20, 20)) > 240);

        QVERIFY(network::isScreenRefreshRequest(network::screenRefreshRequest()));
        QVERIFY(!canvas.apply(network::screenFrameEndMessage(3, false)));
        QVERIFY(canvas.lastFrameIncomplete());
    }

    void screenShare_viewersSeeThePresentersScreen()
    {
        makeStations(3);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        acceptAll({1, 2});
        expectMesh({0, 1, 2});

        QSignalSpy started(voice(1), &VoiceService::presentationChanged);
        QVERIFY(voice(1)->canPresent());
        QVERIFY(voice(1)->startPresenting(QStringLiteral("Écran 1")));
        // Une presentation a la fois : les autres ne peuvent plus presenter.
        QTRY_VERIFY_WITH_TIMEOUT(!voice(0)->canPresent(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!voice(2)->presenterAddress().isNull(), 10000);
        QVERIFY(!voice(2)->startPresenting(QStringLiteral("Écran 2")));
        QCOMPARE(voice(0)->presenterTitle(), QStringLiteral("Écran 1"));

        QImage frame(800, 450, QImage::Format_RGB32);
        frame.fill(QColor(30, 90, 200));
        voice(1)->pushScreenFrame(frame);
        for (int i : {0, 2}) {
            QTRY_COMPARE_WITH_TIMEOUT(voice(i)->remoteScreen().size(), QSize(800, 450), 10000);
            QTRY_VERIFY_WITH_TIMEOUT(voice(i)->remoteScreen().pixelColor(400, 225).blue() > 170, 10000);
        }

        // Une zone change : les spectateurs la recoivent.
        for (int y = 0; y < 100; ++y)
            for (int x = 0; x < 100; ++x)
                frame.setPixel(x, y, qRgb(250, 250, 0));
        voice(1)->pushScreenFrame(frame);
        QTRY_VERIFY_WITH_TIMEOUT(voice(2)->remoteScreen().pixelColor(50, 50).red() > 200, 10000);

        voice(1)->stopPresenting();
        QTRY_VERIFY_WITH_TIMEOUT(voice(0)->presenterAddress().isNull(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(voice(2)->canPresent(), 10000);
        QVERIFY(voice(0)->remoteScreen().isNull());
        QVERIFY(started.count() >= 2);
    }

    void screenShare_lateViewerGetsTheWholeScreen()
    {
        makeStations(3);
        QVERIFY(voice(0)->call(QHostAddress::LocalHost, station(1)->port));
        acceptAll({1});
        expectMesh({0, 1});
        QVERIFY(voice(0)->startPresenting(QStringLiteral("Bilan.xlsx")));
        QImage frame(512, 256, QImage::Format_RGB32);
        frame.fill(QColor(0, 160, 60));
        voice(0)->pushScreenFrame(frame);
        QTRY_COMPARE_WITH_TIMEOUT(voice(1)->remoteScreen().size(), QSize(512, 256), 10000);

        // C rejoint pendant la presentation : il recoit l'ecran sans nouvelle capture.
        QVERIFY(voice(0)->invite(QHostAddress::LocalHost, station(2)->port));
        acceptAll({2});
        expectMesh({0, 1, 2});
        QTRY_COMPARE_WITH_TIMEOUT(voice(2)->remoteScreen().size(), QSize(512, 256), 15000);
        QTRY_VERIFY_WITH_TIMEOUT(voice(2)->remoteScreen().pixelColor(256, 128).green() > 120, 10000);
    }

    void screenShare_presenterLeavingEndsThePresentation()
    {
        makeStations(3);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        acceptAll({1, 2});
        expectMesh({0, 1, 2});
        QVERIFY(voice(2)->startPresenting(QStringLiteral("Écran 1")));
        QTRY_VERIFY_WITH_TIMEOUT(!voice(0)->presenterAddress().isNull(), 10000);
        voice(2)->hangUp();
        QTRY_VERIFY_WITH_TIMEOUT(voice(0)->presenterAddress().isNull(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(voice(0)->canPresent(), 10000);
    }

    void cancellingBeforeAnyAnswerStopsTheRinging()
    {
        makeStations(3);
        QVERIFY(voice(0)->callGroup({target(1), target(2)}));
        QTRY_COMPARE_WITH_TIMEOUT(voice(1)->state(), CallState::Ringing, 10000);
        QTRY_COMPARE_WITH_TIMEOUT(voice(2)->state(), CallState::Ringing, 10000);
        QSignalSpy endedB(voice(1), &VoiceService::callEnded);
        voice(0)->hangUp();
        QTRY_COMPARE_WITH_TIMEOUT(voice(1)->state(), CallState::Idle, 10000);
        QTRY_COMPARE_WITH_TIMEOUT(voice(2)->state(), CallState::Idle, 10000);
        QCOMPARE(endedB.first().at(0).toString(), QStringLiteral("remote-hangup"));
    }
};

QTEST_GUILESS_MAIN(TestVoiceGroupCall)
#include "test_voicegroupcall.moc"
