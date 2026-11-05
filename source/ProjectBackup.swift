import Foundation

/// Backup archives: a plain .zip holding manifest.json, projects.json and assets/<file> for every
/// media file the saved projects reference. Asset paths in projects are absolute, so restoring
/// rewrites the backup machine's assets folder to this machine's.
enum ProjectBackup {
    static let format = 1
    static let appName = "Sử Studio"
    struct Staged {
        let folder: URL
        let manifest: [String: Any]
        let state: [String: Any]
        let files: [String]
        let bytes: Int64
    }
    static func issue(_ message: String) -> NSError { NSError(domain: "ProjectBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    /// Every string in the state that names a file directly inside `assets`.
    static func referencedAssets(_ value: Any, assets: URL) -> Set<String> {
        let prefix = assets.path + "/"
        var found = Set<String>()
        func walk(_ v: Any) {
            if let s = v as? String { if s.hasPrefix(prefix) { let name = String(s.dropFirst(prefix.count)); if safeName(name) { found.insert(name) } } }
            else if let a = v as? [Any] { a.forEach(walk) }
            else if let d = v as? [String: Any] { d.values.forEach(walk) }
        }
        walk(value)
        return found
    }
    static func safeName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") && name != "." && name != ".." && !name.hasPrefix(".") && name.count <= 255 }
    static func rewrite(_ value: Any, from old: String, to new: String) -> Any {
        if let s = value as? String { return s.hasPrefix(old) ? new + s.dropFirst(old.count) : s }
        if let a = value as? [Any] { return a.map { rewrite($0, from: old, to: new) } }
        if let d = value as? [String: Any] { return d.mapValues { rewrite($0, from: old, to: new) } }
        return value
    }
    static func run(_ tool: String, _ args: [String]) throws -> Data {
        let task = Process(); task.executableURL = URL(fileURLWithPath: tool); task.arguments = args
        let out = Pipe(); task.standardOutput = out; task.standardError = FileHandle.nullDevice
        try task.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw issue("Không xử lý được file nén (\(URL(fileURLWithPath: tool).lastPathComponent) lỗi \(task.terminationStatus)).") }
        return data
    }

    @discardableResult
    static func create(state: [String: Any], assets: URL, appVersion: String, to destination: URL) throws -> (projects: Int, files: Int, bytes: Int64) {
        guard let projects = state["projects"] as? [[String: Any]], !projects.isEmpty else { throw issue("Chưa có dự án để sao lưu.") }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("su-studio-backup-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let folder = temp.appendingPathComponent("content", isDirectory: true), media = folder.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        var files = 0, bytes: Int64 = 0
        for name in referencedAssets(state, assets: assets).sorted() {
            let source = assets.appendingPathComponent(name)
            guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            try fm.copyItem(at: source, to: media.appendingPathComponent(name))
            files += 1; bytes += Int64(values.fileSize ?? 0)
        }
        let manifest: [String: Any] = ["app": appName, "format": format, "version": appVersion, "created": ISO8601DateFormatter().string(from: Date()),
                                       "assetsRoot": assets.path, "projects": projects.count, "files": files]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("manifest.json"))
        try JSONSerialization.data(withJSONObject: state).write(to: folder.appendingPathComponent("projects.json"))
        let zip = temp.appendingPathComponent("backup.zip")
        _ = try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", folder.path, zip.path])
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: zip, to: destination)
        return (projects.count, files, bytes)
    }

    /// Unpacks and validates a backup without touching the user's data.
    static func read(_ archive: URL, assets: URL) throws -> Staged {
        let fm = FileManager.default
        // Refuse archives whose entries could land outside the extraction folder.
        let listing = String(decoding: try run("/usr/bin/zipinfo", ["-1", archive.path]), as: UTF8.self)
        let entries = listing.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else { throw issue("File này không phải bản sao lưu Sử Studio hợp lệ.") }
        let folder = fm.temporaryDirectory.appendingPathComponent("su-studio-restore-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
            guard let manifestData = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any],
                  manifest["app"] as? String == appName, let version = manifest["format"] as? Int else { throw issue("File này không phải bản sao lưu Sử Studio.") }
            guard version <= format else { throw issue("Bản sao lưu được tạo bởi phiên bản Sử Studio mới hơn. Cập nhật app rồi khôi phục lại.") }
            guard let stateData = try? Data(contentsOf: folder.appendingPathComponent("projects.json")),
                  var state = (try? JSONSerialization.jsonObject(with: stateData)) as? [String: Any],
                  let projects = state["projects"] as? [[String: Any]], !projects.isEmpty,
                  projects.allSatisfy({ ($0["id"] as? String)?.isEmpty == false && $0["scenes"] is [Any] }) else { throw issue("Bản sao lưu bị thiếu hoặc hỏng dữ liệu dự án.") }
            let media = folder.appendingPathComponent("assets", isDirectory: true)
            var files: [String] = [], bytes: Int64 = 0
            for url in (try? fm.contentsOfDirectory(at: media, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? [] {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, safeName(url.lastPathComponent) else { continue }
                files.append(url.lastPathComponent); bytes += Int64(values.fileSize ?? 0)
            }
            if let old = manifest["assetsRoot"] as? String, !old.isEmpty, old != assets.path {
                state = rewrite(state, from: old + "/", to: assets.path + "/") as? [String: Any] ?? state
            }
            return Staged(folder: folder, manifest: manifest, state: state, files: files.sorted(), bytes: bytes)
        } catch { try? fm.removeItem(at: folder); throw error }
    }

    /// Copies the backup's media into this machine's assets folder. Existing files are kept:
    /// asset names start with a UUID, so the same name is the same file.
    @discardableResult
    static func apply(_ staged: Staged, assets: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        var copied = 0
        for name in staged.files {
            let target = assets.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            try fm.copyItem(at: staged.folder.appendingPathComponent("assets").appendingPathComponent(name), to: target)
            copied += 1
        }
        return copied
    }
    static func discard(_ staged: Staged?) { if let staged { try? FileManager.default.removeItem(at: staged.folder) } }
}
