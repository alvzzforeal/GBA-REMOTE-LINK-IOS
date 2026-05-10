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

// MARK: - GBA Emulator Core (real mGBA integration)

/// Swift wrapper around GBACoreBridge (Objective-C → mGBA C API).
/// Executes GBA games in real-time with audio and display link synchronization.
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

    var isStubMode: Bool { bridge.isStubMode }
    var coreModeDescription: String { bridge.coreModeDescription }
    var lastErrorMessage: String { bridge.lastErrorMessage }
    var renderedFrameCount: Int { bridge.renderedFrameCount }
    
    private var displayLink: CADisplayLink?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private let audioSampleBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: 8192)
    
    // FPS diagnostics
    private var fpsStartTime: Date?
    private var fpsFrameCount = 0
    private var currentFPS: Double = 0.0
    
    var diagnosticString: String {
        return String(format: "FPS: %.1f | Frames: %ld | %s", 
                     currentFPS, bridge.renderedFrameCount,
                     bridge.coreModeDescription)
    }

    // MARK: - Init / Deinit

    init() {}

    deinit {
        stop()
        audioSampleBuffer.deallocate()
    }

    // MARK: - GBACoreProtocol

    func loadROM(at url: URL) throws {
        print("[GBAEmulatorCore] ════════════════════════════════════════")
        print("[GBAEmulatorCore] LOADING ROM: \(url.lastPathComponent)")
        print("[GBAEmulatorCore] Full path: \(url.path)")
        print("[GBAEmulatorCore] ════════════════════════════════════════")
        
        var nsError: NSError?
        let success = bridge.loadROM(atPath: url.path, error: &nsError)
        
        if !success {
            let errorMsg = nsError?.localizedDescription ?? bridge.lastErrorMessage
            print("[GBAEmulatorCore] ❌ LOAD FAILED: \(errorMsg)")
            throw nsError ?? NSError(domain: "GBAEmulatorCore", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        print("[GBAEmulatorCore] ✅ ROM loaded successfully")
        print("[GBAEmulatorCore] Core mode: \(bridge.coreModeDescription)")
        print("[GBAEmulatorCore] Stub mode: \(bridge.isStubMode)")
        print("[GBAEmulatorCore] ════════════════════════════════════════")
        
        setupAudio()
        initializeFPSCounter()
    }

    func reset() {
        print("[GBAEmulatorCore] Resetting core")
        bridge.reset()
    }

    func setKeys(_ mask: UInt16) {
        bridge.setKeys(mask)
    }

    func stop() {
        print("[GBAEmulatorCore] Stopping emulation")
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        bridge.stop()
        teardownAudio()
    }

    /// Run exactly one GBA frame; called by CADisplayLink on main thread.
    func runFrame() {
        guard isRunning else { return }
        
        bridge.runFrame()
        updateFPSCounter()
        
        let image = makeImage()
        frameCallback?(image)
        drainAndScheduleAudio()
    }

    func startDisplayLink() {
        print("[GBAEmulatorCore] Starting CADisplayLink (60 FPS)")
        isRunning = true
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 59, maximum: 60, preferred: 60)
        dl.add(to: .main, forMode: .default)
        displayLink = dl
    }

    // MARK: - CADisplayLink Target

    @objc private func tick() { runFrame() }

    // MARK: - Video → CGImage

    /// Convert mGBA's ARGB8888 video buffer to CGImage.
    private func makeImage() -> CGImage? {
        guard let rawPtr = bridge.videoBuffer else {
            print("[GBAEmulatorCore] ERROR: videoBuffer is nil")
            return nil
        }

        let w = GBAEmulatorCore.screenWidth
        let h = GBAEmulatorCore.screenHeight
        let data = Data(bytes: rawPtr, count: w * h * 4)
        guard let provider = CGDataProvider(data: data as CFData) else {
            print("[GBAEmulatorCore] ERROR: Failed to create CGDataProvider")
            return nil
        }

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

    // MARK: - FPS Counter

    private func initializeFPSCounter() {
        fpsStartTime = Date()
        fpsFrameCount = 0
        currentFPS = 0.0
    }

    private func updateFPSCounter() {
        fpsFrameCount += 1
        
        guard let startTime = fpsStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        
        if elapsed >= 1.0 {
            currentFPS = Double(fpsFrameCount) / elapsed
            print(String(format: "[GBAEmulatorCore] FPS: %.2f (frames: %d)", 
                        currentFPS, fpsFrameCount))
            fpsStartTime = Date()
            fpsFrameCount = 0
        }
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
        ) else {
            print("[GBAEmulatorCore] ERROR: Could not create audio format")
            return
        }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            print("[GBAEmulatorCore] ✓ Audio engine started (32768 Hz stereo)")
        } catch {
            print("[GBAEmulatorCore] ❌ Audio engine start failed: \(error)")
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

    /// Pull samples from mGBA's blip buffers and send to AVAudioEngine.
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
