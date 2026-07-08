# How CollabLAN Works

## Purpose of this document

This document describes **how CollabLAN works in practice** once deployed on a local network, through a reference scenario involving **three machines**. It complements the [Requirements Specification](Cahier_des_charges.pdf) (needs) and [ARCHITECTURE.md](ARCHITECTURE.md) (code structure) by explaining how network exchanges actually unfold, machine by machine, feature by feature.

---

## Reference Scenario

Consider three computers connected to the same local network (same subnet, e.g. Wi-Fi or a company switch):

```
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│     PC-A      │      │     PC-B      │      │     PC-C      │
│  Alice        │      │  Bilal        │      │  Chaima       │
│  192.168.1.10 │      │  192.168.1.11 │      │  192.168.1.12 │
└───────┬───────┘      └───────┬───────┘      └───────┬───────┘
        │                      │                      │
        └──────────────┬───────┴──────────┬───────────┘
                        │   Local network (LAN)         │
                        └───────────────────────────────┘
```

Each machine runs an instance of CollabLAN. **No Internet connection** is required. The mode used here is **Peer-to-Peer** mode (each machine is both a client and a server); **Local Server** mode works on the same principle but with one machine acting as a central server.

---

## 1. Application Startup

On launch, each CollabLAN instance:

1. Loads local settings (machine name, language, theme, download folder — see `Settings`).
2. Initializes the `Security` module (OpenSSL): generates or loads the machine's certificate/key.
3. Starts the network services: UDP listening (discovery), TCP listening (transfers), WebSocket server (messaging).
4. Launches the `Discovery` module, which starts announcing itself and listening for other machines.

At this point, PC-A, PC-B, and PC-C are each running independently, without yet knowing about one another.

---

## 2. Automatic Discovery (UDP)

**Protocol: UDP (broadcast/multicast)**

1. PC-A periodically sends a **UDP broadcast packet** on the local network containing: its identifier, machine name, IP address, and status (online).
2. PC-B and PC-C, listening on the same UDP port, receive this packet and add it to their **list of connected users**.
3. Symmetrically, PC-B and PC-C also send their own announcements, which PC-A receives.
4. If a machine disconnects (app closed or no announcement within the timeout), the other machines remove it from their list and display a **disconnection notification**.

```
PC-A  ── UDP broadcast (announcement) ──►  PC-B, PC-C
PC-B  ── UDP broadcast (announcement) ──►  PC-A, PC-C
PC-C  ── UDP broadcast (announcement) ──►  PC-A, PC-B
```

Result: Alice sees Bilal and Chaima "online" in her interface, and vice versa.

---

## 3. Authentication and Security

**Protocol: OpenSSL (TLS) on top of TCP/WebSocket**

Before any content is exchanged (message, file, call), a **secure handshake** takes place between the two machines involved:

1. The initiating machine (e.g. PC-A) establishes an encrypted (TLS) connection to the destination machine (PC-B).
2. Certificates are verified: only **authorized machines** (a list managed by the administration) can establish a session.
3. Once the session is validated, all exchanges between PC-A and PC-B (messages, files, voice) travel encrypted over this channel.

If PC-C is not authorized by the network administrator (e.g. an unapproved machine), any connection attempt is rejected and logged in the audit trail as a refused attempt.

---

## 4. Messaging (Individual and Group)

**Protocol: WebSocket (over an encrypted connection)**

### Individual message

1. Alice (PC-A) opens a conversation with Bilal (PC-B) and types a message.
2. The message is sent via **WebSocket** directly to PC-B (channel already authenticated in step 3).
3. PC-B receives the message, displays it in the interface, saves it to the local history (SQLite), and triggers a **notification**.
4. An acknowledgment may be sent back to PC-A (status "delivered" / "read").

### Group message

1. Alice creates a group including Bilal and Chaima.
2. When she sends a message to the group, CollabLAN broadcasts the message **in parallel** to PC-B and PC-C via WebSocket.
3. Each machine receives, displays, and saves the message to the group history.

```
PC-A ──message──► PC-B   (individual conversation)

PC-A ──message──┬─► PC-B
                 └─► PC-C   (group conversation)
```

---

## 5. File Sharing

**Protocol: TCP**

1. Chaima (PC-C) selects a file to send to Alice (PC-A).
2. CollabLAN opens a **dedicated TCP connection** between PC-C and PC-A for this transfer (separate from the messaging channel).
3. The file is transferred in chunks; a **progress bar** is displayed in real time on both machines.
4. In case of interruption (network loss, app closing), the transfer can be **resumed** from the last received chunk, without starting over.
5. At the end of the transfer, PC-A receives a **notification** and the file is placed in the configured download folder (`Settings`).
6. The operation is logged in the audit trail on both sides (send / receive).

```
PC-C ── dedicated TCP connection ── file sent (in chunks) ──► PC-A
                                        │
                                progress + resume support
```

---

## 6. Notifications

Every significant event triggers a local notification on the relevant machine:

| Event | Triggered by |
|---|---|
| New message | WebSocket reception |
| File transfer completed / failed | `Transfer` module (TCP) |
| User connected / disconnected | `Discovery` module (UDP) |
| Incoming call | `Voice` module (WebRTC) |

Example: when Bilal (PC-B) receives a message from Alice while the chat window isn't active, a system notification appears (sound + visual alert, based on `Settings`).

---

## 7. Voice Calls

**Protocol: WebRTC**

1. Alice (PC-A) starts a call to Bilal (PC-B).
2. PC-B receives an **incoming call notification** with answer/decline options.
3. If Bilal answers, a **WebRTC** session is established directly between PC-A and PC-B for the audio stream (peer-to-peer, low latency, well suited to a LAN).
4. The call status (ongoing, ended, declined, missed) is displayed in real time on both interfaces.
5. At the end of the call, the event (duration, participants) is logged in the audit trail.

```
PC-A ── call invitation (signaling) ──► PC-B
PC-A ◄──────── WebRTC audio stream ────────────► PC-B
```

---

## 8. Audit Log

Each machine (or the local server, in Server mode) records locally in SQLite (table `AuditLogs`):

- Connections / disconnections (from `Discovery`)
- Messages sent/received (metadata, not necessarily the content)
- File transfers (send/receive, success/failure)
- Calls (duration, participants, status)
- Refused connection attempts (unauthorized machines)

An administrator (e.g. Alice, if she has the admin role) can view and **export** these logs from the administration screen.

---

## 9. Administration

A user with administration rights can, from their machine:

- Manage the list of **authorized machines** on the network (approve/revoke PC-B, PC-C…)
- Manage **user accounts** and their permissions
- View the **audit log** across all visible machines
- Modify the **global settings** applicable to the team/organization

---

## Summary of Network Flows by Feature

| Feature | Protocol | Connection Type |
|---|---|---|
| Machine discovery | UDP | Broadcast/multicast |
| Messaging (individual/group) | WebSocket | Point-to-point (or broadcast for groups) |
| File sharing | TCP | Dedicated connection per transfer |
| Voice calls | WebRTC | Direct peer-to-peer |
| Security (encryption/auth) | OpenSSL (TLS) | Underlying WebSocket/TCP |
| Local storage (history, audit) | SQLite | Local to each machine |

---

## Related Documents

- [Requirements Specification](Cahier_des_charges.pdf) — functional needs and constraints
- [ARCHITECTURE.md](ARCHITECTURE.md) — logical architecture and code structure
- [TEAM.md](TEAM.md) — breakdown of responsibilities
- [ROADMAP.md](ROADMAP.md) — planned developments (v1.1, v2.0)
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — Git workflow and conventions
