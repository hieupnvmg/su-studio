import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Turns one still image into a short clip without any paid video model: an eased camera move over the image
/// (push in, pull out, pan, rise), optional drawn particles (dust, embers, drifting smoke, rain) and a soft vignette.
/// Everything is drawn locally with Core Graphics and written with AVAssetWriter.
enum MotionStill {
    static let moves = ["auto", "push", "pull", "left", "right", "rise"]
    static let overlays = ["none", "dust", "embers", "smoke", "rain"]

    struct Options {
        var move: String
        var overlay: String
        var seconds: Double
        var size: CGSize
        var seed: UInt64
    }

    static func error(_ message: String) -> NSError { NSError(domain: "MotionStill", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    /// Validated options from a JS request; nil when anything is out of range.
    static func options(_ body: [String: Any]) -> Options? {
        let move = body["move"] as? String ?? "auto", overlay = body["overlay"] as? String ?? "none"
        guard moves.contains(move), overlays.contains(overlay),
              let seconds = (body["seconds"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds >= 2, seconds <= 60 else { return nil }
        let vertical = body["aspectRatio"] as? String == "9:16"
        let seed = UInt64(abs((body["seed"] as? NSNumber)?.intValue ?? 1)) &+ 1
        return Options(move: move, overlay: overlay, seconds: seconds, size: vertical ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080), seed: seed)
    }

    /// The move actually used: "auto" picks one from the seed, preferring a pan when the image is much wider than the frame.
    static func resolvedMove(_ move: String, seed: UInt64, image: CGSize, frame: CGSize) -> String {
        guard move == "auto" else { return move }
        if image.width / image.height > frame.width / frame.height * 1.4 { return seed % 2 == 0 ? "left" : "right" }
        return ["push", "pull", "left", "right", "push", "rise"][Int(seed % 6)]
    }

    static func ease(_ t: Double) -> Double { let x = min(1, max(0, t)); return x * x * (3 - 2 * x) }

    /// Visible part of the image (image coordinates, origin bottom-left) at progress t ∈ [0, 1].
    static func cameraRect(move: String, progress t: Double, image: CGSize, frame: CGSize) -> CGRect {
        let aspect = frame.width / frame.height
        var base = image.width / image.height > aspect ? CGSize(width: image.height * aspect, height: image.height) : CGSize(width: image.width, height: image.width / aspect)
        let e = ease(t)
        var zoom = 1.12, cx = image.width / 2, cy = image.height / 2
        switch move {
        case "push": zoom = 1 + 0.16 * e
        case "pull": zoom = 1.16 - 0.16 * e
        case "left", "right":
            let w = base.width / zoom, travel = max(0, image.width - w) / 2
            cx = image.width / 2 + travel * (move == "left" ? 1 - 2 * e : 2 * e - 1)
        case "rise":
            let h = base.height / zoom, travel = max(0, image.height - h) / 2
            cy = image.height / 2 + travel * (2 * e - 1)
        default: zoom = 1
        }
        base = CGSize(width: base.width / zoom, height: base.height / zoom)
        let x = min(max(0, cx - base.width / 2), image.width - base.width), y = min(max(0, cy - base.height / 2), image.height - base.height)
        return CGRect(x: x, y: y, width: base.width, height: base.height)
    }

    struct Particle { var x: Double; var y: Double; var vx: Double; var vy: Double; var r: Double; var a: Double; var phase: Double }

    /// Deterministic particles in frame coordinates (seeded), so a re-render gives the same clip.
    static func particles(_ overlay: String, frame: CGSize, seed: UInt64) -> [Particle] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func random() -> Double { state = state &* 6364136223846793005 &+ 1442695040888963407; return Double(state >> 11) / Double(1 << 53) }
        let unit = frame.height / 1080, w = Double(frame.width), h = Double(frame.height)
        func make(_ count: Int, _ build: () -> Particle) -> [Particle] { (0..<count).map { _ in build() } }
        switch overlay {
        case "dust": return make(80) { Particle(x: random() * w, y: random() * h, vx: (random() - 0.5) * 30 * unit, vy: (random() - 0.5) * 18 * unit, r: (1.2 + random() * 3) * unit, a: 0.25 + random() * 0.4, phase: random() * 6.28) }
        case "embers": return make(55) { Particle(x: random() * w, y: random() * h, vx: (random() - 0.5) * 30 * unit, vy: (40 + random() * 110) * unit, r: (1.8 + random() * 3.5) * unit, a: 0.5 + random() * 0.5, phase: random() * 6.28) }
        case "rain": return make(240) { Particle(x: random() * w, y: random() * h, vx: -120 * unit, vy: -(900 + random() * 600) * unit, r: (22 + random() * 26) * unit, a: 0.18 + random() * 0.2, phase: 0) }
        default: return []
        }
    }

    /// Position of a particle at time t, wrapping around the frame.
    static func position(_ p: Particle, at t: Double, frame: CGSize) -> CGPoint {
        let w = Double(frame.width), h = Double(frame.height), margin = 60.0
        func wrap(_ v: Double, _ size: Double) -> Double { let span = size + 2 * margin; return ((v + margin).truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span) - margin }
        return CGPoint(x: wrap(p.x + p.vx * t + sin(t * 0.9 + p.phase) * 8, w), y: wrap(p.y + p.vy * t, h))
    }

    /// Soft drifting fog made once from blurred noise; drawn twice per frame at different speeds.
    static func smokeTexture(_ frame: CGSize) -> CGImage? {
        // Low-resolution noise scaled up gives cloud-sized patches; blur softens the edges.
        let size = CGRect(x: 0, y: 0, width: frame.width / 4, height: frame.height / 4)
        let cell = CGRect(x: 0, y: 0, width: ceil(size.width / 22) + 2, height: ceil(size.height / 22) + 2)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: cell).settingAlphaOne(in: cell).samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: 22, y: 22)).clampedToExtent()
            .applyingGaussianBlur(sigma: 16).cropped(to: size)
        // Grey mask (fog density) from the red channel, then a proper premultiplied fog colour through it.
        let density = CIVector(x: 3.5, y: 0, z: 0, w: 0)
        let mask = noise.applyingFilter("CIColorMatrix", parameters: ["inputRVector": density, "inputGVector": density, "inputBVector": density,
                                                                      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: -1.47, y: -1.47, z: -1.47, w: 1)])
        let fogColour = CIImage(color: CIColor(red: 0.86, green: 0.86, blue: 0.84)).cropped(to: size)
        let fog = fogColour.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: size), kCIInputMaskImageKey: mask])
        // No colour management: the noise stays a plain 0…1 density instead of being gamma-shifted.
        return CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()]).createCGImage(fog, from: size, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Renders the clip. `progress` gets 0…1; returning true from `cancelled` stops and removes the file.
    static func render(image source: URL, to output: URL, options: Options, progress: (Double) -> Void = { _ in }, cancelled: () -> Bool = { false }) throws {
        let frame = options.size, fps = 30, total = Int((options.seconds * Double(fps)).rounded())
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: Int(max(frame.width, frame.height) * 1.6)] as CFDictionary),
              image.width > 0, image.height > 0 else { throw error("Không đọc được ảnh của cảnh.") }
        let imageSize = CGSize(width: image.width, height: image.height)
        let move = resolvedMove(options.move, seed: options.seed, image: imageSize, frame: frame)
        let dots = particles(options.overlay, frame: frame, seed: options.seed)
        let smoke = options.overlay == "smoke" ? smokeTexture(frame) : nil
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(frame.width), AVVideoHeightKey: Int(frame.height),
                                                                           AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: frame.width * frame.height * 6]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(frame.width), kCVPixelBufferHeightKey as String: Int(frame.height)])
        guard writer.canAdd(input) else { throw error("Không chuẩn bị được bộ ghi video.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? error("Không ghi được video.") }
        writer.startSession(atSourceTime: .zero)
        func fail(_ e: Error) -> Error { writer.cancelWriting(); try? FileManager.default.removeItem(at: output); return e }
        let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.38)] as CFArray, locations: [0.55, 1])!
        for index in 0..<total {
            if cancelled() { throw fail(error("Đã dừng tạo ảnh động.")) }
            let t = Double(index) / Double(fps)
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixels = buffer else { throw fail(error("Hết bộ nhớ khung hình.")) }
            CVPixelBufferLockBaseAddress(pixels, [])
            guard let cg = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: Int(frame.width), height: Int(frame.height), bitsPerComponent: 8,
                                     bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                CVPixelBufferUnlockBaseAddress(pixels, []); throw fail(error("Không vẽ được khung hình."))
            }
            cg.interpolationQuality = .high
            cg.setFillColor(CGColor(gray: 0, alpha: 1)); cg.fill(CGRect(origin: .zero, size: frame))
            // Draw the whole image scaled so the camera rect fills the frame.
            let rect = cameraRect(move: move, progress: total > 1 ? Double(index) / Double(total - 1) : 0, image: imageSize, frame: frame)
            let scale = frame.width / rect.width
            cg.draw(image, in: CGRect(x: -rect.minX * scale, y: -rect.minY * scale, width: imageSize.width * scale, height: imageSize.height * scale))
            if let smoke = smoke {
                // Alternate normal and mirrored copies so the drifting texture has no visible seam.
                for (speed, alpha) in [(18.0, 0.45), (34.0, 0.32)] {
                    let shift = (t * speed * Double(frame.height) / 1080).truncatingRemainder(dividingBy: Double(frame.width) * 2)
                    cg.setAlpha(alpha)
                    for (k, x) in [-shift, frame.width - shift, frame.width * 2 - shift].enumerated() {
                        cg.saveGState()
                        if k == 1 { cg.translateBy(x: x + frame.width, y: 0); cg.scaleBy(x: -1, y: 1); cg.draw(smoke, in: CGRect(origin: .zero, size: frame)) }
                        else { cg.draw(smoke, in: CGRect(x: x, y: 0, width: frame.width, height: frame.height)) }
                        cg.restoreGState()
                    }
                }
                cg.setAlpha(1)
            }
            for p in dots {
                let at = position(p, at: t, frame: frame)
                switch options.overlay {
                case "embers":
                    let flicker = 0.6 + 0.4 * sin(t * 7 + p.phase)
                    cg.setFillColor(CGColor(red: 1, green: 0.45, blue: 0.1, alpha: p.a * 0.25 * flicker))
                    cg.fillEllipse(in: CGRect(x: at.x - p.r * 3, y: at.y - p.r * 3, width: p.r * 6, height: p.r * 6))
                    cg.setFillColor(CGColor(red: 1, green: 0.78, blue: 0.35, alpha: p.a * flicker))
                    cg.fillEllipse(in: CGRect(x: at.x - p.r, y: at.y - p.r, width: p.r * 2, height: p.r * 2))
                case "rain":
                    cg.setStrokeColor(CGColor(red: 0.85, green: 0.9, blue: 1, alpha: p.a)); cg.setLineWidth(1.6 * frame.height / 1080)
                    cg.move(to: at); cg.addLine(to: CGPoint(x: at.x + p.vx / p.vy * p.r, y: at.y + p.r)); cg.strokePath()
                default:
                    cg.setFillColor(CGColor(red: 1, green: 0.96, blue: 0.86, alpha: p.a * (0.7 + 0.3 * sin(t * 1.3 + p.phase))))
                    cg.fillEllipse(in: CGRect(x: at.x - p.r, y: at.y - p.r, width: p.r * 2, height: p.r * 2))
                }
            }
            let centre = CGPoint(x: frame.width / 2, y: frame.height / 2)
            cg.drawRadialGradient(vignette, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: hypot(frame.width, frame.height) / 2, options: [.drawsAfterEndLocation])
            CVPixelBufferUnlockBaseAddress(pixels, [])
            while !input.isReadyForMoreMediaData && writer.status == .writing { Thread.sleep(forTimeInterval: 0.003) }
            guard writer.status == .writing, adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) else { throw fail(writer.error ?? error("Không ghi được khung hình.")) }
            if index % 15 == 0 { progress(Double(index) / Double(total)) }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(total), timescale: CMTimeScale(fps)))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw fail(writer.error ?? error("Không hoàn tất được video.")) }
        progress(1)
    }
}
