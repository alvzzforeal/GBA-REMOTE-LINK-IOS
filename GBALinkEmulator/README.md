# GBA Link Emulator

Um emulador de Game Boy Advance para iPhone/iPad com suporte a multiplayer via Wi-Fi local (Link Cable).

---

## 📁 Estrutura do projeto

```
GBALinkEmulator/
└── GBALinkEmulator/
    ├── GBALinkEmulatorApp.swift      # Entry point (@main)
    ├── ContentView.swift             # Navegação por abas
    ├── Info.plist                    # Permissões de rede e arquivo
    │
    ├── Models/
    │   ├── ROMFile.swift             # Modelo de ROM + ROMLibrary (persistência)
    │   └── LinkCableSession.swift    # Estado do Link Cable + pacotes
    │
    ├── Views/
    │   ├── ROMListView.swift         # Lista de ROMs + importação
    │   ├── EmulatorView.swift        # Tela principal do emulador
    │   ├── VirtualControlsView.swift # D-pad, A/B, L/R, Start, Select
    │   └── MultiplayerView.swift     # Host / Join / IP / descoberta
    │
    ├── Emulator/
    │   └── GBAEmulatorCore.swift     # Bridge Swift→mGBA (stub + instruções)
    │
    └── Network/
        ├── LinkCableHost.swift       # NWListener + Bonjour advertising
        └── LinkCableClient.swift     # NWBrowser (discovery) + NWConnection
```

---

## 🚀 Como compilar e testar

### Pré-requisitos
- Xcode 15+
- iPhone/iPad com iOS 16+ (ou Simulador para testes básicos)
- Apple Developer Account (gratuita funciona para testes no dispositivo)

### Passos

1. **Abrir o projeto**
   ```bash
   open GBALinkEmulator.xcodeproj
   # ou crie um novo projeto Xcode e adicione os arquivos manualmente
   ```

2. **Criar o projeto no Xcode (caso não tenha .xcodeproj)**
   - File → New → Project → App
   - Product Name: `GBALinkEmulator`
   - Interface: SwiftUI | Language: Swift
   - Arraste todos os arquivos `.swift` para o projeto
   - Substitua o `Info.plist` gerado pelo fornecido

3. **Configurar assinatura**
   - Signing & Capabilities → Team: escolha sua conta Apple
   - Bundle Identifier: `com.seuNome.GBALinkEmulator`

4. **Adicionar permissões de rede (Xcode)**
   - Signing & Capabilities → + Capability → "Local Network"
   - Confirme que `NSLocalNetworkUsageDescription` e `NSBonjourServices` estão no Info.plist

5. **Rodar no dispositivo**
   - Conecte iPhone/iPad via USB
   - Selecione o dispositivo no seletor do Xcode
   - Cmd+R para compilar e rodar

6. **Testar multiplayer**
   - Instale o app em **dois dispositivos** na mesma rede Wi-Fi
   - Dispositivo A: aba Multiplayer → **Host**
   - Dispositivo B: aba Multiplayer → **Join** (o host aparece automaticamente)
   - Ou use **Connect by IP** com o IP local do host

---

## 🔧 Integrar o mGBA (core real de emulação)

O arquivo `Emulator/GBAEmulatorCore.swift` contém um stub funcional com comentários
marcando cada ponto de integração. Para rodar ROMs de verdade:

### 1. Clonar o mGBA
```bash
git clone https://github.com/mgba-emu/mgba.git
```

### 2. Compilar para iOS (arm64)
```bash
mkdir build-ios && cd build-ios
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=../cmake/Toolchains/iOS.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF
make -j$(nproc)
# Produto: libmgba.a
```

### 3. Adicionar ao Xcode
- Arraste `libmgba.a` e os headers `mgba/` para o projeto
- Build Settings → Header Search Paths: aponte para os headers do mGBA
- Build Settings → Other Linker Flags: `-lmgba`

### 4. Criar bridge Objective-C
```objc
// GBACoreBridge.h
#import <Foundation/Foundation.h>
#import <mgba/core/core.h>
// Exponha funções C necessárias para o Swift
```

### 5. Substituir o stub em `GBAEmulatorCore.swift`
Cada comentário `// ── mGBA integration point ──` indica onde chamar a API C do mGBA.

---

## ⚙️ Funcionalidades implementadas

| Feature | Status |
|---|---|
| Importar ROMs .gba | ✅ |
| Lista de ROMs com persistência | ✅ |
| Tela do emulador (stub visual) | ✅ |
| Controles virtuais completos | ✅ |
| D-pad, A/B, L/R, Start/Select | ✅ |
| Host Wi-Fi via Bonjour | ✅ |
| Join via descoberta automática | ✅ |
| Join via IP manual | ✅ |
| Troca de dados (input + serial) | ✅ |
| Indicador de latência | ✅ |
| Core mGBA real | 🔧 (stub — ver instruções acima) |

---

## 📝 Notas legais

- Este app **não inclui** ROMs, BIOS ou qualquer arquivo protegido por copyright.
- O usuário deve fornecer suas próprias ROMs legalmente obtidas.
- O mGBA é open-source sob licença MPL 2.0.
