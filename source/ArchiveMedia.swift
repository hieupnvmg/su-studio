import Foundation
import AVFoundation
import ImageIO

enum ArchiveMedia {
    static func error(_ message: String) -> NSError {
        NSError(domain: "ArchiveMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func search(_ query: String, kind: String) async throws -> [[String: Any]] {
        let name = searchName(query)
        if isMaiHacDe(name) {
            async let royalName = searchFiles("Mai Hắc Đế", kind: kind)
            async let birthName = searchFiles("Mai Thúc Loan", kind: kind)
            let results = try await royalName + birthName
            var seen = Set<String>()
            return results.filter {
                let title = $0["title"] as? String ?? ""
                guard let url = $0["url"] as? String else { return false }
                return matchesMaiHacDe(title) && seen.insert(url).inserted
            }
        }
        return try await searchFiles(name, kind: kind)
    }

    private static func searchName(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.replacingOccurrences(
            of: #"^(?:nhà\s+vua|nha\s+vua|vua|hoàng đế|quốc vương|king|emperor)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return name.isEmpty ? trimmed : name
    }

    private static func isMaiHacDe(_ name: String) -> Bool {
        ["mai hắc đế", "mai thúc loan", "mai hac de", "mai thuc loan"].contains(name.lowercased())
    }

    private static func matchesMaiHacDe(_ title: String) -> Bool {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
        guard normalized.contains("mai hac de") || normalized.contains("mai thuc loan") else { return false }
        return !isStreet(title)
    }

    private static func isStreet(_ title: String) -> Bool {
        title.range(of: #"\b(?:đường|phố|street|road|avenue|mể cốc|thái phiên)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func searchFiles(_ query: String, kind: String) async throws -> [[String: Any]] {
        var url = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        let type = kind == "video" ? "video" : "bitmap"
        let parameters = [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "search", "gsrnamespace": "6", "gsrlimit": "12",
            "gsrsearch": "\(query) filetype:\(type)", "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata", "iiurlwidth": "320",
            "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl|Categories|ImageDescription|DateTimeOriginal"
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
            let synthetic = markedSynthetic([title, value("Categories"), value("ImageDescription")].joined(separator: " "))
            return ["title": String(title.dropFirst(5)), "url": media, "source": source,
                    "provider": "Wikimedia Commons", "catalogued": false, "recordDate": value("DateTimeOriginal"),
                    "recordType": synthetic ? "Hồ sơ có nhãn AI hoặc phục dựng" : "Tệp cộng đồng · cần đối chiếu",
                    "thumbnail": info["thumburl"] as? String ?? "", "kind": kind,
                    "license": value("LicenseShortName"), "licenseURL": value("LicenseUrl"), "artist": artist]
        }
    }

    private static func markedSynthetic(_ value: String) -> Bool {
        value.range(of: #"\b(?:ai[- ]generated|generated by ai|generative ai|midjourney|stable diffusion|dall[- ·]e|reenactment|re-enactment|reconstruction|phục dựng|tái dựng)\b"#,
                    options: [.caseInsensitive, .regularExpression]) != nil
    }

    static func searchAll(_ query: String, kind: String) async -> [String: Any] {
        let name = searchName(query)
        let archive = kind == "video" ? "Prelinger Archives" : "The Met"
        async let commonsResult = searchProvider("Wikimedia Commons") {
            try await search(query, kind: kind)
        }
        async let archiveResult = searchProvider(archive) {
            if kind == "video" { return try await searchPrelinger(name) }
            return try await searchMet(name)
        }
        let results = await [archiveResult, commonsResult]
        let items = results.flatMap { $0.items }
        let relevant = isMaiHacDe(name) ? items.filter { matchesMaiHacDe($0["title"] as? String ?? "") } : items
        return ["items": relevant, "warnings": results.compactMap { $0.warning }]
    }

    private static func searchProvider(
        _ name: String, load: () async throws -> [[String: Any]]
    ) async -> (items: [[String: Any]], warning: String?) {
        do { return (try await load(), nil) }
        catch { return ([], "Chưa kết nối được với " + name + ".") }
    }

    private static func json(_ endpoint: String, parameters: [URLQueryItem] = []) async throws -> [String: Any] {
        var url = URLComponents(string: endpoint)!
        if !parameters.isEmpty { url.queryItems = parameters }
        var request = URLRequest(url: url.url!, timeoutInterval: 12)
        request.setValue("SuStudio/0.14 (https://github.com/hieupnvmg/su-studio)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw error("Không đọc được hồ sơ từ kho tư liệu.")
        }
        return value
    }

    private static func searchMet(_ query: String) async throws -> [[String: Any]] {
        let base = "https://collectionapi.metmuseum.org/public/collection/"
        let listing = try await json(base + "v1.1/search", parameters: [
            .init(name: "q", value: query), .init(name: "hasImages", value: "true"), .init(name: "limit", value: "12")
        ])
        let ids = Array((listing["objectIDs"] as? [Int] ?? []).prefix(12))
        let records = await withTaskGroup(of: (Int, [String: Any]?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try? await json(base + "v1/objects/" + String(id))) }
            }
            var loaded: [(Int, [String: Any]?)] = []
            for await record in group { loaded.append(record) }
            return loaded.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }
        if !ids.isEmpty && records.isEmpty { throw error("Không đọc được hồ sơ The Met.") }
        var results: [[String: Any]] = []
        for record in records {
            guard let title = record["title"] as? String,
                  let source = record["objectURL"] as? String else { continue }
            let open = record["isPublicDomain"] as? Bool == true
            let media = open ? record["primaryImage"] as? String ?? "" : ""
            let date = record["objectDate"] as? String ?? ""
            let classification = record["classification"] as? String ?? ""
            let label = classification.localizedCaseInsensitiveContains("photograph") ? "Ảnh trong bộ sưu tập" : "Ảnh số hóa hiện vật"
            results.append(["title": title, "url": media, "source": source, "kind": "image",
                "thumbnail": open ? record["primaryImageSmall"] as? String ?? "" : "", "provider": "The Met",
                "recordDate": date, "recordType": label, "catalogued": !date.isEmpty,
                "license": open ? "CC0 (The Met Open Access)" : "",
                "licenseURL": open ? "https://creativecommons.org/publicdomain/zero/1.0/" : "",
                "artist": record["artistDisplayName"] as? String ?? ""])
        }
        return results
    }

    private static func searchPrelinger(_ query: String) async throws -> [[String: Any]] {
        let words = query.split { !$0.isLetter && !$0.isNumber }.prefix(12)
        guard !words.isEmpty else { return [] }
        let terms = words.map { "text:\"\($0)\"" }.joined(separator: " AND ")
        let listing = try await json("https://archive.org/advancedsearch.php", parameters: [
            .init(name: "q", value: "collection:prelinger AND mediatype:movies AND " + terms),
            .init(name: "rows", value: "6"), .init(name: "output", value: "json")
        ] + ["identifier", "title", "date", "creator", "licenseurl"].map { .init(name: "fl[]", value: $0) })
        let docs = (listing["response"] as? [String: Any])?["docs"] as? [[String: Any]] ?? []
        var results: [[String: Any]] = []
        for doc in docs {
            guard let id = doc["identifier"] as? String,
                  id.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil, id != ".", id != "..",
                  let title = doc["title"] as? String else { continue }
            let date = String((doc["date"] as? String ?? "").prefix(10))
            let rights = doc["licenseurl"] as? String ?? ""
            let licenseURL = URL(string: rights)
            let license = licenseURL?.host == "creativecommons.org" ? rights : ""
            var media = ""
            if !license.isEmpty,
               let record = try? await json("https://archive.org/metadata/" + id),
               let files = record["files"] as? [[String: Any]] {
                let candidates = files.compactMap { file -> (String, Int)? in
                    guard let name = file["name"] as? String, name.lowercased().hasSuffix(".mp4"),
                          !name.contains("/"), file["private"] as? String != "true",
                          let bytes = Int(file["size"] as? String ?? ""), bytes > 0, bytes <= 250_000_000 else { return nil }
                    return (name, bytes)
                }
                if let file = candidates.min(by: { $0.1 < $1.1 }) {
                    media = URL(string: "https://archive.org/download/")!.appendingPathComponent(id)
                        .appendingPathComponent(file.0).absoluteString
                }
            }
            results.append(["title": title, "url": media, "source": "https://archive.org/details/" + id,
                "kind": "video", "thumbnail": "https://archive.org/services/img/" + id,
                "provider": "Prelinger Archives", "recordDate": date, "recordType": "Phim trong bộ sưu tập",
                "catalogued": !date.isEmpty && !markedSynthetic(title), "license": license, "licenseURL": rights,
                "artist": doc["creator"] as? String ?? (doc["creator"] as? [String] ?? []).joined(separator: ", ")])
        }
        return results
    }

    private static func allowedMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        if ["upload.wikimedia.org", "images.metmuseum.org", "archive.org"].contains(host) { return true }
        return host.range(of: #"^(?:ia|dn)[0-9]+(?:\.[a-z]+)?\.archive\.org$"#, options: .regularExpression) != nil
    }

    static func download(_ raw: String, kind: String, root: URL) async throws -> [String: Any] {
        guard let url = URL(string: raw), allowedMediaURL(url),
              ["image", "video"].contains(kind) else { throw error("Đường dẫn tệp ngoài các kho được hỗ trợ.") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("SuStudio/0.13 (https://github.com/hieupnvmg/su-studio)", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url.map(allowedMediaURL) == true,
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
