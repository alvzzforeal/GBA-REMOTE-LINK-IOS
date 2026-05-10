#import "GBACoreBridge.h"
#import <math.h>

// ---------------------------------------------------------------------------
// mGBA C headers
// REQUIRED for iOS emulation. Headers + libmgba.a must be linked at build time.
// ---------------------------------------------------------------------------
#ifdef __has_include
  #if __has_include(<mgba/core/core.h>) && \
      __has_include(<mgba/core/blip_buf.h>) && \
      __has_include(<mgba/gba/interface.h>) && \
      __has_include(<mgba/internal/gba/gba.h>)
    #include <mgba/core/core.h>
    #include <mgba/core/blip_buf.h>
    #include <mgba/gba/interface.h>
    #include <mgba/internal/gba/gba.h>
    #define MGBA_AVAILABLE 1
    #define MGBA_PLATFORM_GBA mPLATFORM_GBA
  #else
    #define MGBA_AVAILABLE 0
  #endif
#else
  #define MGBA_AVAILABLE 0
#endif

// Fail early if mGBA is not linked
#if !MGBA_AVAILABLE
  #error "mGBA headers and/or libmgba.a not found. See GBALinkEmulator/MGBA_INTEGRATION_GUIDE.md for setup."
#endif

// Audio constants
static const int kSampleRate   = 32768;
static const int kAudioBufSize = 4096;

// ---------------------------------------------------------------------------
@interface GBACoreBridge () {
    struct mCore  *_core;
    struct GBA    *_gba;
    blip_t        *_blipLeft;
    blip_t        *_blipRight;
    uint32_t  _videoBuffer[240 * 160];
    int16_t   _audioStereo[kAudioBufSize * 2];
    BOOL      _loaded;
    NSString *_lastErrorMessage;
    int       _frameCount;
    int       _nonBlackFrameCount;
}
@end

@implementation GBACoreBridge

// MARK: - Init / Dealloc

- (instancetype)init {
    if (!(self = [super init])) return nil;
    memset(_videoBuffer, 0, sizeof(_videoBuffer));
    _loaded     = NO;
    _frameCount = 0;
    _nonBlackFrameCount = 0;
    _lastErrorMessage = @"Not loaded yet";
    _core = NULL;
    _gba = NULL;
    _blipLeft = NULL;
    _blipRight = NULL;
    NSLog(@"[GBABridge] ✓ REAL MGBA MODE - mGBA headers detected and compiled successfully");
    return self;
}

- (void)dealloc {
    [self stop];
}

// MARK: - Public API

- (BOOL)loadROM:(NSString *)path error:(NSError **)outError {
    NSLog(@"[GBABridge] Loading ROM from: %@", path);
    
    // Verify file exists
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        _lastErrorMessage = @"ROM file not found on disk.";
        NSLog(@"[GBABridge] ERROR: File not found: %@", path);
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:10
                            userInfo:@{NSLocalizedDescriptionKey: _lastErrorMessage}];
        }
        return NO;
    }
    
    // Create GBA core
    NSLog(@"[GBABridge] Creating mCore for platform %d", MGBA_PLATFORM_GBA);
    _core = mCoreCreate(MGBA_PLATFORM_GBA);
    if (!_core) {
        _lastErrorMessage = @"mCoreCreate failed — mGBA library may be corrupt.";
        NSLog(@"[GBABridge] ERROR: mCoreCreate returned NULL");
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:1
                            userInfo:@{NSLocalizedDescriptionKey: _lastErrorMessage}];
        }
        return NO;
    }
    NSLog(@"[GBABridge] ✓ mCore created successfully");
    
    // Initialize the core
    _core->init(_core);
    NSLog(@"[GBABridge] ✓ mCore initialized");
    
    // Set video buffer (GBA native: 240x160, ARGB8888)
    _core->setVideoBuffer(_core, (color_t *)_videoBuffer, kGBAScreenWidth);
    NSLog(@"[GBABridge] ✓ Video buffer set (240x160 @ %p)", _videoBuffer);
    
    // Set audio buffer size
    _core->setAudioBufferSize(_core, kAudioBufSize);
    NSLog(@"[GBABridge] ✓ Audio buffer size set to %d samples", kAudioBufSize);
    
    // Get and configure audio channels (blip_buf resampler)
    _blipLeft  = _core->getAudioChannel(_core, 0);
    _blipRight = _core->getAudioChannel(_core, 1);
    if (_blipLeft) {
        blip_set_rates(_blipLeft, _core->frequency(_core), kSampleRate);
        NSLog(@"[GBABridge] ✓ Left audio channel configured");
    }
    if (_blipRight) {
        blip_set_rates(_blipRight, _core->frequency(_core), kSampleRate);
        NSLog(@"[GBABridge] ✓ Right audio channel configured");
    }
    
    // Load ROM file
    const char *cPath = [path fileSystemRepresentation];
    NSLog(@"[GBABridge] Calling mCoreLoadFile(%s)...", cPath);
    if (!mCoreLoadFile(_core, cPath)) {
        NSString *desc = [NSString stringWithFormat:
            @"mCoreLoadFile failed.\nPath: %@\n\nCheck that the file is a valid .gba ROM.", path];
        _lastErrorMessage = desc;
        NSLog(@"[GBABridge] ERROR: %@", desc);
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:2
                            userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        [self stop];
        return NO;
    }
    NSLog(@"[GBABridge] ✓ ROM loaded successfully");
    
    // Reset core to initialize registers and start emulation
    _core->reset(_core);
    NSLog(@"[GBABridge] ✓ mCore reset complete");
    
    _loaded = YES;
    _frameCount = 0;
    _nonBlackFrameCount = 0;
    _lastErrorMessage = @"";
    NSLog(@"[GBABridge] ✅ READY TO EMULATE: %@", path.lastPathComponent);
    return YES;
}

