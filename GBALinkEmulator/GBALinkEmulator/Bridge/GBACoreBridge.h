#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// GBACoreBridge
// Thin Objective-C wrapper around the mGBA C API (libmgba).
// mGBA must be present as either:
//   a) A compiled static library  →  libmgba.a  (arm64-apple-ios)
//   b) An xcframework             →  mGBA.xcframework
// Add it to the Xcode project under Frameworks, Libraries, and Embedded Content.
//
// Required mGBA headers (copy from mGBA source → include/mgba/):
//   mgba/core/core.h
//   mgba/core/blip_buf.h
//   mgba/gba/interface.h
//   mgba/internal/gba/gba.h
//   mgba-util/common.h
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

/// Load a ROM file. Returns YES on success.
- (BOOL)loadROMAtPath:(NSString *)path error:(NSError **)outError;

/// Hard-reset the emulator (keeps ROM loaded).
- (void)reset;

/// Run exactly one GBA frame (280896 cycles at ~59.73 Hz).
/// Must be called from a dedicated emulation thread or a CADisplayLink callback.
- (void)runFrame;

/// Set the pressed-keys bitmask (GBAKeyMask).
- (void)setKeys:(uint16_t)mask;

/// Stop emulation and free all resources.
- (void)stop;

/// ARGB8888 pixel buffer for the current frame.
/// Size: kGBAScreenWidth * kGBAScreenHeight * 4 bytes.
/// Safe to read immediately after -runFrame returns.
@property (nonatomic, readonly) const uint32_t * _Nullable videoBuffer;

/// BLIP audio samples filled each frame (stereo int16, interleaved L/R).
/// Drained automatically; call -drainAudioInto:maxSamples: to consume them.
- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples;

/// YES after -loadROMAtPath:error: succeeds and before -stop is called.
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

@end

NS_ASSUME_NONNULL_END
