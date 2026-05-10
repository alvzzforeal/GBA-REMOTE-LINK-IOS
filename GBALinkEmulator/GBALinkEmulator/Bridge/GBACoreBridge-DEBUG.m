/**
 * TEMPORARY DEBUG VERSION - mGBA STUB FALLBACK
 * 
 * Use este arquivo APENAS se você está desenvolvendo localmente sem mGBA linkado.
 * 
 * Para usar:
 * 1. Em Xcode: Build Phases → Compile Sources
 * 2. Remova GBACoreBridge.m
 * 3. Adicione este arquivo (GBACoreBridge-DEBUG.m)
 * 4. Compile
 * 5. ROM carregará em STUB MODE (animação colorida)
 * 
 * ⚠️ NÃO use em production. GitHub Actions sempre usa modo REAL.
 */

#import "GBACoreBridge.h"
#import <math.h>

// Try to include mGBA, but don't fail if not available
#ifdef __has_include
  #if __has_include(<mgba/core/core.h>)
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

// Stub shims if mGBA not available
#if !MGBA_AVAILABLE
  typedef void mCore;
  typedef void GBA;
  typedef void blip_t;
  #define mPLATFORM_GBA 0
  static inline mCore* mCoreCreate(int p) { (void)p; return NULL; }
  static inline void mCoreDeinit(mCore *c) { (void)c; }
  static inline int mCoreLoadFile(mCore *c, const char *p) { (void)c; (void)p; return 0; }
#endif

static const int kSampleRate   = 32768;
static const int kAudioBufSize = 4096;

@interface GBACoreBridge () {
#if MGBA_AVAILABLE
    struct mCore  *_core;
    blip_t        *_blipLeft;
    blip_t        *_blipRight;
#else
    void          *_core;
#endif
    uint32_t  _videoBuffer[240 * 160];
    int16_t   _audioStereo[kAudioBufSize * 2];
    BOOL      _loaded;
    NSString *_lastErrorMessage;
    int       _frameCount;
    int       _nonBlackFrameCount;
}
@end

@implementation GBACoreBridge

- (instancetype)init {
    if (!(self = [super init])) return nil;
    memset(_videoBuffer, 0, sizeof(_videoBuffer));
    _loaded = NO;
    _frameCount = 0;
    _nonBlackFrameCount = 0;
    _lastErrorMessage = @"Not loaded yet";
    _core = NULL;
    _blipLeft = NULL;
    _blipRight = NULL;
#if MGBA_AVAILABLE
    NSLog(@"[GBABridge] ✓ REAL MGBA MODE - mGBA headers detected");
#else
    NSLog(@"[GBABridge] ⚠️  STUB MODE - mGBA not linked. Using fallback animation.");
#endif
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)loadROM:(NSString *)path error:(NSError **)outError {
#if MGBA_AVAILABLE
    NSLog(@"[GBABridge-REAL] Loading ROM: %@", path);
    
    _core = mCoreCreate(MGBA_PLATFORM_GBA);
    if (!_core) {
        _lastErrorMessage = @"mCoreCreate failed";
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:1
                            userInfo:@{NSLocalizedDescriptionKey: _lastErrorMessage}];
        }
        return NO;
    }
    
    _core->init(_core);
    _core->setVideoBuffer(_core, (color_t *)_videoBuffer, kGBAScreenWidth);
    _core->setAudioBufferSize(_core, kAudioBufSize);
    
    _blipLeft  = _core->getAudioChannel(_core, 0);
    _blipRight = _core->getAudioChannel(_core, 1);
    if (_blipLeft)  blip_set_rates(_blipLeft,  _core->frequency(_core), kSampleRate);
    if (_blipRight) blip_set_rates(_blipRight, _core->frequency(_core), kSampleRate);
    
    const char *cPath = [path fileSystemRepresentation];
    if (!mCoreLoadFile(_core, cPath)) {
        _lastErrorMessage = @"mCoreLoadFile failed";
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:2
                            userInfo:@{NSLocalizedDescriptionKey: _lastErrorMessage}];
        }
        [self stop];
        return NO;
    }
    
    _core->reset(_core);
    _loaded = YES;
    _frameCount = 0;
    _nonBlackFrameCount = 0;
    NSLog(@"[GBABridge-REAL] ROM loaded: %@", path.lastPathComponent);
    return YES;
