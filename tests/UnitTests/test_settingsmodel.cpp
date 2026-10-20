#include <QtTest>
#include <QSettings>
#include <QStandardPaths>

#include "SettingsModel.h"

/*
 * core::SettingsModel : persistance des reglages globaux (QSettings).
 *
 * Ce test couvre en particulier `machineName`, ajoute parce que le README
 * annoncait un reglage "nom du poste" qui n'existait nulle part : le nom
 * diffuse aux autres postes etait fige sur QHostInfo::localHostName(), donc
 * deux machines au nom Windows generique etaient indiscernables dans la
 * liste des pairs.
 *
 * QStandardPaths::setTestModeEnabled() redirige QSettings vers un
 * emplacement de test : les reglages reels de l'utilisateur ne sont jamais
 * touches par ce test.
 */
class TestSettingsModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName(QStringLiteral("LocaLinkTests"));
        QCoreApplication::setApplicationName(QStringLiteral("test_settingsmodel"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
    }

    void init()
    {
        QSettings settings;
        settings.clear();
        settings.sync();
    }

    void cleanupTestCase()
    {
        QSettings settings;
        settings.clear();
        settings.sync();
    }

    void machineNameDefaultsToEmptyMeaningHostName()
    {
        core::SettingsModel model;
        // Vide = "utiliser le nom d'hote", c'est-a-dire le comportement
        // d'avant ce reglage : aucune migration n'est necessaire.
        QVERIFY(model.machineName().isEmpty());
    }

    void machineNameIsTrimmedAndEmitsChangeOnlyWhenItChanges()
    {
        core::SettingsModel model;
        QSignalSpy spy(&model, &core::SettingsModel::machineNameChanged);

        model.setMachineName(QStringLiteral("  Poste Accueil  "));
        QCOMPARE(model.machineName(), QStringLiteral("Poste Accueil"));
        QCOMPARE(spy.count(), 1);

        // Meme valeur (aux espaces pres) : pas de signal superflu, sinon
        // chaque frappe reappliquerait le nom a DiscoveryService.
        model.setMachineName(QStringLiteral("Poste Accueil"));
        QCOMPARE(spy.count(), 1);
    }

    void machineNameSurvivesSaveAndReload()
    {
        {
            core::SettingsModel model;
            model.setMachineName(QStringLiteral("Poste Comptabilite"));
            model.save();
        }

        // Nouvelle instance : load() est appele par le constructeur.
        core::SettingsModel reloaded;
        QCOMPARE(reloaded.machineName(), QStringLiteral("Poste Comptabilite"));
    }

    void loadRestoresPreviouslySavedValuesAndDiscardsUnsavedEdits()
    {
        core::SettingsModel model;
        model.setMachineName(QStringLiteral("Poste A"));
        model.save();

        // Edition non enregistree puis "Annuler" (SettingsView appelle load()).
        model.setMachineName(QStringLiteral("Poste B"));
        model.load();
        QCOMPARE(model.machineName(), QStringLiteral("Poste A"));
    }
};

QTEST_MAIN(TestSettingsModel)
#include "test_settingsmodel.moc"
