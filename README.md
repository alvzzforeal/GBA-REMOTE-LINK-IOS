# GBALinkEmulator — mGBA Integration Guide

> **GBALinkEmulator** is an iOS Game Boy Advance emulator with Wi-Fi Link Cable  
> support, powered by the open-source **mGBA** core.

---

## Architecture

```
GBALinkEmulatorApp (SwiftUI)
│
├── Views/
│   ├── ROMListView         — import & browse .gba files
│   ├── EmulatorView        — game screen + virtual controls
│   └── MultiplayerView     — Wi-Fi link cable lobby
│
├── Emulator/
│   └── GBAEmulatorCore.swift  ← Swift wrapper (mGBA integration)
│
├── Bridge/
│   ├── GBACoreBridge.h     ← Obj-C API exposed to Swift via Bridging Header
│   └── GBACoreBridge.m     ← Calls into mGBA's C API
│
└── Network/
    ├── LinkCableHost       — GBA serial protocol over TCP/Bonjour
    └── LinkCableClient
```

---

## How to integrate mGBA

### Option A — Swift Package Manager *(recommended)*

1. Open `GBALinkEmulator.xcodeproj` in Xcode.
2. **File → Add Package Dependencies…** → `https://github.com/mgba-emu/mgba` → version `0.10.3`
3. Uncomment the `.package` + `.product` lines in `Package.swift`.
4. Build Settings → **Swift Compiler – Code Generation** →  
   `Objective-C Bridging Header` = `GBALinkEmulator/GBALinkEmulator-Bridging-Header.h`
5. Build. ✅

### Option B — Pre-built static library (`libmgba.a`)

```bash
git clone --depth 1 --branch 0.10.3 https://github.com/mgba-emu/mgba.git
cmake mgba -B mgba-build -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=mgba/cmake/Toolchains/iOS.cmake \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED=OFF -DBUILD_STATIC=ON \
  -DUSE_LZMA=OFF -DUSE_PNG=OFF -DUSE_SQLITE3=OFF \
  -DCMAKE_INSTALL_PREFIX=mgba-install
cmake --build mgba-build --target install -j$(sysctl -n hw.logicalcpu)
```

Then add `libmgba.a` → *Frameworks, Libraries* (Do Not Embed)  
and `mgba-install/include` → *Header Search Paths* (recursive).

---

## mGBA C API used

| Call | Purpose |
|------|---------|
| `mCoreCreate(PLATFORM_GBA)` | Allocate core |
| `core->init(core)` | Initialise internals |
| `core->setVideoBuffer(core, buf, 240)` | ARGB8888 output buffer |
| `mCoreLoadFile(core, path)` | Load `.gba` ROM |
| `core->reset(core)` | Hard-reset / boot |
| `core->runFrame(core)` | Advance one frame at 59.73 Hz |
| `core->setKeys(core, mask)` | Button state |
| `blip_read_samples()` | Drain audio samples |
| `core->deinit(core)` | Free resources |

---

## GitHub Actions CI

`.github/workflows/ios-build.yml`:

| Step | Trigger |
|------|---------|
| Compile (no signing) | Every push / PR |
| Unit tests on Simulator | Every push / PR |
| Archive + Export IPA | Push to `main` only |
| Upload to TestFlight | Push to `main` only |

### Required Secrets

| Secret | Description |
|--------|-------------|
| `APPLE_TEAM_ID` | 10-char Apple Team ID |
| `MATCH_GIT_URL` | URL of match certificates repo |
| `MATCH_PASSWORD` | match encryption passphrase |
| `MATCH_GIT_BASIC_AUTH` | `base64("user:pat")` for HTTPS |
| `APP_STORE_CONNECT_API_KEY` | `.p8` key contents |
| `APP_STORE_CONNECT_KEY_ID` | 10-char Key ID |
| `APP_STORE_CONNECT_ISSUER` | Issuer UUID |
| `KEYCHAIN_PASSWORD` | Random strong string |

---

## App Icon

`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` — Xcode auto-generates all sizes from this single 1024×1024 asset (iOS 16+).
