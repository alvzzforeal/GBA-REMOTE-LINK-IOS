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
}

// MARK: - GBA Emulator Core (mGBA integration)

/// Swift wrapper around GBACoreBridge (Objective-C → mGBA C API).
/// Drop-in replacement for the stub: same protocol, same public API.
final class GBAEmulatorCore: GBACoreProtocol {

    // MARK: - Public

    var frameCallback: FrameCallback?
    var audioCallback: AudioCallback?
    private(set) var isRunning = false

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

    func loadROM(at url: URL) throws {
        var nsError: NSError?
        let ok = bridge.loadROMAtPath(url.path, error: &nsError)
        guard ok else {
            throw nsError ?? ROMError.loadFailed
        }
        setupAudio()
        print("[mGBA] ROM loaded: \(url.lastPathComponent)")
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

    /// Convert mGBA's ABGR8888 (LE) video buffer to a CGImage.
    private func makeImage() -> CGImage? {
        guard let rawPtr = bridge.videoBuffer else { return nil }

        let w = GBAEmulatorCore.screenWidth
        let h = GBAEmulatorCore.screenHeight
        let data = Data(bytes: rawPtr, count: w * h * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.noneSkipFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Audio (AVAudioEngine + AVAudioPlayerNode)

    private func setupAudio() {
        let engine     = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        // GBA outputs 32768 Hz stereo via mGBA's blip_buf resampler
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
            print("[mGBA] Audio engine start failed: \(error)")
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

    /// Pull samples from mGBA's blip buffers and hand them to AVAudioEngine.
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
            // Interleaved stereo: channelData[0] holds L+R pairs
            memcpy(dst[0], audioSampleBuffer, Int(count) * 2 * MemoryLayout<Int16>.size)
        }

        playerNode.scheduleBuffer(pcmBuffer)

        // Forward to any external consumer (e.g. link-cable audio sync)
        if audioCallback != nil {
            let samples = Array(UnsafeBufferPointer(start: audioSampleBuffer, count: Int(count) * 2))
            audioCallback?(samples)
        }
    }
}