#else
    // STUB MODE
    NSLog(@"[GBABridge-STUB] Loading ROM in STUB mode: %@", path);
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        _lastErrorMessage = @"ROM file not found";
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:10
                            userInfo:@{NSLocalizedDescriptionKey: _lastErrorMessage}];
        }
        return NO;
    }
    
    _loaded = YES;
    _frameCount = 0;
    _nonBlackFrameCount = 0;
    _lastErrorMessage = @"STUB MODE";
    NSLog(@"[GBABridge-STUB] ROM ready for stub animation: %@", path.lastPathComponent);
    return YES;
#endif
}

- (void)reset {
#if MGBA_AVAILABLE
    if (_core) _core->reset(_core);
#endif
    _frameCount = 0;
}

- (void)runFrame {
    if (!_loaded) return;
    
#if MGBA_AVAILABLE
    if (_core) {
        _core->runFrame(_core);
        _frameCount++;
        if (_frameCount % 300 == 0) {
            NSLog(@"[GBABridge-REAL] Frame %d", _frameCount);
        }
    }
#else
    // STUB ANIMATION
    _frameCount++;
    float t = _frameCount / 60.0f;
    
    for (int y = 0; y < 160; y++) {
        for (int x = 0; x < 240; x++) {
            float fx = (float)x / 239.0f;
            float fy = (float)y / 159.0f;
            
            float r = 0.5f + 0.5f * sinf(fx * 6.28f + t * 1.3f);
            float g = 0.5f + 0.5f * sinf(fy * 6.28f + t * 0.9f + 2.09f);
            float b = 0.5f + 0.5f * sinf((fx + fy) * 4.0f + t * 1.7f + 4.19f);
            
            if (r > 1.0f) r = 1.0f;
            if (g > 1.0f) g = 1.0f;
            if (b > 1.0f) b = 1.0f;
            
            uint8_t R = (uint8_t)(r * 255.0f);
            uint8_t G = (uint8_t)(g * 255.0f);
            uint8_t B = (uint8_t)(b * 255.0f);
            
            _videoBuffer[y * 240 + x] = (0xFF << 24) | (R << 16) | (G << 8) | B;
        }
    }
#endif
}

- (void)setKeys:(uint16_t)mask {
#if MGBA_AVAILABLE
    if (_core) _core->setKeys(_core, (int32_t)mask);
#endif
}

- (NSInteger)drainAudioInto:(int16_t *)buffer maxSamples:(NSInteger)maxSamples {
#if MGBA_AVAILABLE
    if (!_blipLeft || !_blipRight) return 0;
    int available = blip_samples_avail(_blipLeft);
    int toRead = (int)MIN(available, (int)maxSamples);
    if (toRead <= 0) return 0;
    
    int16_t leftBuf[toRead], rightBuf[toRead];
    blip_read_samples(_blipLeft,  leftBuf,  toRead, 0);
    blip_read_samples(_blipRight, rightBuf, toRead, 0);
    for (int i = 0; i < toRead; i++) {
        buffer[i * 2]     = leftBuf[i];
        buffer[i * 2 + 1] = rightBuf[i];
    }
    return toRead;
#else
    return 0;
#endif
}

- (void)stop {
#if MGBA_AVAILABLE
    if (_core) {
        _core->deinit(_core);
        _core = NULL;
    }
    _blipLeft  = NULL;
    _blipRight = NULL;
#endif
    _loaded = NO;
}

- (const uint32_t *)videoBuffer { return _videoBuffer; }
- (BOOL)isLoaded { return _loaded; }
- (BOOL)isStubMode { return !MGBA_AVAILABLE; }
- (NSString *)coreModeDescription {
#if MGBA_AVAILABLE
    return @"✓ REAL MGBA MODE";
#else
    return @"⚠️  STUB MODE (test only)";
#endif
}
- (NSString *)lastErrorMessage { return _lastErrorMessage ?: @""; }
- (NSInteger)renderedFrameCount { return _frameCount; }

@end
