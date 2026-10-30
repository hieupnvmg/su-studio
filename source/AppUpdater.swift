import Cocoa
import CryptoKit

final class AppUpdater: NSObject, URLSessionTaskDelegate {
    var onUpdate: (([String: Any]) -> Void)?
    let repository: String
    let current: String
    private(set) var busy = false
    private var assetURL: URL?
    private var digest = ""
    private var version = ""
    private var staged: URL?
    private var session: URLSession?
    private let cache: URL
    init(root: URL) {
        repository = Bundle.main.object(forInfoDictionaryKey: "UpdateRepository") as? String ?? "hieupnvmg/su-studio"
        current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        cache = root.appendingPathComponent("updates", isDirectory: true)
    }
    static func newer(_ candidate: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let plain = value.hasPrefix("v") ? String(value.dropFirst()) : value
            let p = plain.split(separator: ".", omittingEmptySubsequences: false)
            guard p.count == 3, p.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), p.allSatisfy({ Int($0) != nil }) else { return nil }
            return p.compactMap { Int($0) }
        }
        guard let a = parts(candidate), let b = parts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }
    private func emit(_ state: String, _ message: String) {
        onUpdate?(["status": state, "message": message, "current": current, "version": version, "repository": repository])
    }
    private func fetch(_ url: URL, token: String?, binary: Bool = false, completion: @escaping (Data?, Int, Error?) -> Void) {
        var req = URLRequest(url: url); req.timeoutInterval = binary ? 180 : 25
        req.setValue(binary ? "application/octet-stream" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Su-Studio-Updater", forHTTPHeaderField: "User-Agent")
        if let token = token, !token.isEmpty { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let config = URLSessionConfiguration.ephemeral; config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 240
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); self.session = session
        session.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { session.finishTasksAndInvalidate(); completion(data, status, error) }
        }.resume()
    }
    func check(token: String?) {
        guard !busy else { return }; busy = true; staged = nil; assetURL = nil
        emit("checking", "Đang kiểm tra GitHub Releases…")
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        fetch(url, token: token) { [weak self] data, status, error in
            guard let self = self else { return }; self.busy = false
            guard error == nil, status == 200, let data = data,
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  body["draft"] as? Bool == false, body["prerelease"] as? Bool == false,
                  let tag = body["tag_name"] as? String else {
                self.emit("error", status == 404 ? "Chưa có release hoặc repo riêng tư. Nếu repo riêng tư, lưu GitHub token có quyền Contents: Read của repo rồi thử lại." : "Không kiểm tra được cập nhật (HTTP \(status)). Kiểm tra mạng hoặc quyền GitHub."); return
            }
            self.version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.newer(self.version, than: self.current) else {
                self.emit("current", "Bạn đang dùng bản mới nhất (\(self.current))."); return
            }
            let name = "Su-Studio-\(self.version)-Universal.zip"
            guard let assets = body["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { $0["name"] as? String == name }),
                  let raw = asset["url"] as? String, let assetURL = URL(string: raw),
                  assetURL.scheme == "https", assetURL.host == "api.github.com",
                  assetURL.path.hasPrefix("/repos/\(self.repository)/releases/assets/"),
                  let digest = asset["digest"] as? String,
                  digest.range(of: "^sha256:[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
                  let size = asset["size"] as? Int, size > 0, size < 512_000_000 else {
                self.emit("error", "Release mới chưa có gói Universal ZIP hoặc mã SHA-256 hợp lệ. Chưa cho phép cài."); return
            }
            self.assetURL = assetURL; self.digest = String(digest.dropFirst(7)).lowercased()
            self.emit("available", "Có bản \(self.version). Bấm tải để xác minh và chuẩn bị cài.")
        }
    }
    func download(token: String?) {
        guard !busy, let url = assetURL else { return }; busy = true
        emit("downloading", "Đang tải bản \(version) và kiểm tra SHA-256…")
        fetch(url, token: token, binary: true) { [weak self] data, status, error in
            guard let self = self else { return }
            guard error == nil, status == 200, let data = data, data.count < 512_000_000,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == self.digest else {
                self.busy = false; self.emit("error", "Tải hoặc xác minh SHA-256 thất bại (HTTP \(status)). Không cài bản này."); return
            }
            let expectedVersion = self.version
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let work = self.cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                    let archive = work.appendingPathComponent("update.zip"); try data.write(to: archive, options: .atomic)
                    let unpack = work.appendingPathComponent("unpacked", isDirectory: true)
                    try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
                    try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpack.path])
                    let app = unpack.appendingPathComponent("HistoryStudio.app")
                    guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "local.history.studio",
                          bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion else {
                        throw NSError(domain: "Update", code: 1)
                    }
                    try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
                    DispatchQueue.main.async { self.staged = app; self.busy = false; self.emit("ready", "Đã xác minh bản \(expectedVersion). Cài đặt sẽ đóng và mở lại app; dữ liệu dự án được giữ.") }
                } catch {
                    DispatchQueue.main.async { self.busy = false; self.emit("error", "Gói cập nhật không hợp lệ hoặc không giải nén được. Không thay bản đang dùng.") }
                }
            }
        }
    }
    static func run(_ binary: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: binary); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "UpdateProcess", code: Int(p.terminationStatus)) }
    }
    func install() {
        guard !busy, let staged = staged else { return }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", !target.path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: parent.path) else {
            emit("error", "Hãy cài Sử Studio vào thư mục Applications bạn có quyền ghi trước. App không tự xin quyền admin."); return
        }
        busy = true; emit("installing", "Đang chuẩn bị cài bản cập nhật…")
        DispatchQueue.global(qos: .userInitiated).async {
            let replacement = parent.appendingPathComponent(".SuStudio-update-" + UUID().uuidString + ".app")
            do {
                try Self.run("/usr/bin/ditto", [staged.path, replacement.path])
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
                let helper = self.cache.appendingPathComponent("install-" + UUID().uuidString + ".sh")
                let script = """
                #!/bin/sh
                set -eu
                pid="$1"; target="$2"; replacement="$3"; backup="$4"
                count=0
                while kill -0 "$pid" 2>/dev/null; do
                    count=$((count + 1))
                    if [ "$count" -ge 300 ]; then exit 1; fi
                    sleep 0.2
                done
                /bin/mv "$target" "$backup"
                if /bin/mv "$replacement" "$target"; then
                    /usr/bin/open "$target"
                    # Preserve previous app for manual rollback.
                else
                    /bin/mv "$backup" "$target"
                    /usr/bin/open "$target"
                    exit 1
                fi
                """
                try script.write(to: helper, atomically: true, encoding: .utf8)
                let backup = parent.appendingPathComponent(".SuStudio-previous-" + UUID().uuidString + ".app")
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), target.path, replacement.path, backup.path]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try p.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch {
                try? FileManager.default.removeItem(at: replacement)
                DispatchQueue.main.async { self.busy = false; self.emit("error", "Không chuẩn bị được bản cài. Bản hiện tại vẫn được giữ nguyên.") }
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", let host = url.host,
              host == "api.github.com" || host == "github.com" || host.hasSuffix(".githubusercontent.com") else { completionHandler(nil); return }
        var safe = request
        if host != "api.github.com" { safe.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(safe)
    }
}
