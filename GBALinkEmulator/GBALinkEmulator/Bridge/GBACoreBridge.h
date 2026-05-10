#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

static const int kGBAScreenWidth  = 240;
static const int kGBAScreenHeight = 160;

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

/// Swift name: try bridge.loadROM(atPath: url.path)
- (BOOL)loadROM:(NSString *)path error:(NSError **)outError NS_SWIFT_NAME(loadROM(atPath:));

- (void)reset;
- (void)runFrame;
- (void)setKeys:(uint16_t)mask;
- (void)stop;

@property (nonatomic, readonly) const uint32_t * _Nullable videoBuffer;
- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples;
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

/// Debug helpers exposed to Swift so the app can show REAL/STUB on screen.
@property (nonatomic, readonly, getter=isStubMode) BOOL stubMode;
@property (nonatomic, readonly) NSString *coreModeDescription;
@property (nonatomic, readonly) NSString *lastErrorMessage;
@property (nonatomic, readonly) NSInteger renderedFrameCount;

@end

NS_ASSUME_NONNULL_END
