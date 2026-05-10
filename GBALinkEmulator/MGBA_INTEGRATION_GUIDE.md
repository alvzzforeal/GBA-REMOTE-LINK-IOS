# Como integrar o mGBA real ao GBALinkEmulator

## Estado actual do projeto

O projecto compila e roda em **STUB mode**: a ROM é verificada no disco,
o display link dispara a 60fps, e a pipeline de vídeo (`runFrame → videoBuffer
→ CGImage → SwiftUI Image`) está funcionando — você vai ver uma animação
colorida na tela em vez de preto.

Para rodar jogos de verdade, você precisa linkar `libmgba.a`.

---

## Passo a passo completo

### 1. Baixar e compilar o mGBA para iOS

```bash
git clone https://github.com/mgba-emu/mgba.git
cd mgba

# Instale dependências (macOS)
brew install cmake

# Compile para iOS arm64 (device)
mkdir build-ios-arm64 && cd build-ios-arm64
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=../src/platform/qt/ios.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED=OFF \
  -DBUILD_STATIC=ON \
  -DENABLE_FILESYSTEM=OFF \
  -DENABLE_VFS_ZIP=OFF \
  -DUSE_SQLITE3=OFF \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)
make -j$(sysctl -n hw.logicalcpu)

# Compile para Simulator x86_64 + arm64 (opcional, para rodar no Simulator)
cd ..
mkdir build-ios-sim && cd build-ios-sim
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED=OFF \
  -DBUILD_STATIC=ON \
  -DENABLE_FILESYSTEM=OFF \
  -DENABLE_VFS_ZIP=OFF \
  -DUSE_SQLITE3=OFF \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path)
make -j$(sysctl -n hw.logicalcpu)

# Criar XCFramework (device + simulator numa pancada)
xcodebuild -create-xcframework \
  -library build-ios-arm64/libmgba.a \
  -headers include \
  -library build-ios-sim/libmgba.a \
  -headers include \
  -output mGBA.xcframework
```

### 2. Adicionar ao Xcode

1. Arraste `mGBA.xcframework` para dentro do projeto no Xcode
   (ou `build-ios-arm64/libmgba.a` se não precisar do Simulator).
2. Em **Target → General → Frameworks, Libraries, and Embedded Content**,
   confirme que aparece com **Do Not Embed**.
3. Em **Build Settings → Header Search Paths**, adicione:
   ```
   $(SRCROOT)/path/para/mgba/include
   ```
   (o diretório que contém a pasta `mgba/` com `core/core.h` etc.)

### 3. Verificar a integração

Compile o projecto. Se o mGBA for encontrado, o compilador vai imprimir:

```
// Nenhum warning — MGBA_AVAILABLE = 1
```

Se ainda estiver em stub mode, você verá:

```
warning: mGBA headers not found — GBACoreBridge running in STUB mode.
```

Nesse caso, verifique o Header Search Path.

### 4. Testar

- Importe uma ROM `.gba` pela aba Library.
- Toque na ROM para abrir o emulador.
- O banner amarelo "DEMO MODE" **não deve aparecer** quando mGBA está integrado.
- O jogo deve rodar a ~59.73fps (GBA clock real).

---

## Estrutura de arquivos modificados nesta correção

| Arquivo | O que foi corrigido |
|---|---|
| `Bridge/GBACoreBridge.h` | Renomeado `loadROMAtPath:error:` → `loadROM:error:` + `NS_SWIFT_NAME`. Era o bug que causava tela preta. |
| `Bridge/GBACoreBridge.m` | Stub agora renderiza frames coloridos reais em vez de nada. |
| `Emulator/GBAEmulatorCore.swift` | Comentário explicando o bug corrigido; `isStub` exposto. |
| `Views/EmulatorView.swift` | Responsividade total; `GeometryReader` em todo o layout; banner de stub. |
| `Views/VirtualControlsView.swift` | Escala proporcional de iPhone mini a Pro Max via `.clamped()`. |
| `Views/ROMListView.swift` | Biblioteca ocupa tela inteira; grid calculado com `GeometryReader`. |

---

## Por que havia tela preta (diagnóstico detalhado)

O `GBAEmulatorCore.swift` chamava:

```swift
try bridge.loadROM(atPath: url.path)   // ← seletor ObjC: loadROM:error:
```

Mas o header declarava:

```objc
- (BOOL)loadROMAtPath:(NSString *)path error:(NSError **)outError;
// seletor ObjC: loadROMAtPath:error:  ← DIFERENTE!
```

Swift/ObjC bridge compila sem erro porque o método existe com esse nome,
mas o `NS_SWIFT_NAME` estava errado: o Swift tentava chamar `loadROM:error:`
que **não existia** no ObjC. Em runtime, isso resulta em `unrecognized selector`
ou simplesmente o método não sendo chamado — logo, a ROM nunca carregava,
e o display link chamava `runFrame()` com `_loaded = NO`, não gerando frames.

**Correção**: renomear o método ObjC para `loadROM:error:` e adicionar
`NS_SWIFT_NAME(loadROM(atPath:))` para manter a API Swift idêntica.
