import Foundation
import CoreGraphics
import UIKit
import AVFoundation

// MARK: - Frame / Audio Callbacks

typealias FrameCallback = (CGImage?) -> Void
typealias AudioCallback = ([Int16]) -> Void

// MARK: - GBA Core Protocol

protocol GBACoreProtocol: AnyObject {
    func loadROM(at url: URL) throws
    func reset()
    func runFrame()
    func setKeys(_ mask: UInt16)
    func stop()
    func startDisplayLink()
    var frameCallback: FrameCallback? { get set }
    var audioCallback: AudioCallback? { get set }
    var isRunning: Bool { get }
    var isStub: Bool { get }
}

// MARK: - GBA Emulator Core

/// Swift wrapper around GBACoreBridge (Objective-C → mGBA C API).
///
/// BUG FIXED (was causing black screen):
///   The old code called `bridge.loadROM(atPath: url.path)` but the ObjC method
///   was declared as `loadROMAtPath:error:` — a different selector.
///   Swift would silently compile this as a call to a missing method and crash
///   or do nothing at runtime. Fixed by renaming the ObjC method to `loadROM:error:`
///   with NS_SWIFT_NAME(loadROM(atPath:)), so Swift/ObjC selectors now match.
final class GBAEmulatorCore: GBACoreProtocol {

    // MARK: - Public

    var frameCallback: FrameCallback?
    var audioCallback: AudioCallback?
    private(set) var isRunning = false

    /// True when mGBA is not linked and the bridge runs in stub/demo mode.
    var isStub: Bool { bridge.isStubMode }

    // GBA hardware screen size (fixed)
    static let screenWidth  = 240
    static let screenHeight = 160

    // MARK: - Private

    private let bridge = GBACoreBridge()
    private var displayLink: CADisplayLink?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private let audioSampleBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: 8192)

    // MARK: - Init / Deinit

    init() {}

    deinit {
        stop()
        audioSampleBuffer.deallocate()
    }

    // MARK: - GBACoreProtocol

    /// Load a ROM from the given URL.
    /// Throws a descriptive error if loading fails (file missing, invalid ROM, etc.)
    func loadROM(at url: URL) throws {
        // FIX: Previously called bridge.loadROM(atPath:) which matched the WRONG
        // ObjC selector (loadROMAtPath:error: vs loadROM:error:).
        // Now the ObjC bridge declares the method as loadROM:error: with
        // NS_SWIFT_NAME(loadROM(atPath:)) so the call below works correctly.
        try bridge.loadROM(atPath: url.path)
        setupAudio()
        print("[GBACore] ROM loaded: \(url.lastPathComponent) | stub=\(bridge.isStubMode)")
    }

    func reset() {
        bridge.reset()
    }

    func setKeys(_ mask: UInt16) {
        bridge.setKeys(mask)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        bridge.stop()
        teardownAudio()
    }

    /// Run exactly one GBA frame; called by the CADisplayLink tick on the main thread.
    func runFrame() {
        guard isRunning else { return }
        bridge.runFrame()
        let image = makeImage()
        frameCallback?(image)
        drainAndScheduleAudio()
    }

    func startDisplayLink() {
        isRunning = true
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 59, maximum: 60, preferred: 60)
        dl.add(to: .main, forMode: .default)
        displayLink = dl
    }

    // MARK: - CADisplayLink Target

    @objc private func tick() { runFrame() }

    // MARK: - Video → CGImage

    /// Convert mGBA's (or stub's) ARGB8888 video buffer to a CGImage.
    private func makeImage() -> CGImage? {
        guard let rawPtr = bridge.videoBuffer else { return nil }

        let w = GBAEmulatorCore.screenWidth
        let h = GBAEmulatorCore.screenHeight
        let byteCount = w * h * 4

        // Wrap the raw buffer in a Data without copying (zero-copy path).
        // The bridge owns the memory for the duration of runFrame.
        let data = Data(bytes: rawPtr, count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            // ARGB8888 little-endian: matches how both mGBA and the stub write pixels
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.noneSkipFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Audio (AVAudioEngine)

    private func setupAudio() {
        // Stub mode produces no audio — skip engine setup to save resources
        guard !bridge.isStubMode else { return }

        let engine     = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 32768,
            channels: 2,
            interleaved: true
        ) else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            print("[GBACore] Audio engine start failed: \(error)")
            return
        }

        playerNode.play()
        audioEngine     = engine
        audioPlayerNode = playerNode
        audioFormat     = format
    }

    private func teardownAudio() {
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioEngine     = nil
        audioPlayerNode = nil
        audioFormat     = nil
    }

    private func drainAndScheduleAudio() {
        guard let playerNode = audioPlayerNode,
              let format = audioFormat else { return }

        let count = bridge.drainAudio(into: audioSampleBuffer, maxSamples: 4096)
        guard count > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(count)
        ) else { return }

        pcmBuffer.frameLength = AVAudioFrameCount(count)
        if let dst = pcmBuffer.int16ChannelData {
            memcpy(dst[0], audioSampleBuffer, Int(count) * 2 * MemoryLayout<Int16>.size)
        }

        playerNode.scheduleBuffer(pcmBuffer)

        if audioCallback != nil {
            let samples = Array(UnsafeBufferPointer(start: audioSampleBuffer, count: Int(count) * 2))
            audioCallback?(samples)
        }
    }
}
