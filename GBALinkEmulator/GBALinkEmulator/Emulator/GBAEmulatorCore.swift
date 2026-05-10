import Foundation
import CoreGraphics
import UIKit

// MARK: - GBA Emulator Core
//
// This file is a Swift-side bridge to mGBA (or any C-based GBA core).
//
// HOW TO INTEGRATE mGBA:
// ─────────────────────────────────────────────────────────────────────
// 1. Clone mGBA: https://github.com/mgba-emu/mgba
// 2. Build libmgba.a for iOS arm64 using the CMake toolchain provided
//    in mGBA's repo (see: cmake/Toolchains/iOS.cmake).
// 3. Add the compiled static library and headers to your Xcode project.
// 4. Create a GBACoreBridge.h / GBACoreBridge.m in Objective-C and
//    add it to your Bridging Header.
// 5. Replace the stub methods below with real calls into mGBA's C API:
//    - mCoreCreate(GB_PLATFORM_GBA)
//    - core->init(core)
//    - mCoreLoadFile(core, romPath)
//    - core->reset(core)
//    - core->runFrame(core)
//    - core->setKeys(core, keyMask)
//    - blip_read_samples() / core->getAudioChannel()
// ─────────────────────────────────────────────────────────────────────

// MARK: - Frame Output

typealias FrameCallback = (CGImage?) -> Void
typealias AudioCallback = ([Int16]) -> Void

// MARK: - GBA Core Protocol

protocol GBACoreProtocol: AnyObject {
    func loadROM(at url: URL) throws
    func reset()
    func runFrame()
    func setKeys(_ mask: UInt16)
    func stop()
    var frameCallback: FrameCallback? { get set }
    var audioCallback: AudioCallback? { get set }
    var isRunning: Bool { get }
}

// MARK: - Stub Core (renders a placeholder screen)

final class GBAEmulatorCore: GBACoreProtocol {
    var frameCallback: FrameCallback?
    var audioCallback: AudioCallback?
    private(set) var isRunning = false

    private var displayLink: CADisplayLink?
    private var romURL: URL?
    private var frameCount: Int = 0

    // GBA screen resolution
    static let screenWidth  = 240
    static let screenHeight = 160

    private var pixelBuffer: [UInt32]

    init() {
        pixelBuffer = Array(
            repeating: 0xFF_1A_1A_2E,  // dark navy background
            count: GBAEmulatorCore.screenWidth * GBAEmulatorCore.screenHeight
        )
    }

    // MARK: - Load ROM

    func loadROM(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ROMError.fileNotFound
        }
        romURL = url

        // ── mGBA integration point ──
        // let cPath = url.path.cString(using: .utf8)
        // mCoreLoadFile(core, cPath)
        // core->reset(core)

        print("[GBACore] ROM loaded: \(url.lastPathComponent)")
    }

    // MARK: - Control

    func reset() {
        frameCount = 0
        // core->reset(core)
        print("[GBACore] Reset")
    }

    func setKeys(_ mask: UInt16) {
        // ── mGBA integration point ──
        // core->setKeys(core, Int32(mask))
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    // MARK: - Run Loop (60 fps via CADisplayLink)

    func runFrame() {
        guard isRunning else { return }
        frameCount += 1

        // ── mGBA integration point ──
        // core->runFrame(core)
        // Then read pixels from core->getVideoBuffer() into pixelBuffer

        renderStubFrame()

        let image = makeImage()
        frameCallback?(image)
    }

    func startDisplayLink() {
        isRunning = true
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 59, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .default)
    }

    @objc private func tick() {
        runFrame()
    }

    // MARK: - Stub Renderer (checkerboard + frame counter)

    private func renderStubFrame() {
        let w = GBAEmulatorCore.screenWidth
        let h = GBAEmulatorCore.screenHeight
        let phase = frameCount / 30

        for y in 0..<h {
            for x in 0..<w {
                let check = ((x / 20) + (y / 20) + phase) % 2 == 0
                pixelBuffer[y * w + x] = check ? 0xFF_16_213E : 0xFF_0F_3460
            }
        }

        // Draw a simple "GBA" label in the center (very basic dot-font)
        drawStubText()
    }

    private func drawStubText() {
        // Paint a bright dot pattern so the screen isn't entirely blank
        let cx = GBAEmulatorCore.screenWidth / 2
        let cy = GBAEmulatorCore.screenHeight / 2
        for r in -3...3 {
            for c in -30...30 {
                let x = cx + c
                let y = cy + r
                if x >= 0, x < GBAEmulatorCore.screenWidth,
                   y >= 0, y < GBAEmulatorCore.screenHeight {
                    pixelBuffer[y * GBAEmulatorCore.screenWidth + x] = 0xFF_E94560
                }
            }
        }
    }

    private func makeImage() -> CGImage? {
        let w = GBAEmulatorCore.screenWidth
        let h = GBAEmulatorCore.screenHeight
        guard let ctx = CGContext(
            data: &pixelBuffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
