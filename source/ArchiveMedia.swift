import Foundation
import AVFoundation
import ImageIO

enum ArchiveMedia {
    static func error(_ message: String) -> NSError {
        NSError(domain: "ArchiveMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private struct SearchSubject {
        let names: [String]
        let isPerson: Bool
    }

    static func search(_ query: String, kind: String) async throws -> [[String: Any]] {
        try await searchCommons(subject(for: query), kind: kind)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    private static func subject(for query: String) async -> SearchSubject {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.replacingOccurrences(
            of: #"^(?:(?:nhà\s+)?vua|(?:nha\s+)?vua|hoàng đế|hoang de|quốc vương|quoc vuong|king|emperor)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        let fallback = SearchSubject(names: [name], isPerson: name != trimmed)
        let key = normalized(name)
        guard key.split(separator: " ").count >= 2,
              let listing = try? await wikidata([
                "action": "wbsearchentities", "search": name, "language": "vi", "uselang": "vi", "limit": "8"
              ]) else { return fallback }
        let candidates = (listing["search"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            let match = (item["match"] as? [String: Any])?["text"] as? String ?? ""
            let label = item["label"] as? String ?? ""
            return [match, label].contains { normalized($0) == key } ? item["id"] as? String : nil
        }
        guard !candidates.isEmpty,
              let records = try? await wikidata([
                "action": "wbgetentities", "ids": candidates.joined(separator: "|"),
                "props": "labels|aliases|claims", "languages": "vi|en"
              ]) else { return fallback }
        let entities = records["entities"] as? [String: [String: Any]] ?? [:]
        let people = entities.values.filter { entity in
            let claims = entity["claims"] as? [String: [[String: Any]]] ?? [:]
            return claims["P31", default: []].contains { claim in
                let snak = claim["mainsnak"] as? [String: Any]
                let data = snak?["datavalue"] as? [String: Any]
                return (data?["value"] as? [String: Any])?["id"] as? String == "Q5"
            }
        }
        guard people.count == 1, let person = people.first else { return fallback }
        let labels = person["labels"] as? [String: [String: String]] ?? [:]
        let aliases = person["aliases"] as? [String: [[String: String]]] ?? [:]
        let alternatives = [labels["vi"]?["value"]].compactMap { $0 }
            + aliases["vi", default: []].compactMap { $0["value"] }
            + [labels["en"]?["value"]].compactMap { $0 }
        var seen = Set<String>()
        let names = (alternatives.filter { normalized($0) == key } + [name] + alternatives)
            .filter { normalized($0).split(separator: " ").count >= 2 && seen.insert(normalized($0)).inserted }
        return SearchSubject(names: Array(names.prefix(3)), isPerson: true)
    }

    private static func wikidata(_ parameters: [String: String]) async throws -> [String: Any] {
        try await json("https://www.wikidata.org/w/api.php", parameters: (parameters.merging(["format": "json"]) { old, _ in old })
            .map { URLQueryItem(name: $0.key, value: $0.value) }, timeout: 4)
    }

    private static func relevant(_ item: [String: Any], to subject: SearchSubject, includeCategoryMatches: Bool = true) -> Bool {
        guard subject.isPerson else { return true }
        let title = normalized(item["title"] as? String ?? "")
        let context = (item["searchContext"] as? String ?? "").split(separator: "|").map { normalized(String($0)) }
        let description = normalized(item["searchDescription"] as? String ?? "")
        if context.contains(where: { $0.hasPrefix("streets in ") || $0.hasPrefix("roads in ") }) {
            return false
        }
        let names = subject.names.map(normalized).filter { !$0.isEmpty }
        let location = #"\b(?:duong(?: pho)?|pho|ngo|dai lo|nga tu|nga ba|giao lo|street|road|avenue|boulevard)\b"#
        for name in names {
            let key = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
            let namedLocation = location + " " + key + "|" + key + " " + location
            if ([title] + context).contains(where: { $0.range(of: namedLocation, options: .regularExpression) != nil }) {
                return false
            }
            // Some street photos list only the name followed by a street address.
            if title.range(of: key + #" (?:(?:phuong|quan|ward|district|p)\s*\d+\b|(?:tp|thanh pho|city of) )"#,
                           options: .regularExpression) != nil { return false }
        }
        return names.contains { name in
            let phrase = " " + name + " "
            let matchesCaption = (" " + description + " ").contains(phrase)
                && title.contains(name.replacingOccurrences(of: " ", with: ""))
            return (" " + title + " ").contains(phrase) || matchesCaption
                || (includeCategoryMatches && context.contains { (" " + $0 + " ").contains(phrase) })
        }
    }

    private static func searchCommons(_ subject: SearchSubject, kind: String) async throws -> [[String: Any]] {
        var queries = subject.names
        if subject.isPerson {
            // Commons can index captions or filenames under the unaccented spelling only.
            queries += subject.names.map { "\"\(normalized($0))\"" }
        }
        let batches = await withTaskGroup(of: (Int, [[String: Any]]?).self) { group in
            for (index, name) in queries.enumerated() {
                group.addTask { (index, try? await searchFiles(name, kind: kind)) }
            }
            var batches: [(Int, [[String: Any]])] = []
            for await (index, items) in group {
                if let items { batches.append((index, items)) }
            }
            return batches
        }
        guard !batches.isEmpty else { throw error("Không tìm được tư liệu từ Wikimedia Commons. Thử lại sau.") }
        var seen = Set<String>()
        return batches.sorted { $0.0 < $1.0 }.flatMap { index, items in
            items.filter { item in
                guard let url = item["url"] as? String else { return false }
                return relevant(item, to: subject, includeCategoryMatches: index < subject.names.count)
                    && seen.insert(url).inserted
            }
        }
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
                    "searchContext": value("Categories"),
                    "searchDescription": value("ImageDescription").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression),
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
        let subject = await subject(for: query)
        let name = subject.names[0]
        let archive = kind == "video" ? "Prelinger Archives" : "The Met"
        async let commonsResult = searchProvider("Wikimedia Commons") {
            try await searchCommons(subject, kind: kind)
        }
        async let archiveResult = searchProvider(archive) {
            if kind == "video" { return try await searchPrelinger(name) }
            return try await searchMet(name)
        }
        let results = await [archiveResult, commonsResult]
        let items = results.flatMap { $0.items }
        let matching = items.filter { relevant($0, to: subject) }.map { item in
            item.filter { $0.key != "searchContext" && $0.key != "searchDescription" }
        }
        return ["items": matching, "warnings": results.compactMap { $0.warning }]
    }

    private static func searchProvider(
        _ name: String, load: () async throws -> [[String: Any]]
    ) async -> (items: [[String: Any]], warning: String?) {
        do { return (try await load(), nil) }
        catch { return ([], "Chưa kết nối được với " + name + ".") }
    }

    private static func json(_ endpoint: String, parameters: [URLQueryItem] = [], timeout: TimeInterval = 12) async throws -> [String: Any] {
        var url = URLComponents(string: endpoint)!
        if !parameters.isEmpty { url.queryItems = parameters }
        var request = URLRequest(url: url.url!, timeoutInterval: timeout)
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

    // Only fetch from publishers and media hosts supported by the native importer.
    private static func allowedWebURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        let domains = ["vov.vn", "vovmedia.vn", "tuoitre.vn", "tuoitre.com.vn", "vtv.vn", "vtvcdn.net",
                       "vietnamnet.vn", "vnncdn.net", "baochinhphu.vn", "mediacdn.vn", "sggp.org.vn",
                       "nhandan.vn", "vnanet.vn",
                       "time.com", "wikimedia.org", "vnexpress.net", "qdnd.vn"]
        return allowedMediaURL(url) || domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private final class WebRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.map(ArchiveMedia.allowedWebURL) == true ? request : nil)
        }
    }

    static func detectWebFiles(_ items: [[String: String]], kind: String) async -> [[String: String]] {
        await withTaskGroup(of: (Int, [String: String]).self) { group in
            for (index, item) in items.prefix(24).enumerated() {
                group.addTask {
                    var result = item
                    var direct = await webMedia(item["mediaURL"] ?? "", kind: kind)
                    if direct == nil, kind == "image", let preview = item["thumbnail"], preview != item["mediaURL"] {
                        direct = await webMedia(preview, kind: kind)
                    }
                    if direct == nil, let source = item["source"] {
                        direct = await pageMedia(source, kind: kind)
                        if let direct, kind == "image" {
                            result["thumbnail"] = direct
                            result["note"] = [item["note"], "Tệp phát hiện là ảnh đại diện của trang nguồn."].compactMap { $0 }.joined(separator: " ")
                        }
                    }
                    result["mediaURL"] = direct ?? ""
                    return (index, result)
                }
            }
            var checked: [(Int, [String: String])] = []
            for await item in group { checked.append(item) }
            return checked.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private static func pageMedia(_ raw: String, kind: String) async -> String? {
        guard let url = URL(string: raw), allowedWebURL(url) else { return nil }
        let session = URLSession(configuration: .ephemeral, delegate: WebRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: url, timeoutInterval: 8)
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType == "text/html", let page = http.url else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 128 * 1024 { break }
            }
        } catch { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let tags = try! NSRegularExpression(pattern: #"<meta\s[^>]*>"#, options: .caseInsensitive)
        let attrs = try! NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*["']([^"']*)["']"#)
        let properties = kind == "image" ? ["og:image", "og:image:secure_url"] : ["og:video", "og:video:url", "og:video:secure_url"]
        for tagMatch in tags.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(tagMatch.range, in: html) else { continue }
            let tag = String(html[range])
            var fields: [String: String] = [:]
            for match in attrs.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let key = Range(match.range(at: 1), in: tag), let value = Range(match.range(at: 2), in: tag) else { continue }
                fields[String(tag[key]).lowercased()] = String(tag[value])
            }
            guard properties.contains(fields["property"] ?? fields["name"] ?? ""),
                  let content = fields["content"],
                  let file = URL(string: content.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL else { continue }
            if let verified = await webMedia(file.absoluteString, kind: kind) { return verified }
        }
        return nil
    }

    static func webMedia(_ raw: String, kind: String) async -> String? {
        guard let url = URL(string: raw), allowedWebURL(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral, delegate: WebRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.expectedContentLength <= 250_000_000,
              let mime = http.mimeType?.lowercased(), supportedWebMIME(mime, kind: kind) else { return nil }
        return url.absoluteString
    }

    private static func supportedWebMIME(_ mime: String, kind: String) -> Bool {
        if kind == "image" { return ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif", "image/tiff"].contains(mime) }
        return ["video/mp4", "video/quicktime", "video/webm", "video/ogg", "video/x-m4v"].contains(mime)
    }

    static func download(_ raw: String, kind: String, root: URL, web: Bool = false) async throws -> [String: Any] {
        let allowed = web ? allowedWebURL : allowedMediaURL
        guard let url = URL(string: raw), allowed(url),
              ["image", "video"].contains(kind) else { throw error("Đường dẫn tệp ngoài các nguồn được hỗ trợ.") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("SuStudio/0.14 (https://github.com/hieupnvmg/su-studio)", forHTTPHeaderField: "User-Agent")
        let session = web ? URLSession(configuration: .ephemeral, delegate: WebRedirects(), delegateQueue: nil) : .shared
        defer { if web { session.finishTasksAndInvalidate() } }
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url.map(allowed) == true,
              !web || supportedWebMIME(http.mimeType ?? "", kind: kind),
              (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 250_000_000 else {
            throw error("Không tải được tệp tư liệu hoặc tệp vượt 250 MB.")
        }
        return try importFile(temporary, kind: kind, root: root, fileExtension: http.url?.pathExtension ?? url.pathExtension)
    }

    static func importFile(_ file: URL, kind: String, root: URL, fileExtension: String? = nil) throws -> [String: Any] {
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 250_000_000 else {
            throw error("Tệp tư liệu vượt 250 MB.")
        }
        let fm = FileManager.default
        let folder = root.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = (fileExtension ?? file.pathExtension).lowercased()
        let safeExtension = ext.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil ? ext : "media"
        let original = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(safeExtension)
        try fm.copyItem(at: file, to: original)
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
