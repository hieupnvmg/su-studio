import Foundation
import AVFoundation
import AppKit
// Ảnh động: camera moves, particles, both orientations, validation and cancellation.
let out = URL(fileURLWithPath: CommandLine.arguments[1]), shots = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// A landscape test picture: left half red, right half blue, a green band at the top.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 800, height: 900).fill()
NSColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1).setFill(); NSRect(x: 800, y: 0, width: 800, height: 900).fill()
NSColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1).setFill(); NSRect(x: 0, y: 780, width: 1600, height: 120).fill()
NSGraphicsContext.restoreGraphicsState()
let picture = out.appendingPathComponent("scene.png"); try rep.representation(using: .png, properties: [:])!.write(to: picture)

precondition(MotionStill.options(["move": "push", "overlay": "dust", "seconds": 6])?.size == CGSize(width: 1920, height: 1080))
precondition(MotionStill.options(["move": "left", "overlay": "none", "seconds": 6, "aspectRatio": "9:16"])?.size == CGSize(width: 1080, height: 1920))
precondition(MotionStill.options(["move": "spin", "seconds": 6]) == nil && MotionStill.options(["overlay": "fire", "seconds": 6]) == nil)
precondition(MotionStill.options(["seconds": 1]) == nil && MotionStill.options(["seconds": 61]) == nil && MotionStill.options([:]) == nil)

let image = CGSize(width: 1600, height: 900), wide = CGSize(width: 1920, height: 1080), tall = CGSize(width: 1080, height: 1920)
for move in ["push", "pull", "left", "right", "rise"] {
    for frame in [wide, tall] {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            let r = MotionStill.cameraRect(move: move, progress: t, image: image, frame: frame)
            precondition(r.minX >= -0.001 && r.minY >= -0.001 && r.maxX <= image.width + 0.001 && r.maxY <= image.height + 0.001, "\(move) stays inside the image")
            precondition(abs(r.width / r.height - frame.width / frame.height) < 0.001, "\(move) keeps the frame aspect")
        }
    }
}
let pushStart = MotionStill.cameraRect(move: "push", progress: 0, image: image, frame: wide), pushEnd = MotionStill.cameraRect(move: "push", progress: 1, image: image, frame: wide)
precondition(pushEnd.width < pushStart.width * 0.9 && abs(pushEnd.midX - pushStart.midX) < 0.5, "push zooms into the centre")
let leftStart = MotionStill.cameraRect(move: "left", progress: 0, image: image, frame: tall), leftEnd = MotionStill.cameraRect(move: "left", progress: 1, image: image, frame: tall)
precondition(leftStart.midX > leftEnd.midX + 500, "left pans across a landscape image in a vertical frame")
precondition(MotionStill.resolvedMove("auto", seed: 3, image: image, frame: tall) == "right" || MotionStill.resolvedMove("auto", seed: 3, image: image, frame: tall) == "left", "auto pans when the image is much wider than the frame")
precondition(MotionStill.particles("dust", frame: wide, seed: 7).count == 80 && MotionStill.particles("none", frame: wide, seed: 7).isEmpty)
precondition(MotionStill.particles("embers", frame: wide, seed: 7).map(\.x) == MotionStill.particles("embers", frame: wide, seed: 7).map(\.x), "particles are deterministic")
let p = MotionStill.Particle(x: 10, y: 10, vx: 0, vy: 5000, r: 2, a: 1, phase: 0)
precondition((0..<20).allSatisfy { let at = MotionStill.position(p, at: Double($0), frame: wide); return at.y >= -60 && at.y <= 1140 }, "particles wrap around")

func frame(_ url: URL, _ seconds: Double) throws -> NSBitmapImageRep {
    let g = AVAssetImageGenerator(asset: AVURLAsset(url: url)); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
    return NSBitmapImageRep(cgImage: try g.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil))
}
func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor { rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)! }
for (name, body) in [("push-embers", ["move": "push", "overlay": "embers", "seconds": 3, "seed": 4] as [String: Any]),
                     ("left-smoke-tall", ["move": "left", "overlay": "smoke", "seconds": 3, "aspectRatio": "9:16", "seed": 2]),
                     ("rise-rain", ["move": "rise", "overlay": "rain", "seconds": 2, "seed": 9]),
                     ("pull-dust", ["move": "pull", "overlay": "dust", "seconds": 2, "seed": 5])] {
    let options = MotionStill.options(body)!, clip = out.appendingPathComponent(name + ".mp4")
    var reported: [Double] = []
    try MotionStill.render(image: picture, to: clip, options: options, progress: { reported.append($0) })
    let asset = AVURLAsset(url: clip), track = asset.tracks(withMediaType: .video).first!
    precondition(abs(asset.duration.seconds - options.seconds) < 0.05 && track.naturalSize == options.size, "\(name): \(asset.duration.seconds) \(track.naturalSize)")
    precondition(reported.last == 1 && zip(reported, reported.dropFirst()).allSatisfy { $0 <= $1 }, "progress rises to 1")
    let first = try frame(clip, 0), last = try frame(clip, options.seconds - 0.05)
    if let shots = shots { for (label, rep) in [("first", first), ("last", last)] { try rep.representation(using: .png, properties: [:])!.write(to: shots.appendingPathComponent("\(name)-\(label).png")) } }
    if name == "left-smoke-tall" {
        precondition(color(first, 540, 960).blueComponent > 0.45 && color(last, 540, 960).redComponent > 0.45, "pan travels from the right (blue) to the left (red) half")
    }
    if name == "push-embers" {
        var orange = 0
        for y in stride(from: 0, to: 1080, by: 4) { for x in stride(from: 0, to: 1920, by: 4) { let c = color(last, x, y); if c.redComponent > 0.9 && c.greenComponent > 0.55 && c.blueComponent < 0.5 { orange += 1 } } }
        precondition(orange > 5, "embers are drawn (\(orange))")
        // Bitmap rows count from the top: the green band at the top gets thinner as the camera pushes in.
        func band(_ rep: NSBitmapImageRep) -> Int { (0..<400).filter { let c = color(rep, 960, $0); return c.greenComponent > 0.5 && c.redComponent < 0.4 }.count }
        precondition(band(first) > band(last) + 30 && band(last) > 20, "push in crops into the top band (\(band(first)) → \(band(last)))")
    }
}
// Cancelling stops early and leaves no file.
let cancelled = out.appendingPathComponent("cancel.mp4"); var calls = 0
do { try MotionStill.render(image: picture, to: cancelled, options: MotionStill.options(["seconds": 10])!, cancelled: { calls += 1; return calls > 5 }); fatalError("not cancelled") } catch {}
precondition(!FileManager.default.fileExists(atPath: cancelled.path), "cancelled clip removed")
do { try MotionStill.render(image: out.appendingPathComponent("missing.png"), to: cancelled, options: MotionStill.options(["seconds": 2])!); fatalError("missing image accepted") } catch {}
print("Motion still passed: eased camera moves inside the image, both orientations, deterministic dust/embers/smoke/rain overlays, progress, cancel, invalid options")
