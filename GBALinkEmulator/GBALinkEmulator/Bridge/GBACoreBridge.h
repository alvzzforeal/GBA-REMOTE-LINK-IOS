#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ============================================================================
// GBACoreBridge
// Objective-C bridge to real mGBA C API for iOS emulation.
// 
// REQUIREMENT: libmgba.a and headers MUST be linked at build time.
// If mGBA is not available, the build will FAIL with #error.
// See GBALinkEmulator/MGBA_INTEGRATION_GUIDE.md for setup.
// ============================================================================

static const int kGBAScreenWidth  = 240;
static const int kGBAScreenHeight = 160;

/// GBA controller button mask (10-bit, standard GBA inputs)
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

@interface GBACoreBridge : NSObject

// MARK: - ROM Loading

/// Load a GBA ROM and initialize the emulator core.
/// @param path File system path to .gba ROM file
/// @param outError Error details if loading fails
/// @return YES on success, NO on failure
- (BOOL)loadROM:(NSString *)path error:(NSError **)outError NS_SWIFT_NAME(loadROM(atPath:));

// MARK: - Emulation Control

/// Reset the GBA core to power-on state
- (void)reset;

/// Execute one frame of emulation (~59.73 ms at real GBA speed)
/// Updates videoBuffer with rendered frame
- (void)runFrame;

/// Set which GBA buttons are pressed (mask of GBAKeyMask values)
- (void)setKeys:(uint16_t)mask;

/// Stop emulation and release core resources
- (void)stop;

// MARK: - Video Output

/// Raw ARGB8888 video buffer (240x160 pixels)
/// Updated after each runFrame() call
@property (nonatomic, readonly) const uint32_t * _Nullable videoBuffer;

// MARK: - Audio Output

/// Read available audio samples from GBA emulation output
/// @param buffer Destination for interleaved stereo L/R samples
/// @param maxSamples Maximum samples to read
/// @return Number of samples read (each sample = 2 int16_t values for L+R)
- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples;

// MARK: - State & Debug Info

/// YES if a ROM is currently loaded and ready to emulate
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

/// Always NO (stub mode removed; build requires real mGBA)
@property (nonatomic, readonly, getter=isStubMode) BOOL stubMode;

/// "✓ REAL MGBA MODE" — displayed on screen to confirm real emulation
@property (nonatomic, readonly) NSString *coreModeDescription;

/// Human-readable error message if loading failed
@property (nonatomic, readonly) NSString *lastErrorMessage;

/// Number of frames executed so far
@property (nonatomic, readonly) NSInteger renderedFrameCount;

@end

NS_ASSUME_NONNULL_END
