#import "GBACoreBridge.h"
#import <math.h>

// ---------------------------------------------------------------------------
// mGBA C headers
// Activated automatically when libmgba.a + headers are added to the project.
// ---------------------------------------------------------------------------
#ifdef __has_include
  #if __has_include(<mgba/core/core.h>)
    #include <mgba/core/core.h>
    #include <mgba/core/blip_buf.h>
    #include <mgba/gba/interface.h>
    #include <mgba/internal/gba/gba.h>
    #define MGBA_AVAILABLE 1
  #else
    #define MGBA_AVAILABLE 0
    #warning "mGBA headers not found — GBACoreBridge running in STUB mode. See header for integration steps."
  #endif
#endif

#if !defined(MGBA_AVAILABLE)
  #define MGBA_AVAILABLE 0
#endif

// Stub shims so the file compiles without mGBA
#if !MGBA_AVAILABLE
typedef void mCore;
static inline mCore *mCoreCreate(int p) { (void)p; return NULL; }
static inline void   mCoreDeinit(mCore *c) { (void)c; }
#endif

// Audio constants
static const int kSampleRate   = 32768;
static const int kAudioBufSize = 4096;

// ---------------------------------------------------------------------------
@interface GBACoreBridge () {
#if MGBA_AVAILABLE
    struct mCore  *_core;
    struct GBA    *_gba;
    blip_t        *_blipLeft;
    blip_t        *_blipRight;
#else
    void          *_core;   // placeholder — never used
#endif
    uint32_t  _videoBuffer[240 * 160];
    int16_t   _audioStereo[kAudioBufSize * 2];
    BOOL      _loaded;
    int       _frameCount;  // used by stub animation
}
@end

@implementation GBACoreBridge

// MARK: - Init / Dealloc

- (instancetype)init {
    if (!(self = [super init])) return nil;
    memset(_videoBuffer, 0, sizeof(_videoBuffer));
    _loaded     = NO;
    _frameCount = 0;
    return self;
}

- (void)dealloc {
    [self stop];
}

// MARK: - Public API
// NOTE: Swift imports this as loadROM(atPath:) due to NS_SWIFT_NAME in the header.
//       The ObjC selector is loadROM:error:
//       Old name was loadROMAtPath:error: — that mismatch caused silent failure.

- (BOOL)loadROM:(NSString *)path error:(NSError **)outError {
#if MGBA_AVAILABLE
    // ── Real mGBA path ────────────────────────────────────────────────────
    _core = mCoreCreate(PLATFORM_GBA);
    if (!_core) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"mCoreCreate failed — mGBA library may be corrupt."}];
        }
        return NO;
    }

    _core->init(_core);
    _core->setVideoBuffer(_core, _videoBuffer, kGBAScreenWidth);
    _core->setAudioBufferSize(_core, kAudioBufSize);

    _blipLeft  = _core->getAudioChannel(_core, 0);
    _blipRight = _core->getAudioChannel(_core, 1);
    if (_blipLeft)  blip_set_rates(_blipLeft,  _core->frequency(_core), kSampleRate);
    if (_blipRight) blip_set_rates(_blipRight, _core->frequency(_core), kSampleRate);

    const char *cPath = [path fileSystemRepresentation];
    if (!mCoreLoadFile(_core, cPath)) {
        NSString *desc = [NSString stringWithFormat:
            @"mCoreLoadFile failed.\nPath: %@\n\nCheck that the file is a valid .gba ROM and is accessible.", path];
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:2
                            userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        [self stop];
        return NO;
    }

    _core->reset(_core);
    _loaded = YES;
    NSLog(@"[GBABridge-mGBA] ROM loaded: %@", path.lastPathComponent);
    return YES;

#else
    // ── STUB path ─────────────────────────────────────────────────────────
    // mGBA is not linked. We verify the file exists and looks like a GBA ROM,
    // then return success so the animation pipeline can be tested.
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GBABridge" code:10
                            userInfo:@{NSLocalizedDescriptionKey:
                                @"ROM file not found on disk."}];
        }
        return NO;
    }

    // Minimal GBA header check: byte 0xB2 must be 0x96 (Nintendo logo checksum)
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (fh) {
        [fh seekToFileOffset:0xB2];
        NSData *magic = [fh readDataOfLength:1];
        [fh closeFile];
        if (magic.length == 1) {
            uint8_t byte = ((uint8_t *)magic.bytes)[0];
            if (byte != 0x96) {
                NSLog(@"[GBABridge-STUB] Warning: byte at 0xB2 = 0x%02X (expected 0x96). File may not be a valid GBA ROM.", byte);
            }
        }
    }

    _loaded = YES;
    _frameCount = 0;
    NSLog(@"[GBABridge-STUB] mGBA NOT linked. Running stub renderer for: %@", path.lastPathComponent);
    NSLog(@"[GBABridge-STUB] To enable real emulation, add libmgba.a. See GBACoreBridge.h for steps.");
    return YES;
#endif
}

- (void)reset {
#if MGBA_AVAILABLE
    if (_core) _core->reset(_core);
#else
    _frameCount = 0;
#endif
}

- (void)runFrame {
#if MGBA_AVAILABLE
    if (_core && _loaded) {
        _core->runFrame(_core);
    }
#else
    if (!_loaded) return;

    // ── STUB RENDERER ─────────────────────────────────────────────────────
    // Renders a GBA-boot-logo-style animation so you can confirm that:
    //   1. runFrame is being called (display link is working)
    //   2. videoBuffer → CGImage pipeline is working
    //   3. The frame appears on screen
    //
    // Replace this entire block with real mGBA once libmgba.a is linked.
    // ─────────────────────────────────────────────────────────────────────
    _frameCount++;
    float t = _frameCount / 60.0f;

    for (int y = 0; y < 160; y++) {
        for (int x = 0; x < 240; x++) {
            // Animated gradient + scanline pattern
            float fx = (float)x / 239.0f;
            float fy = (float)y / 159.0f;

            // Scrolling colour wave
            float r = 0.5f + 0.5f * sinf(fx * 6.28f + t * 1.3f);
            float g = 0.5f + 0.5f * sinf(fy * 6.28f + t * 0.9f + 2.09f);
            float b = 0.5f + 0.5f * sinf((fx + fy) * 4.0f + t * 1.7f + 4.19f);

            // Darken every 3rd scanline to simulate CRT
            float scanline = ((y % 3) == 0) ? 0.82f : 1.0f;
            r *= scanline; g *= scanline; b *= scanline;

            // Clamp
            if (r > 1.0f) r = 1.0f;
            if (g > 1.0f) g = 1.0f;
            if (b > 1.0f) b = 1.0f;

            uint8_t R = (uint8_t)(r * 255.0f);
            uint8_t G = (uint8_t)(g * 255.0f);
            uint8_t B = (uint8_t)(b * 255.0f);

            // ARGB8888, little-endian (matches CGBitmapInfo in Swift)
            _videoBuffer[y * 240 + x] = (0xFF << 24) | (R << 16) | (G << 8) | B;
        }
    }
#endif
}

- (void)setKeys:(uint16_t)mask {
#if MGBA_AVAILABLE
    if (_core) _core->setKeys(_core, (int32_t)mask);
#endif
    // Stub: keys are ignored (no game logic)
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
    return 0;   // No audio in stub mode
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
- (BOOL)isStubMode              { return !MGBA_AVAILABLE; }

@end
