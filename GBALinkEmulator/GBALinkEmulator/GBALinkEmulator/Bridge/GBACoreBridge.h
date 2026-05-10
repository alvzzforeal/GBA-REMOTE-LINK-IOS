#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// GBACoreBridge
// Thin Objective-C wrapper around the mGBA C API (libmgba).
//
// HOW TO INTEGRATE REAL mGBA:
// 1. Download mGBA source: https://github.com/mgba-emu/mgba
// 2. Build for iOS arm64:
//      mkdir build-ios && cd build-ios
//      cmake .. -DCMAKE_TOOLCHAIN_FILE=../src/platform/qt/ios.cmake \
//               -DBUILD_SHARED=OFF -DBUILD_STATIC=ON
//      make -j8
// 3. Add libmgba.a to Xcode → Frameworks, Libraries, and Embedded Content
// 4. Add Header Search Paths → $(SRCROOT)/path/to/mgba/include
// 5. The #if __has_include(<mgba/core/core.h>) block will activate automatically.
//
// Until then, the bridge compiles in STUB mode and renders an animated
// pattern so the rendering pipeline can be verified end-to-end.
// ---------------------------------------------------------------------------

/// GBA screen dimensions (fixed by hardware)
static const int kGBAScreenWidth  = 240;
static const int kGBAScreenHeight = 160;

/// GBA button bit-mask (matches mGBA GBAKey enum)
typedef NS_OPTIONS(uint16_t, GBAKeyMask) {
    GBAKeyA      = 1 << 0,
    GBAKeyB      = 1 << 1,
    GBAKeySelect = 1 << 2,
    GBAKeyStart  = 1 << 3,
    GBAKeyRight  = 1 << 4,
    GBAKeyLeft   = 1 << 5,
    GBAKeyUp     = 1 << 6,
    GBAKeyDown   = 1 << 7,
    GBAKeyR      = 1 << 8,
    GBAKeyL      = 1 << 9,
};

/// Opaque wrapper around mCoreThread / mCore
@interface GBACoreBridge : NSObject

// ---------------------------------------------------------------------------
// IMPORTANT: Swift calls this as bridge.loadROM(atPath: path).
// The selector is loadROM:error: which Swift imports as loadROM(atPath:).
// Keep this name exactly — do NOT rename to loadROMAtPath:error:.
// ---------------------------------------------------------------------------

/// Load a ROM file. Returns YES on success, NO on failure (sets outError).
- (BOOL)loadROM:(NSString *)path error:(NSError **)outError
    NS_SWIFT_NAME(loadROM(atPath:));

/// Hard-reset the emulator (keeps ROM loaded).
- (void)reset;

/// Run exactly one GBA frame (~280896 cycles at ~59.73 Hz).
/// Called from a CADisplayLink callback on the main thread.
- (void)runFrame;

/// Set the pressed-keys bitmask (GBAKeyMask).
- (void)setKeys:(uint16_t)mask;

/// Stop emulation and free all resources.
- (void)stop;

/// ARGB8888 pixel buffer for the current frame.
/// Size: kGBAScreenWidth * kGBAScreenHeight * 4 bytes.
/// Valid to read immediately after -runFrame returns.
@property (nonatomic, readonly) const uint32_t * _Nullable videoBuffer;

/// Drain audio samples (stereo int16, interleaved L/R).
- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples;

/// YES after -loadROM:error: succeeds and before -stop is called.
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

/// YES if running in stub mode (mGBA not linked).
@property (nonatomic, readonly) BOOL isStubMode;

@end

NS_ASSUME_NONNULL_END
