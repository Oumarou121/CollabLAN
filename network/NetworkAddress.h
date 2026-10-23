#ifndef NETWORK_NETWORKADDRESS_H
#define NETWORK_NETWORKADDRESS_H

#include <QHostAddress>
#include <QString>

namespace network {

/// Adresse sous sa forme canonique : une adresse IPv4 rapportee au format
/// IPv6 par une socket double pile ("::ffff:192.168.1.21") redevient
/// l'adresse IPv4 qu'elle est ("192.168.1.21"). Sans cela, le meme poste
/// apparaissait sous deux adresses differentes (comparaisons ratees) et
/// l'interface affichait "::ffff:..." comme nom de poste.
inline QHostAddress canonicalAddress(const QHostAddress &address)
{
    bool isIPv4 = false;
    const quint32 ipv4 = address.toIPv4Address(&isIPv4);
    return isIPv4 ? QHostAddress(ipv4) : address;
}

/// Texte d'une adresse pour l'enregistrement et l'affichage (forme canonique).
inline QString displayAddress(const QHostAddress &address)
{
    return address.isNull() ? QString() : canonicalAddress(address).toString();
}

/// Meme chose pour une adresse deja sous forme de texte ; un texte qui n'est
/// pas une adresse est rendu tel quel.
inline QString displayAddress(const QString &address)
{
    const QHostAddress parsed(address.trimmed());
    return parsed.isNull() ? address : displayAddress(parsed);
}

} // namespace network

#endif // NETWORK_NETWORKADDRESS_H
