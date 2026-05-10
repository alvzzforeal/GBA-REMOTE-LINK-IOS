# Real mGBA Integration Setup Guide

## Overview
This project now requires **real mGBA** with no stub fallback mode. If mGBA headers are not found at compile time, the build will **FAIL with a clear #error message**.

## Build Requirements

### For GitHub Actions (CI/CD)
✅ **Already configured** in `.github/workflows/ios-build.yml`:
- Automatically downloads mGBA 0.10.3
- Builds `libmgba.a` for iOS arm64
- Passes headers and library to Xcode via build variables
- Verifies binary is NOT in stub mode

### For Local Development (Xcode)

#### Option 1: Auto-Build (Recommended)
1. Run the GitHub Actions workflow (or build locally with same steps)
2. Copy the built files to your project:
   ```bash
   mkdir -p GBALinkEmulator/Dependencies/mgba/{include,lib}
   cp mgba-dist/lib/libmgba.a GBALinkEmulator/Dependencies/mgba/lib/
   cp -R mgba-dist/include/. GBALinkEmulator/Dependencies/mgba/include/
   ```

#### Option 2: Manual Build
```bash
# Build mGBA 0.10.3 for iOS
git clone --branch 0.10.3 https://github.com/mgba-emu/mgba.git
cd mgba
mkdir build-ios && cd build-ios

cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_STATIC=ON -DBUILD_SHARED=OFF \
  -DENABLE_FILESYSTEM=OFF \
  -DUSE_ZLIB=ON

cmake --build . --parallel 8

# Copy to project
mkdir -p ../GBALinkEmulator/Dependencies/mgba/{include,lib}
cp libmgba.a ../GBALinkEmulator/Dependencies/mgba/lib/
cp -R include/. ../GBALinkEmulator/Dependencies/mgba/include/
```

#### Option 3: Use Xcode Build Settings
In Xcode, set these for the GBALinkEmulator target:

**Build Settings:**
- **Header Search Paths**: `/path/to/mgba/include`
- **Library Search Paths**: `/path/to/mgba/lib`

**Build Phases → Link Binary With Libraries:**
- Add `libmgba.a` from the library path

**Other Linker Flags**: `-lz -lc++`

## Verification

### Build Success Indicators
1. ✅ **No compile errors**
2. ✅ **Console logs show**: `[GBABridge] ✓ REAL MGBA MODE - mGBA headers detected`
3. ✅ **Binary contains**: `REAL MGBA MODE` string (not `STUB MODE`)

### Runtime Verification
1. Launch the app
2. Import a valid `.gba` ROM (e.g., Pokémon Emerald)
3. Tap to play
4. You should see:
   - **Green banner** at top-left: `✓ REAL MGBA MODE`
   - **FPS counter**: Shows ~59-60 FPS
   - **Game screen**: Displays game graphics (NOT black)

### Troubleshooting

#### "Build Failed" with #error message
**Cause**: mGBA headers not found
**Solution**:
1. Verify files exist:
   ```bash
   test -f /path/to/mgba/include/mgba/core/core.h
   test -f /path/to/mgba/lib/libmgba.a
   ```
2. Update Xcode build settings with correct paths
3. Run `xcodebuild clean` and rebuild

#### Black Screen After Loading ROM
**Likely causes**:
1. **Invalid ROM file** - Try a different .gba ROM
2. **mGBA not actually loaded** - Check console for error messages
3. **Video buffer issue** - Check system logs for memory issues

**Debug steps**:
- Check Xcode console for `[GBABridge]` log messages
- Look for `ROM loaded successfully` message
- Verify FPS counter is updating
- Check that device has sufficient memory

#### "mGBA headers not found" Warning at Build Time
If you see this message: **This is now a FATAL ERROR** (build will fail)
- Verify mGBA is properly configured
- Check file permissions: `ls -la /path/to/mgba/include`
- Try clean rebuild: `xcodebuild clean -project ... && xcodebuild build ...`

## Build Time Behavior

### What's Different From Before
- **STUB mode removed** - No fallback animation
- **#error macro** - Build fails clearly if mGBA missing
- **Detailed logging** - Understand exactly what's happening

### What's The Same
- Same public API (GBACoreProtocol)
- Same video buffer format (ARGB8888, 240x160)
- Same audio interface (32768 Hz stereo via blip_buf)
- Same button input handling

## GitHub Actions CI/CD

The workflow `.github/workflows/ios-build.yml` handles everything:
1. ✅ Downloads mGBA 0.10.3
2. ✅ Builds for iOS arm64
3. ✅ Caches library between runs (saves 15+ minutes)
4. ✅ Passes paths to Xcode automatically
5. ✅ Verifies build is NOT in stub mode
6. ✅ Creates .ipa artifact

**To trigger**: Push to `main` branch or manually dispatch workflow.

## Performance Notes

- **Target FPS**: ~59.73 FPS (real GBA speed)
- **CPU**: Uses ~20-30% on iPhone 13+
- **Memory**: ~50-80 MB for emulation core
- **Audio**: 32768 Hz stereo, real-time resampling via blip_buf

## Support for Simulators

Currently only builds for **iOS device (arm64)**. To add Simulator support:

```bash
# Build for Simulator (x86_64 and arm64e)
cmake -B build-sim -S mgba \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64e" \
  ...

# Create XCFramework with both
xcodebuild -create-xcframework \
  -library build-ios/libmgba.a -headers mgba/include \
  -library build-sim/libmgba.a -headers mgba/include \
  -output mGBA.xcframework
```

Then add `mGBA.xcframework` to Xcode (General → Frameworks).

## Key Files

- `GBALinkEmulator/GBALinkEmulator/Bridge/GBACoreBridge.h` - Main Objective-C interface
- `GBALinkEmulator/GBALinkEmulator/Bridge/GBACoreBridge.m` - mGBA C API wrapper (REAL ONLY)
- `GBALinkEmulator/GBALinkEmulator/Emulator/GBAEmulatorCore.swift` - Swift wrapper
- `GBALinkEmulator/GBALinkEmulator/Views/EmulatorView.swift` - UI with FPS display
- `.github/workflows/ios-build.yml` - Automated CI/CD pipeline

## Questions or Issues?

Check console logs for `[GBABridge]` messages - they indicate exactly what's happening during:
- Core initialization
- ROM loading
- Frame execution
- Audio setup

Logs appear at levels:
- ✓ Success messages
- ❌ Errors with details
- Frame counters every 300 frames
