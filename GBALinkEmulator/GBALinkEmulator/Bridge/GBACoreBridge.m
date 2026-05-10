#import "GBACoreBridge.h"

// ---------------------------------------------------------------------------
// mGBA C headers
// These are installed by the mGBA Swift Package / xcframework.
// The SPM plugin copies them into the DerivedData include path automatically.
// If you use a manual libmgba.a, add the include path in Xcode build settings:
//   Header Search Paths → $(SRCROOT)/mGBA/include
// ---------------------------------------------------------------------------
#ifdef __has_include
  #if __has_include(<mgba/core/core.h>)
    #include <mgba/core/core.h>
    #include <mgba/core/blip_buf.h>
    #include <mgba/gba/interface.h>
    #include <mgba/internal/gba/gba.h>
    #define MGBA_AVAILABLE 1
  #else
    // mGBA not yet present → compile stub so the project still builds
    #define MGBA_AVAILABLE 0
    #warning "mGBA headers not found. GBACoreBridge will run in STUB mode."
  #endif
#endif

#if !defined(MGBA_AVAILABLE)
  #define MGBA_AVAILABLE 0
#endif

// ---------------------------------------------------------------------------
// Stub type aliases (used when MGBA_AVAILABLE == 0 so Xcode doesn't error out)
// ---------------------------------------------------------------------------
#if !MGBA_AVAILABLE
typedef void mCore;
static inline mCore *mCoreCreate(int p) { (void)p; return NULL; }
static inline void   mCoreDeinit(mCore *c) { (void)c; }
#endif

// MARK: - Audio constants
static const int kSampleRate   = 32768;   // GBA native sample rate
static const int kAudioBufSize = 4096;    // stereo int16 pairs per frame

// ---------------------------------------------------------------------------
@interface GBACoreBridge () {
#if MGBA_AVAILABLE
    struct mCore     *_core;
    struct GBA       *_gba;
    blip_t           *_blipLeft;
    blip_t           *_blipRight;
#else
    void             *_core;           // placeholder
#endif
    uint32_t          _videoBuffer[240 * 160];
    int16_t           _audioStereo[kAudioBufSize * 2];
    BOOL              _loaded;
}
@end

@implementation GBACoreBridge

// MARK: - Init / Dealloc

- (instancetype)init {
    if (!(self = [super init])) return nil;
    memset(_videoBuffer, 0, sizeof(_videoBuffer));
    _loaded = NO;
    return self;
}

- (void)dealloc {
    [self stop];
}

// MARK: - Public API

- (BOOL)loadROMAtPath:(NSString *)path error:(NSError **)outError {
#if MGBA_AVAILABLE
    // 1. Create the mGBA core for GBA platform
    _core = mCoreCreate(PLATFORM_GBA);
    if (!_core) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"mCoreCreate failed"}];
        }
        return NO;
    }

    // 2. Initialise core internals
    _core->init(_core);

    // 3. Point video buffer at our local buffer (ARGB8888, 240×160)
    _core->setVideoBuffer(_core, _videoBuffer, kGBAScreenWidth);

    // 4. Configure audio: 32768 Hz, stereo, ~60fps worth of samples
    _core->setAudioBufferSize(_core, kAudioBufSize);
    _blipLeft  = _core->getAudioChannel(_core, 0);
    _blipRight = _core->getAudioChannel(_core, 1);
    if (_blipLeft)  blip_set_rates(_blipLeft,  _core->frequency(_core), kSampleRate);
    if (_blipRight) blip_set_rates(_blipRight, _core->frequency(_core), kSampleRate);

    // 5. Load the ROM
    const char *cPath = [path fileSystemRepresentation];
    if (!mCoreLoadFile(_core, cPath)) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"mCoreLoadFile failed: %@", path]}];
        }
        [self stop];
        return NO;
    }

    // 6. Reset to boot state
    _core->reset(_core);
    _loaded = YES;
    return YES;

#else
    // ─── STUB mode ──────────────────────────────────────────────────────────
    // mGBA not linked yet. Return YES so the rest of the app remains usable.
    NSLog(@"[GBABridge] STUB – mGBA not linked. ROM not actually loaded.");
    _loaded = YES;
    return YES;
#endif
}

- (void)reset {
#if MGBA_AVAILABLE
    if (_core) _core->reset(_core);
#endif
}

- (void)runFrame {
#if MGBA_AVAILABLE
    if (_core && _loaded) {
        _core->runFrame(_core);
    }
#else
    // Stub: paint an animated checkerboard into _videoBuffer
    static int frame = 0; frame++;
    int phase = (frame / 30) & 1;
    for (int y = 0; y < 160; y++) {
        for (int x = 0; x < 240; x++) {
            int check = (((x / 20) + (y / 20) + phase) & 1);
            _videoBuffer[y * 240 + x] = check ? 0xFF1A2E50 : 0xFF0F3460;
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
    int toRead    = (int)MIN(available, (int)maxSamples);
    if (toRead <= 0) return 0;

    // Read into temporary mono buffers, then interleave
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

// MARK: - Properties

- (const uint32_t *)videoBuffer { return _videoBuffer; }
- (BOOL)isLoaded                { return _loaded; }

@end
