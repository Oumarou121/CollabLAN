---
name: TrustedPeerStore requires explicit approval UI
description: network::TrustedPeerStore (TLS whitelist) never auto-trusts peers; any channel wired through TlsHandshakeService needs a way for an admin to approve pending fingerprints or it will silently reject every connection.
---

`network::TrustedPeerStore` is a persistent whitelist keyed by certificate
SHA-256 fingerprint. By explicit design it never trusts a peer automatically
(no trust-on-first-use) — `TlsHandshakeService` rejects any peer not already
in the store, even on a first-ever connection between two freshly installed
machines.

**Why:** This is intentional (see the class's own doc comment), but it means
simply routing an existing plaintext network channel through
`TlsHandshakeService` for encryption is not enough to keep it working: with
an empty store, every handshake gets rejected and the feature appears
completely broken with no obvious error surfaced to the end user.

**How to apply:** When adding TLS to a channel via `TlsHandshakeService`,
also surface `handshakeRejected` (fingerprint + address) somewhere an admin
can see it and call `trustPeer()` — e.g. a simple pending-peers panel. Do not
bypass the whitelist by auto-trusting discovered peers as a shortcut; that
contradicts the component's stated security intent.