- (void)reset {
    if (_core) {
        NSLog(@"[GBABridge] Resetting core");
        _core->reset(_core);
        _frameCount = 0;
        _nonBlackFrameCount = 0;
    }
}

- (void)runFrame {
    if (!_core || !_loaded) {
        if (_frameCount % 300 == 0) {
            NSLog(@"[GBABridge] runFrame called but core not ready (loaded=%d)", _loaded);
        }
        return;
    }
    
    _core->runFrame(_core);
    _frameCount++;
    
    // Detect first non-black frame
    if (_nonBlackFrameCount == 0) {
        BOOL hasNonBlack = NO;
        const uint32_t *buf = _videoBuffer;
        for (int i = 0; i < 240 * 160; i++) {
            if (buf[i] != 0xFF000000) {  // ARGB: fully opaque black
                hasNonBlack = YES;
                break;
            }
        }
        if (hasNonBlack) {
            _nonBlackFrameCount = _frameCount;
            NSLog(@"[GBABridge] ✓ First non-black frame at frame #%d", _frameCount);
        }
    }
    
    if ((_frameCount % 300) == 0) {
        NSLog(@"[GBABridge] runFrame: frame #%d", _frameCount);
    }
}

- (void)setKeys:(uint16_t)mask {
    if (_core) _core->setKeys(_core, (int32_t)mask);
}

- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples {
    if (!_blipLeft || !_blipRight) return 0;
    
    int available = blip_samples_avail(_blipLeft);
    int toRead = (int)MIN(available, (int)maxSamples);
    if (toRead <= 0) return 0;
    
    int16_t leftBuf[toRead], rightBuf[toRead];
    blip_read_samples(_blipLeft,  leftBuf,  toRead, 0);
    blip_read_samples(_blipRight, rightBuf, toRead, 0);
    
    // Interleave L/R into output buffer
    for (int i = 0; i < toRead; i++) {
        buffer[i * 2]     = leftBuf[i];
        buffer[i * 2 + 1] = rightBuf[i];
    }
    
    return toRead;
}

- (void)stop {
    NSLog(@"[GBABridge] Stopping emulation");
    if (_core) {
        _core->deinit(_core);
        _core = NULL;
    }
    _blipLeft  = NULL;
    _blipRight = NULL;
    _loaded = NO;
}

// MARK: - Properties

- (const uint32_t *)videoBuffer { 
    return _videoBuffer; 
}

- (BOOL)isLoaded { 
    return _loaded; 
}

- (BOOL)isStubMode { 
    return NO;  // Always real mGBA (stub removed)
}

- (NSString *)coreModeDescription {
    return @"✓ REAL MGBA MODE";
}

- (NSString *)lastErrorMessage { 
    return _lastErrorMessage ?: @""; 
}

- (NSInteger)renderedFrameCount { 
    return _frameCount; 
}

@end
