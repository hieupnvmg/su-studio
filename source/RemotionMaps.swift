import Foundation
import CryptoKit

/// Map scenes rendered with Remotion (React + headless Chrome) in a private workspace under
/// Application Support/HistoryStudio/remotion: a portable Node.js, the bundled map project and its packages.
/// Nothing is installed system-wide and no admin rights are needed.
final class RemotionMaps {
    static let nodeVersion = "v24.22.2"
    /// SHA-256 of the official Node.js archives for `nodeVersion` (from nodejs.org SHASUMS256.txt).
    static let nodeChecksums = ["arm64": "aa9549349e47dffaa42dcf95d6e06ade8c4bdafc980979883b88767670df385a",
                                "x64": "d5e336d588c45be0c37dbd52cc29895593009ca4997a77a1fd02815131ed0e52"]
    static let minimumNodeMajor = 18

    let root: URL
    let template: URL?
    var onUpdate: (([String: Any]) -> Void)?
    private var process: Process?
    private var download: URLSessionDownloadTask?
    private(set) var busy = false
    private var cancelled = false

    init(root: URL, template: URL? = Bundle.main.resourceURL?.appendingPathComponent("remotion-map", isDirectory: true)) {
        self.root = root; self.template = template
    }
    var runtime: URL { root.appendingPathComponent("remotion", isDirectory: true) }
    var portableNode: URL { runtime.appendingPathComponent("node/bin/node") }
    var project: URL { runtime.appendingPathComponent("map-project", isDirectory: true) }
    static func error(_ message: String) -> NSError { NSError(domain: "RemotionMaps", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static var arch: String {
        var info = utsname(); uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.hasPrefix("arm") ? "arm64" : "x64"
    }

    // MARK: Status

    /// The Node.js to use: the portable copy first, then a system install (apps do not see the shell PATH).
    func node() -> (url: URL, version: String, portable: Bool)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [portableNode.path, "/opt/homebrew/bin/node", "/usr/local/bin/node", home + "/.local/bin/node", home + "/.volta/bin/node"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            guard let version = try? Self.capture(URL(fileURLWithPath: path), ["-v"]).trimmingCharacters(in: .whitespacesAndNewlines),
                  let major = Int(version.dropFirst().split(separator: ".").first ?? ""), major >= Self.minimumNodeMajor else { continue }
            return (URL(fileURLWithPath: path), version, path == portableNode.path)
        }
        return nil
    }
    static func capture(_ executable: URL, _ arguments: [String]) throws -> String {
        let task = Process(), pipe = Pipe()
        task.executableURL = executable; task.arguments = arguments; task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try task.run(); task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    /// Versions pinned in the bundled template's package.json.
    func pinned() -> [String: String] {
        guard let template = template, let data = try? Data(contentsOf: template.appendingPathComponent("package.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return json["dependencies"] as? [String: String] ?? [:]
    }
    func packagesReady() -> Bool {
        let pins = pinned()
        guard !pins.isEmpty else { return false }
        return pins.allSatisfy { name, version in
            guard let data = try? Data(contentsOf: project.appendingPathComponent("node_modules/\(name)/package.json")),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            return json["version"] as? String == version
        }
    }
    func browserReady() -> Bool {
        let folder = project.appendingPathComponent("node_modules/.remotion/chrome-headless-shell", isDirectory: true)
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return false }
        return items.contains { ($0 as? URL)?.lastPathComponent == "chrome-headless-shell" }
    }
    func status() -> [String: Any] {
        let found = node(), packages = found != nil && packagesReady(), browser = packages && browserReady()
        return ["status": "status", "busy": busy,
                "node": ["ok": found != nil, "version": found?.version ?? "", "portable": found?.portable ?? false],
                "packages": ["ok": packages, "version": pinned()["remotion"] ?? ""],
                "browser": ["ok": browser], "ready": found != nil && packages && browser]
    }

    // MARK: Install

    func installNode() {
        guard begin() else { return }
        let arch = Self.arch, name = "node-\(Self.nodeVersion)-darwin-\(arch)"
        guard let expected = Self.nodeChecksums[arch], let url = URL(string: "https://nodejs.org/dist/\(Self.nodeVersion)/\(name).tar.gz") else { return finish(error: "Máy này chưa có bản Node.js phù hợp.") }
        update("node", 0, "Đang tải Node.js \(Self.nodeVersion)…")
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: url) { [weak self] file, response, error in
            guard let self = self else { return }
            do {
                guard error == nil, let file = file, (response as? HTTPURLResponse)?.statusCode == 200 else { throw Self.error(self.cancelled ? "Đã dừng tải Node.js." : "Không tải được Node.js. Kiểm tra mạng rồi thử lại.") }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw Self.error("File Node.js tải về không khớp mã kiểm tra SHA-256; đã bỏ.") }
                let staging = self.runtime.appendingPathComponent("node-staging", isDirectory: true), fm = FileManager.default
                try? fm.removeItem(at: staging); try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                let tar = Process(); tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar"); tar.arguments = ["-xzf", file.path, "-C", staging.path]
                try tar.run(); tar.waitUntilExit()
                guard tar.terminationStatus == 0 else { throw Self.error("Không giải nén được Node.js.") }
                let target = self.runtime.appendingPathComponent("node", isDirectory: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: staging.appendingPathComponent(name), to: target)
                try? fm.removeItem(at: staging)
                guard self.node()?.portable == true else { throw Self.error("Đã giải nén nhưng chưa chạy được Node.js.") }
                DispatchQueue.main.async { self.finish(message: "Đã cài Node.js \(Self.nodeVersion) trong thư mục của Sử Studio.") }
            } catch { DispatchQueue.main.async { self.finish(error: error.localizedDescription) } }
        }
        observe(task, phase: "node", label: "Đang tải Node.js")
        download = task; task.resume()
    }

    /// Copies the bundled map project (sources, scripts, package.json) into the workspace; node_modules stays.
    func syncProject() throws {
        guard let template = template, FileManager.default.fileExists(atPath: template.path) else { throw Self.error("Bản app thiếu dự án mẫu Remotion.") }
        let fm = FileManager.default
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        for name in ["package.json", "render.mjs", "ensure.mjs", "src"] {
            let target = project.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: template.appendingPathComponent(name), to: target)
        }
    }

