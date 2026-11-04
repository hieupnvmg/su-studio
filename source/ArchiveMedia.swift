import Foundation
import AVFoundation
import ImageIO

enum ArchiveMedia {
    static func error(_ message: String) -> NSError {
        NSError(domain: "ArchiveMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func search(_ query: String, kind: String) async throws -> [[String: Any]] {
        var url = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        let type = kind == "video" ? "video" : "bitmap"
        let parameters = [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "search", "gsrnamespace": "6", "gsrlimit": "12",
            "gsrsearch": "\(query) filetype:\(type)", "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata", "iiurlwidth": "320",
            "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl"
        ]
        url.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!, timeoutInterval: 25)
        request.setValue("SuStudio/0.13 (https://github.com/hieupnvmg/su-studio)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil else { throw error("Không tìm được tư liệu từ Wikimedia Commons. Thử lại sau.") }
        let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
        return pages.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }.compactMap { page in
            guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  let title = page["title"] as? String, let media = info["url"] as? String,
                  let source = info["descriptionurl"] as? String,
                  let mime = info["mime"] as? String, mime.hasPrefix(kind + "/") || (kind == "video" && mime == "application/ogg" && URL(string: media)?.pathExtension.lowercased() == "ogv") else { return nil }
            let metadata = info["extmetadata"] as? [String: [String: Any]] ?? [:]
            func value(_ key: String) -> String { metadata[key]?["value"] as? String ?? "" }
            let artist = value("Artist").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return ["title": String(title.dropFirst(5)), "url": media, "source": source,
                    "thumbnail": info["thumburl"] as? String ?? "", "kind": kind,
                    "license": value("LicenseShortName"), "licenseURL": value("LicenseUrl"), "artist": artist]
        }
    }

    static func download(_ raw: String, kind: String, root: URL) async throws -> [String: Any] {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "upload.wikimedia.org",
              ["image", "video"].contains(kind) else { throw error("Đường dẫn tệp Wikimedia không hợp lệ.") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("SuStudio/0.13 (https://github.com/hieupnvmg/su-studio)", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == "upload.wikimedia.org",
              (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 250_000_000 else {
            throw error("Không tải được tệp tư liệu hoặc tệp vượt 250 MB.")
        }
        let fm = FileManager.default
        let folder = root.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let safeExtension = ext.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil ? ext : "media"
        let original = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(safeExtension)
        try fm.copyItem(at: temporary, to: original)
        do {
            if kind == "image", CGImageSourceCreateWithURL(original as CFURL, nil) == nil {
                throw error("Định dạng ảnh này không đọc được trên máy.")
            }
            let source = AVURLAsset(url: original)
            if kind == "video", !source.tracks(withMediaType: .video).isEmpty,
               source.duration.seconds.isFinite, source.duration.seconds > 0 {
                return ["path": original.path, "originalPath": original.path, "duration": source.duration.seconds]
            }
            let output = folder.appendingPathComponent(UUID().uuidString + "-archive.mp4")
            do {
                try convert(original, to: output, still: kind == "image")
                let clip = AVURLAsset(url: output)
                guard !clip.tracks(withMediaType: .video).isEmpty, clip.duration.seconds.isFinite,
                      clip.duration.seconds > 0 else { throw error("Clip tư liệu sau chuyển đổi không đọc được.") }
                return ["path": output.path, "originalPath": original.path, "duration": clip.duration.seconds]
            } catch {
                try? fm.removeItem(at: output)
                throw error
            }
        } catch {
            try? fm.removeItem(at: original)
            throw error
        }
    }

    static func convert(_ source: URL, to output: URL, still: Bool) throws {
        guard let executable = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw error("Máy cần FFmpeg để đưa ảnh hoặc video WebM vào timeline.")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["-nostdin", "-v", "error"] + (still ? ["-loop", "1", "-framerate", "30"] : [])
        task.arguments! += ["-i", source.path, "-map", "0:v:0"]
        task.arguments! += still ? ["-t", "1", "-an"] : ["-map", "0:a:0?", "-c:a", "aac"]
        task.arguments! += ["-vf", "scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1",
                            "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", output.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw error("FFmpeg không chuyển được tệp tư liệu sang MP4.") }
    }
}
