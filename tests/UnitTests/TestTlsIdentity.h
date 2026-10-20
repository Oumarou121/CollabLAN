#ifndef TESTS_TESTTLSIDENTITY_H
#define TESTS_TESTTLSIDENTITY_H

#include <QTemporaryDir>
#include <memory>

#include "Security/SecurityService.h"

/// Identite TLS partagee par les tests de transfert.
///
/// TransferService chiffre toutes ses connexions : sans certificat local, configureTls() echoue
/// et plus aucun fichier ne part (cause des echecs des tests de transfert ecrits avant le passage
/// a TLS). Une seule identite suffit, y compris quand l'expediteur et le destinataire sont deux
/// services du meme processus : la generation de cle RSA n'a alors lieu qu'une fois.
inline network::SecurityService *testTlsIdentity()
{
    static QTemporaryDir dir;
    static std::unique_ptr<network::SecurityService> service = [] {
        auto created = std::make_unique<network::SecurityService>(dir.path());
        created->initialize();
        return created;
    }();
    return service.get();
}

#endif // TESTS_TESTTLSIDENTITY_H