    /// npm install with the pinned versions, then the headless Chrome Remotion renders with.
    func installPackages() {
        guard let node = node() else { return update("error", 0, "Cài Node.js trước.") }
        guard begin() else { return }
        do { try syncProject() } catch { return finish(error: error.localizedDescription) }
        let npm = node.url.deletingLastPathComponent().appendingPathComponent("npm")
        guard FileManager.default.isExecutableFile(atPath: npm.path) else { return finish(error: "Không tìm thấy npm bên cạnh Node.js. Cài Node.js của Sử Studio rồi thử lại.") }
        update("packages", 0, "Đang tải các gói Remotion (khoảng 300 MB)…")
        run(npm, ["install", "--no-audit", "--no-fund", "--loglevel=error"], node: node.url) { [weak self] ok, tail in
            guard let self = self else { return }
            guard ok else { return self.finish(error: "npm install chưa xong. " + tail) }
            self.update("browser", 0, "Đang tải trình duyệt render (khoảng 150 MB)…")
            self.run(node.url, ["ensure.mjs"], node: node.url) { ok, tail in
                ok ? self.finish(message: "Remotion đã sẵn sàng.") : self.finish(error: "Chưa tải được trình duyệt render. " + tail)
            }
        }
    }

    // MARK: Render

    /// Renders a validated map scene to `output` (MP4) or a single preview frame (PNG).
    func render(props: [String: Any], output: URL, still: Bool, frame: Int = 0, completion: @escaping (Error?) -> Void) {
        guard let node = node(), packagesReady(), browserReady() else { return completion(Self.error("Remotion chưa cài xong. Mở Cài đặt & kết nối → Remotion.")) }
        guard begin(notify: false) else { return completion(Self.error("Remotion đang chạy việc khác. Đợi xong hoặc dừng trước.")) }
        do {
            try syncProject()
            let file = runtime.appendingPathComponent("props-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: props).write(to: file)
            update(still ? "still" : "render", 0, still ? "Đang dựng khung xem trước…" : "Đang dựng cảnh bản đồ…")
            run(node.url, ["render.mjs", still ? "still" : "video", file.path, output.path, String(frame)], node: node.url) { [weak self] ok, tail in
                try? FileManager.default.removeItem(at: file)
                self?.busy = false; self?.process = nil
                completion(ok && FileManager.default.fileExists(atPath: output.path) ? nil : Self.error(self?.cancelled == true ? "Đã dừng dựng cảnh bản đồ." : "Chưa dựng được cảnh bản đồ. " + tail))
            }
        } catch { busy = false; completion(error) }
    }

    func cancel() {
        cancelled = true
        download?.cancel()
        process?.terminate()
    }

    // MARK: Map plan

    static let palette = ["#c0392b", "#2c5aa0", "#2e7d32", "#8e44ad"]
    /// A map plan (from the AI or edited by hand) reduced to safe, bounded props for the MapScene composition.
    /// Returns nil when there is no usable camera view.
    static func sanitize(_ plan: [String: Any], aspect: String, seconds: Double) -> [String: Any]? {
        func number(_ v: Any?) -> Double? { (v as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
        func point(_ v: Any?) -> [Double]? {
            guard let a = v as? [Any], a.count == 2, let lon = number(a[0]), let lat = number(a[1]), abs(lon) <= 180, abs(lat) <= 85 else { return nil }
            return [lon, lat]
        }
        func view(_ v: Any?) -> [String: Any]? {
            // Out-of-range zoom (e.g. 1.4 for a voyage across continents) is clamped, not rejected.
            guard let d = v as? [String: Any], let center = point(d["center"]), let zoom = number(d["zoom"]) else { return nil }
            return ["center": center, "zoom": min(14, max(1, zoom))]
        }
        func text(_ v: Any?, _ limit: Int) -> String { String((v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)) }
        func time(_ v: Any?) -> Double { min(seconds, max(0, number(v) ?? 0)) }
        guard seconds.isFinite, (2...60).contains(seconds), let start = view(plan["start"]) else { return nil }
        var end = view(plan["end"]) ?? start
        if abs((end["zoom"] as! Double) - (start["zoom"] as! Double)) > 4 { end = start }
        var sides: [[String: Any]] = []
        for (i, raw) in (plan["sides"] as? [[String: Any]] ?? []).prefix(4).enumerated() {
            var id = text(raw["id"], 20).lowercased()
            if id.range(of: "^[a-z0-9_-]{1,20}$", options: .regularExpression) == nil || sides.contains(where: { $0["id"] as? String == id }) { id = "side\(i + 1)" }
            let color = text(raw["color"], 7)
            sides.append(["id": id, "name": text(raw["name"], 40), "color": color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? color : palette[i]])
        }
        let ids = sides.compactMap { $0["id"] as? String }
        let places: [[String: Any]] = (plan["places"] as? [[String: Any]] ?? []).prefix(16).compactMap { raw in
            let name = text(raw["name"], 40), kind = text(raw["kind"], 10)
            guard !name.isEmpty, let at = point(raw["at"]) else { return nil }
            return ["name": name, "at": at, "kind": ["city", "fort", "river", "mountain"].contains(kind) ? kind : "city"]
        }
        let moves: [[String: Any]] = (plan["moves"] as? [[String: Any]] ?? []).prefix(10).compactMap { raw in
            let path = (raw["path"] as? [Any] ?? []).prefix(24).compactMap(point)
            let from = time(raw["start"]), to = time(raw["end"])
            guard path.count >= 2, to - from >= 0.2 else { return nil }
            let side = text(raw["side"], 20).lowercased()
            return ["side": ids.contains(side) ? side : (ids.first ?? "side1"), "path": path, "start": from, "end": to, "label": text(raw["label"], 40),
                    "kind": text(raw["kind"], 10) == "retreat" ? "retreat" : "advance", "icon": text(raw["icon"], 10) == "ship" ? "ship" : "arrow"]
        }
        let clashes: [[String: Any]] = (plan["clashes"] as? [[String: Any]] ?? []).prefix(8).compactMap { raw in
            guard let at = point(raw["at"]) else { return nil }
            return ["at": at, "time": time(raw["time"]), "label": text(raw["label"], 40)]
        }
        let vertical = aspect == "9:16"
        return ["width": vertical ? 1080 : 1920, "height": vertical ? 1920 : 1080, "seconds": seconds,
                "title": text(plan["title"], 80), "date": text(plan["date"], 40), "style": text(plan["style"], 10) == "plain" ? "plain" : "vintage",
                "start": start, "end": end, "sides": sides, "places": places, "moves": moves, "clashes": clashes]
    }

    // MARK: Plumbing

    private func begin(notify: Bool = true) -> Bool {
        guard !busy else { if notify { update("error", 0, "Đang cài hoặc dựng. Đợi xong hoặc dừng trước.") }; return false }
        busy = true; cancelled = false
        return true
    }
    private func update(_ phase: String, _ progress: Double, _ message: String) {
        let send: () -> Void = { self.onUpdate?(["status": "progress", "phase": phase, "progress": progress, "message": message]) }
        if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
    }
    private func finish(message: String? = nil, error: String? = nil) {
        busy = false; process = nil; download = nil
        var result = status(); result["status"] = error == nil ? "installed" : "error"; result["message"] = error ?? message ?? ""
        onUpdate?(result)
    }
    private var observation: NSKeyValueObservation?
    private func observe(_ task: URLSessionTask, phase: String, label: String) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.update(phase, progress.fractionCompleted, "\(label)… \(Int(progress.fractionCompleted * 100))%")
        }
    }

    /// Runs a Node tool in the project folder with that Node first on PATH and npm's cache inside the workspace.
    /// JSON progress lines ({phase, progress}) are forwarded; the last stderr/stdout text explains failures.
    private func run(_ executable: URL, _ arguments: [String], node: URL, completion: @escaping (Bool, String) -> Void) {
        let task = Process(), out = Pipe(), err = Pipe()
        task.executableURL = executable; task.arguments = arguments; task.currentDirectoryURL = project
        var env = ["PATH": node.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                   "npm_config_cache": runtime.appendingPathComponent("npm-cache").path, "npm_config_update_notifier": "false", "LANG": "en_US.UTF-8"]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = tmp }
        task.environment = env
        task.standardOutput = out; task.standardError = err
        var tail = "", buffer = ""
        let lock = NSLock()
        func remember(_ text: String) { lock.lock(); tail = String((tail + text).suffix(600)); lock.unlock() }
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound]); buffer.removeSubrange(..<range.upperBound)
                if let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let phase = json["phase"] as? String {
                    if phase == "error" { remember((json["message"] as? String ?? "") + " ") }
                    else if phase != "done" { self?.update(phase, (json["progress"] as? NSNumber)?.doubleValue ?? 0, Self.label(phase, (json["progress"] as? NSNumber)?.doubleValue ?? 0)) }
                } else { remember(line + " ") }
            }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) { remember(text) }
        }
        task.terminationHandler = { finished in
            out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
            lock.lock(); let message = tail.trimmingCharacters(in: .whitespacesAndNewlines); lock.unlock()
            DispatchQueue.main.async { completion(finished.terminationStatus == 0, String(message.suffix(300))) }
        }
        do { try task.run(); process = task } catch { completion(false, error.localizedDescription) }
    }
    static func label(_ phase: String, _ progress: Double) -> String {
        let percent = " \(Int(max(0, min(1, progress)) * 100))%"
        switch phase {
        case "bundle": return "Đang chuẩn bị dự án Remotion…" + percent
        case "browser": return "Đang tải trình duyệt render…" + percent
        case "render": return "Đang dựng cảnh bản đồ…" + percent
        default: return "Đang xử lý…" + percent
        }
    }
}
