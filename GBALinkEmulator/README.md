# GBALinkEmulator — CI Build com mGBA real

## Como usar (sem Mac)

### 1. Coloque o código no GitHub

```
seu-usuario/GBALinkEmulator/
├── .github/
│   └── workflows/
│       └── build.yml          ← workflow principal
├── scripts/
│   ├── patch_pbxproj.py       ← injeta libmgba no projeto
│   ├── ExportOptions-unsigned.plist
│   └── ExportOptions-signed.plist
├── GBALinkEmulator.xcodeproj/
│   └── project.pbxproj
└── GBALinkEmulator/
    ├── Bridge/
    │   ├── GBACoreBridge.h
    │   └── GBACoreBridge.m
    ├── Emulator/
    │   └── GBAEmulatorCore.swift
    └── Views/ Models/ Network/ ...
```

### 2. Rode o workflow

- Vá em **Actions → Build GBALinkEmulator with real mGBA → Run workflow**
- Ou faça um push para `main`

### 3. Baixe o IPA

Após ~15–25 min (primeira vez — mGBA compila do zero):
- **Actions → seu run → Artifacts → GBALinkEmulator-IPA**
- Baixe o `.ipa`

### 4. Instale no iPhone

**Sem conta de desenvolvedor** (mais fácil):
- [Sideloadly](https://sideloadly.io/) — Windows/Mac, usa Apple ID gratuito
- [AltStore](https://altstore.io/) — requer PC/Mac na mesma rede
- [TrollStore](https://github.com/opa334/TrollStore) — iOS 14.0–16.6.1, sem PC

**Com conta de desenvolvedor** ($99/ano):
- Configure os 4 GitHub Secrets abaixo
- O workflow assina o IPA automaticamente
- Instale via [iOS App Installer](https://docs.fastlane.tools/) ou diretamente

---

## GitHub Secrets (opcional — para build assinado)

Vá em **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Como obter |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Exporte o certificado de distribuição do Keychain como `.p12`, então `base64 -i cert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | A senha do `.p12` |
| `APPLE_PROVISIONING_PROFILE` | Baixe o `.mobileprovision` do Apple Developer Portal, então `base64 -i profile.mobileprovision` |
| `APPLE_TEAM_ID` | 10 caracteres, visível em [developer.apple.com](https://developer.apple.com/account) → Membership |

---

## O que o workflow faz (passo a passo)

```
Job 1: build-mgba (~10-15 min, cacheado após 1ª vez)
  ├── checkout mGBA 0.10.3 source
  ├── cmake configure para iOS arm64
  ├── ninja build → libmgba.a
  └── upload artifact: lib + headers

Job 2: build-app (~5-10 min)
  ├── checkout seu app
  ├── download mgba-dist do job 1
  ├── patch_pbxproj.py
  │     ├── injeta PBXFileReference para libmgba.a
  │     ├── injeta PBXBuildFile na fase Frameworks
  │     ├── HEADER_SEARCH_PATHS → mgba-dist/include
  │     ├── LIBRARY_SEARCH_PATHS → mgba-dist/lib
  │     └── OTHER_LDFLAGS: -lmgba -lz -lc++
  ├── xcodebuild archive
  ├── verifica que "STUB – mGBA not linked" NÃO está no binário
  ├── xcodebuild -exportArchive → .ipa
  └── upload artifact: GBALinkEmulator-IPA
```

---

## Cache

O `libmgba.a` é cacheado por versão:

```
key: mgba-ios-arm64-0.10.3-v3
```

Primeira build: ~15 min (compila mGBA).  
Builds seguintes: ~5 min (mGBA vem do cache).

Para forçar recompilação, mude a variável `MGBA_VERSION` no workflow.

---

## Problemas comuns

### "mGBA headers not found" ainda aparece
→ O `patch_pbxproj.py` não encontrou os config blocks certos.  
→ Abra o log do step "Patch Xcode project" e veja os checkmarks.  
→ Se algum está ✗, abra uma issue com o trecho do seu `project.pbxproj`.

### Build falha em "libmgba.a not found after build"
→ A versão do mGBA mudou o nome da biblioteca.  
→ O step imprime todos os `.a` encontrados — use esse nome no workflow.

### IPA instala mas fecha imediatamente
→ O Bundle ID no `ExportOptions-signed.plist` precisa bater com o da provisioning profile.  
→ Verifique `com.guizinho.GBALinkEmulator` no Apple Developer Portal.

### "Stub string found" no step de verificação
→ mGBA não foi linkado apesar do patch.  
→ Baixe o `build.log` artifact e procure por "MGBA_AVAILABLE".
