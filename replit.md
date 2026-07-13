# CollabLAN

LAN-only collaboration suite (messaging, file sharing, voice calls, audit log) written in C++23 / Qt 6. No internet connection required.

## Stack

- **Language:** C++23
- **UI:** Qt 6 Quick/QML
- **Database:** SQLite (via Qt SQL)
- **Networking:** UDP discovery · TCP/WebSocket messaging · WebRTC voice (libdatachannel)
- **Crypto:** OpenSSL
- **Build:** CMake 3.20+ · Ninja

## How to build

The **"Build CollabLAN"** workflow runs the full build. To build manually from a shell:

```bash
mkdir -p build
cd build
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -j2
```

Binary output: `build/app/CollabLAN`

### First-time note
`libdatachannel` (WebRTC) is fetched via CMake FetchContent. Its git submodules (libsrtp, libjuice, usrsctp, plog, json) must be present in `build/_deps/libdatachannel-src/deps/`. They are populated automatically on the first `cmake ..` run **or** can be seeded manually with:

```bash
cd build/_deps/libdatachannel-src
git init
git submodule update --init --recursive --depth=1 deps/libsrtp deps/libjuice deps/usrsctp deps/plog deps/json
```

## Running

CollabLAN is a Qt desktop GUI application. On Replit it builds cleanly but requires a display (X11/Wayland) to launch. Run it on a machine with a display or use an X11 forwarding setup.

## Tests

```bash
cd build
ctest --output-on-failure
```

## User preferences

(none yet)
