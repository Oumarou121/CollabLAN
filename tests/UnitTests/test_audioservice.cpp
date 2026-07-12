#include <QtTest>

#include "AudioService.h"

using services::AudioService;

class TestAudioService : public QObject
{
    Q_OBJECT

private slots:
    void soundEnabled_defaultsToTrue()
    {
        AudioService audioService;
        QVERIFY(audioService.isSoundEnabled());
    }

    void setSoundEnabled_canBeToggled()
    {
        AudioService audioService;

        audioService.setSoundEnabled(false);
        QVERIFY(!audioService.isSoundEnabled());

        audioService.setSoundEnabled(true);
        QVERIFY(audioService.isSoundEnabled());
    }

    void playSound_doesNotBlockWhenDisabled()
    {
        AudioService audioService;
        audioService.setSoundEnabled(false);

        // Ne doit pas planter ni bloquer meme sans backend audio
        // disponible (environnement de test headless).
        audioService.playSound(AudioService::EventType::Message);
        audioService.playSound(AudioService::EventType::Transfer);
        audioService.playSound(AudioService::EventType::Call);
    }

    void playSound_eachEventTypeCanBeInvoked()
    {
        AudioService audioService;

        // Un son distinct est associe a chaque type d'evenement
        // (criteres d'acceptation de l'issue #56) : on verifie ici que
        // chaque type peut etre joue sans erreur, la lecture reelle
        // dependant du backend audio de la plateforme.
        audioService.playMessageSound();
        audioService.playTransferSound();
        audioService.playCallSound();
    }

    void volume_isClampedBetweenZeroAndOne()
    {
        AudioService audioService;

        audioService.setVolume(2.0);
        QCOMPARE(audioService.volume(), 1.0);

        audioService.setVolume(-1.0);
        QCOMPARE(audioService.volume(), 0.0);

        audioService.setVolume(0.5);
        QCOMPARE(audioService.volume(), 0.5);
    }
};

QTEST_MAIN(TestAudioService)
#include "test_audioservice.moc"
