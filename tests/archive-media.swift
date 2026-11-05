import Foundation
import AVFoundation
import ImageIO

// Offline fixtures for archival media import: no network, no FFmpeg on PATH required.
let temp = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func writeImage(_ name: String, width: Int, height: Int, type: CFString, orientation: Int? = nil) -> URL {
    let url = temp.appendingPathComponent(name)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)!
    let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
    CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return url
}

func checkClip(_ result: [String: Any], maxWidth: Int, maxHeight: Int, label: String) -> CGSize {
    let path = result["path"] as! String
    precondition(path.hasSuffix("-archive.mp4"), "\(label): expected converted MP4")
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let track = asset.tracks(withMediaType: .video).first!
    let size = track.naturalSize.applying(track.preferredTransform)
    let width = Int(abs(size.width)), height = Int(abs(size.height))
    precondition(width % 2 == 0 && height % 2 == 0, "\(label): odd frame size \(width)x\(height)")
    precondition(width <= maxWidth && height <= maxHeight, "\(label): frame \(width)x\(height) too large")
    let duration = (result["duration"] as! Double)
    precondition(abs(duration - 1) < 0.05, "\(label): duration \(duration)")
    precondition(FileManager.default.fileExists(atPath: result["originalPath"] as! String), "\(label): original kept")
    return CGSize(width: width, height: height)
}

let root = temp.appendingPathComponent("root", isDirectory: true)

// Large landscape JPEG fits inside 1920x1080 without FFmpeg.
let wide = checkClip(try ArchiveMedia.importFile(writeImage("wide.jpg", width: 3000, height: 1500, type: "public.jpeg" as CFString),
                                                 kind: "image", root: root), maxWidth: 1920, maxHeight: 1080, label: "wide")
precondition(wide.width == 1920 && wide.height == 960, "wide: \(wide)")

// Small odd-sized PNG is upscaled to fit and rounded to even sides.
let small = checkClip(try ArchiveMedia.importFile(writeImage("small.png", width: 301, height: 401, type: "public.png" as CFString),
                                                  kind: "image", root: root), maxWidth: 1920, maxHeight: 1080, label: "small")
precondition(small.height == 1080 && small.width == 810, "small: \(small)")

// EXIF orientation 6 (rotated) is applied before fitting: landscape pixels become a portrait frame.
let rotated = checkClip(try ArchiveMedia.importFile(writeImage("rotated.jpg", width: 1600, height: 900, type: "public.jpeg" as CFString, orientation: 6),
                                                    kind: "image", root: root), maxWidth: 1920, maxHeight: 1080, label: "rotated")
precondition(rotated.height > rotated.width, "rotated: \(rotated)")

// Non-image data is rejected and leaves no files behind.
let junk = temp.appendingPathComponent("junk.jpg")
try Data("not an image".utf8).write(to: junk)
let before = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path).count
do {
    _ = try ArchiveMedia.importFile(junk, kind: "image", root: root)
    preconditionFailure("junk image accepted")
} catch {}
let after = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path).count
precondition(after == before, "junk left files")

// Web allowlist: news CDNs that host the images are allowed; lookalikes, http and credentials are not.
func allowed(_ raw: String) -> Bool { ArchiveMedia.allowedWebURL(URL(string: raw)!) }
for raw in ["https://i1-vnexpress.vnecdn.net/2023/01/01/a.jpg", "https://icdn.dantri.com.vn/a.jpg",
            "https://images2.thanhnien.vn/a.jpg", "https://znews-photo.zingcdn.me/a.jpg",
            "https://tile.loc.gov/storage-services/a.jpg", "https://gallica.bnf.fr/ark:/12148/a",
            "https://upload.wikimedia.org/wikipedia/commons/a/ab/A.jpg", "https://live.staticflickr.com/1/a.jpg"] {
    precondition(allowed(raw), "should allow \(raw)")
}
for raw in ["http://vnexpress.net/a.jpg", "https://evilvnexpress.net/a.jpg", "https://vnexpress.net.evil.com/a.jpg",
            "https://user:pass@vnexpress.net/a.jpg", "https://vnexpress.net:8443/a.jpg", "https://example.com/a.jpg"] {
    precondition(!allowed(raw), "should reject \(raw)")
}

// Generic binary content type is accepted only with a matching media extension.
let jpg = URL(string: "https://cdn.example/a.JPG")!, page = URL(string: "https://cdn.example/watch")!
precondition(ArchiveMedia.acceptableWebType("image/webp", url: page, kind: "image"))
precondition(ArchiveMedia.acceptableWebType("application/octet-stream", url: jpg, kind: "image"))
precondition(!ArchiveMedia.acceptableWebType("application/octet-stream", url: page, kind: "image"))
precondition(!ArchiveMedia.acceptableWebType("application/octet-stream", url: jpg, kind: "video"))
precondition(!ArchiveMedia.acceptableWebType("text/html", url: jpg, kind: "image"))
precondition(!ArchiveMedia.acceptableWebType("application/vnd.apple.mpegurl", url: URL(string: "https://cdn.example/a.mp4")!, kind: "video"))

print("Archive media fixtures passed: native still clips (fit, even sides, EXIF rotation, 1s), junk rejection, web allowlist, binary type guard; no network or FFmpeg")
