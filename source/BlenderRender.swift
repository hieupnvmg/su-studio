import Cocoa
import AVFoundation
import Vision
import CoreImage

/// Renders scene clips with a local Blender install: a 3D model the user picked, or a scene
/// built by an AI-written bpy script. Blender runs headless with a bundled driver script,
/// inside a macOS sandbox with no network and no writes outside the job folder. Frames are
/// rendered as PNG and assembled into H.264 here, so Blender's own video encoder is not needed.
final class BlenderRender: NSObject {
    static let defaultsKey = "BlenderAppPath"
    /// Free CC0 assets from Poly Haven, downloaded on request. kind: hdri | texture | model.
    struct LibraryItem { let kind: String; let key: String; let id: String; let title: String; let pack: String }
    static let catalog: [LibraryItem] = [
        .init(kind: "hdri", key: "overcast", id: "overcast_soil_puresky", title: "Trời u ám", pack: "base"),
        .init(kind: "hdri", key: "clear", id: "kloofendal_48d_partly_cloudy_puresky", title: "Trời quang, mây nhẹ", pack: "base"),
        .init(kind: "hdri", key: "sunset", id: "kloppenheim_06_puresky", title: "Hoàng hôn", pack: "base"),
        .init(kind: "hdri", key: "fire_sky", id: "the_sky_is_on_fire", title: "Hoàng hôn đỏ rực", pack: "base"),
        .init(kind: "hdri", key: "forest", id: "rainforest_trail", title: "Đường rừng", pack: "base"),
        .init(kind: "hdri", key: "misty", id: "misty_pines", title: "Rừng sương mù", pack: "base"),
        .init(kind: "hdri", key: "night", id: "kloppenheim_02", title: "Đêm", pack: "base"),
        .init(kind: "hdri", key: "city_dusk", id: "sunset_jhbcentral", title: "Thành phố chạng vạng", pack: "base"),
        .init(kind: "texture", key: "mud", id: "brown_mud_leaves_01", title: "Bùn lẫn lá", pack: "base"),
        .init(kind: "texture", key: "mud_dry", id: "brown_mud_dry", title: "Bùn khô", pack: "base"),
        .init(kind: "texture", key: "forest_floor", id: "forest_leaves_02", title: "Đất rừng", pack: "base"),
        .init(kind: "texture", key: "grass", id: "leafy_grass", title: "Cỏ", pack: "base"),
        .init(kind: "texture", key: "sand", id: "sand_01", title: "Cát", pack: "base"),
        .init(kind: "texture", key: "rocks", id: "aerial_rocks_02", title: "Đá sỏi", pack: "base"),
        .init(kind: "texture", key: "concrete", id: "concrete_floor_02", title: "Bê tông", pack: "base"),
        .init(kind: "texture", key: "plaster", id: "painted_plaster_wall", title: "Tường vữa", pack: "base"),
        .init(kind: "texture", key: "brick", id: "red_brick_03", title: "Gạch đỏ", pack: "base"),
        .init(kind: "texture", key: "planks", id: "weathered_brown_planks", title: "Ván gỗ cũ", pack: "base"),
        .init(kind: "texture", key: "bark", id: "bark_brown_02", title: "Vỏ cây", pack: "base"),
        .init(kind: "texture", key: "roof_iron", id: "corrugated_iron", title: "Mái tôn", pack: "base"),
        .init(kind: "texture", key: "cobblestone", id: "cobblestone_floor_04", title: "Đá lát", pack: "base"),
        .init(kind: "texture", key: "stone_blocks", id: "medieval_blocks_03", title: "Khối đá cổ", pack: "base"),
        .init(kind: "model", key: "fern", id: "fern_02", title: "Dương xỉ", pack: "nature"),
        .init(kind: "model", key: "grass_clump", id: "grass_medium_01", title: "Khóm cỏ", pack: "nature"),
        .init(kind: "model", key: "grass_short", id: "grass_bermuda_01", title: "Cỏ thấp", pack: "nature"),
        .init(kind: "model", key: "dead_trunk", id: "dead_tree_trunk_02", title: "Gốc cây khô", pack: "nature"),
        .init(kind: "model", key: "dry_branches", id: "dry_branches_medium_01", title: "Cành khô", pack: "nature"),
        .init(kind: "model", key: "boulder", id: "boulder_01", title: "Tảng đá", pack: "nature"),
        .init(kind: "model", key: "mossy_rocks", id: "rock_moss_set_01", title: "Đá rêu", pack: "nature"),
        .init(kind: "model", key: "military_crate", id: "old_military_crate", title: "Thùng quân dụng", pack: "props"),
        .init(kind: "model", key: "wooden_crate", id: "wooden_crate_01", title: "Thùng gỗ", pack: "props"),
        .init(kind: "model", key: "barrel", id: "Barrel_01", title: "Thùng phuy", pack: "props"),
        .init(kind: "model", key: "wooden_barrels", id: "wooden_barrels_01", title: "Thùng gỗ tròn", pack: "props"),
        .init(kind: "model", key: "road_barrier", id: "concrete_road_barrier", title: "Rào bê tông", pack: "props"),
        .init(kind: "model", key: "cannon", id: "cannon_01", title: "Đại bác cổ", pack: "props"),
    ]
    static let packs: [(key: String, title: String)] = [("base", "Bầu trời và chất liệu"), ("nature", "Cây cỏ, đá"), ("props", "Đạo cụ")]
    var libraryRoot: URL { root.appendingPathComponent("library/polyhaven", isDirectory: true) }
    private var downloading = false
    static let modelTypes = ["glb", "gltf", "fbx", "obj", "blend", "usd", "usdz", "usdc", "usda", "stl"]
    static let imageTypes = ["png", "jpg", "jpeg", "webp", "heic", "tif", "tiff"]
    static let moves = ["push", "pull", "pan_left", "pan_right", "rise", "orbit", "static"]
    static let overlayNames = ["smoke", "fog", "dust", "embers", "rain"]
    let root: URL
    var onUpdate: (([String: Any]) -> Void)?
    var driver: URL? = Bundle.main.url(forResource: "blender_render", withExtension: "py")
    var useSandbox = FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec")
    var applicationOverride: URL?
    var home = FileManager.default.homeDirectoryForCurrentUser
    private var process: Process?
    private var cancelled = false
    var busy: Bool { process != nil }
    init(root: URL) { self.root = root }
    var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }

    static func executable(_ app: URL) -> URL { app.appendingPathComponent("Contents/MacOS/Blender") }
    static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var list: [URL] = []
        for folder in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            list.append(folder.appendingPathComponent("Blender.app"))
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            list += names.filter { $0.hasPrefix("Blender") && $0.hasSuffix(".app") && $0 != "Blender.app" }.sorted().reversed().map { folder.appendingPathComponent($0) }
        }
        return list
    }
    /// "Blender 4.2.3" → "4.2.3"; nil when the app does not answer like Blender.
    static func version(of app: URL) -> String? {
        let exe = executable(app)
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return nil }
        let task = Process(); task.executableURL = exe; task.arguments = ["--factory-startup", "--version"]
        let out = Pipe(); task.standardOutput = out; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(30)
        while task.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate(); return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("Blender ") }) else { return nil }
        return line.dropFirst("Blender ".count).split(separator: " ").first.map(String.init)
    }
    func locate() -> (app: URL, version: String)? {
        var list: [URL] = []
        if let override = applicationOverride { list.append(override) }
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) { list.append(URL(fileURLWithPath: saved)) }
        list += Self.candidates()
        for app in list { if let v = Self.version(of: app) { return (app, v) } }
        return nil
    }
    func status() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = self.locate()
            DispatchQueue.main.async {
                if let found { self.onUpdate?(["status": "found", "path": found.app.path, "version": found.version, "sandbox": self.useSandbox]) }
                else { self.onUpdate?(["status": "missing", "message": "Chưa tìm thấy Blender. Cài Blender 4.x/5.x vào thư mục Applications hoặc chọn Blender.app."]) }
            }
        }
    }
    func choose() {
        let panel = NSOpenPanel(); panel.allowedFileTypes = ["app"]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.title = "Chọn Blender.app"; panel.prompt = "Dùng Blender này"
        guard panel.runModal() == .OK, let app = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let v = Self.version(of: app)
            DispatchQueue.main.async {
                guard let v else { self.onUpdate?(["status": "missing", "message": "\(app.lastPathComponent) không phải Blender chạy được."]); return }
                UserDefaults.standard.set(app.path, forKey: Self.defaultsKey)
                self.onUpdate?(["status": "found", "path": app.path, "version": v, "sandbox": self.useSandbox])
            }
        }
    }
    /// Copies a picked 3D model into the project assets so backups and moves keep it.
    func importModel(_ body: [String: Any]) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedFileTypes = Self.modelTypes
        panel.title = "Chọn model 3D"; panel.prompt = "Dùng model"
        var reply: [String: Any] = ["status": "model", "projectId": body["projectId"] ?? "", "sceneId": body["sceneId"] ?? "", "clipId": body["clipId"] ?? "", "library": body["library"] as? Bool ?? false]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            let dest = assets.appendingPathComponent(UUID().uuidString + "-" + file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: dest)
            reply["path"] = dest.path; reply["name"] = file.lastPathComponent
        } catch { reply = ["status": "error", "message": "Không chép được model: \(error.localizedDescription)"] }
        onUpdate?(reply)
    }

    /// Blender ships its own Python (Contents/Resources/<version>/python/bin/python3.x).
    static func bundledPython(_ app: URL) -> URL? {
        let resources = app.appendingPathComponent("Contents/Resources")
        for version in ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []).sorted().reversed() {
            let bin = resources.appendingPathComponent(version).appendingPathComponent("python/bin")
            if let name = ((try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []).sorted().first(where: { $0.hasPrefix("python3") }),
               FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent(name).path) { return bin.appendingPathComponent(name) }
        }
        return nil
    }
    /// Runs the driver's script checker (parse only, nothing executes) and returns the problems found.
    static func checkScript(_ script: String, driver: URL, python: URL) throws -> [String] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("su-check-\(UUID().uuidString).py")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let task = Process(); task.executableURL = python; task.arguments = ["-I", driver.path, "--check", file.path]
        let out = Pipe(); task.standardOutput = out; task.standardError = FileHandle.nullDevice
        try task.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard let problems = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { throw NSError(domain: "BlenderRender", code: 7, userInfo: [NSLocalizedDescriptionKey: "Không kiểm tra được script."]) }
        return problems
    }
    func check(_ body: [String: Any]) {
        let script = body["script"] as? String ?? ""
        var reply: [String: Any] = ["status": "checked", "projectId": body["projectId"] ?? "", "clipId": body["clipId"] ?? "", "requestId": body["requestId"] ?? ""]
        DispatchQueue.global(qos: .userInitiated).async {
            let python = self.locate().flatMap { Self.bundledPython($0.app) } ?? URL(fileURLWithPath: "/usr/bin/python3")
            do {
                guard let driver = self.driver else { throw NSError(domain: "BlenderRender", code: 8, userInfo: [NSLocalizedDescriptionKey: "Thiếu script điều khiển Blender trong app."]) }
                reply["problems"] = try Self.checkScript(script, driver: driver, python: python)
            } catch { reply["status"] = "uncheckable"; reply["message"] = error.localizedDescription }
            DispatchQueue.main.async { self.onUpdate?(reply) }
        }
    }
    // MARK: Poly Haven library
    func itemFolder(_ item: LibraryItem) -> URL { libraryRoot.appendingPathComponent(item.kind).appendingPathComponent(item.key, isDirectory: true) }
    /// Installed files by kind, in the shape the driver expects.
    func installed() -> [String: Any] {
        var hdri: [String: String] = [:], textures: [String: [String: String]] = [:], models: [String: String] = [:]
        let fm = FileManager.default
        for item in Self.catalog {
            let folder = itemFolder(item)
            guard fm.fileExists(atPath: folder.appendingPathComponent(".complete").path) else { continue }
            switch item.kind {
            case "hdri": hdri[item.key] = folder.appendingPathComponent("sky.hdr").path
            case "texture": textures[item.key] = ["diff": folder.appendingPathComponent("diff.jpg").path, "nor": folder.appendingPathComponent("nor.jpg").path, "rough": folder.appendingPathComponent("rough.jpg").path]
            default:
                if let name = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).first(where: { $0.hasSuffix(".gltf") }) { models[item.key] = folder.appendingPathComponent(name).path }
            }
        }
        return ["hdri": hdri, "textures": textures, "models": models]
    }
    func libraryStatus() {
        let done = installed()
        let keys = Set(((done["hdri"] as? [String: String]) ?? [:]).keys).union(((done["textures"] as? [String: Any]) ?? [:]).keys).union(((done["models"] as? [String: String]) ?? [:]).keys)
        let packs = Self.packs.map { pack -> [String: Any] in
            let items = Self.catalog.filter { $0.pack == pack.key }
            return ["key": pack.key, "title": pack.title, "count": items.count, "installed": items.filter { keys.contains($0.key) }.count]
        }
        let items = Self.catalog.filter { keys.contains($0.key) }.map { ["kind": $0.kind, "key": $0.key, "title": $0.title] }
        onUpdate?(["status": "library", "packs": packs, "items": items, "downloading": downloading])
    }
    static func allowedDownload(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", ["dl.polyhaven.org", "api.polyhaven.com"].contains(url.host ?? "") else { return nil }
        return url
    }
    /// Files to fetch for one catalog item: (remote URL, path relative to the item folder).
    static func downloads(for item: LibraryItem, listing: [String: Any]) -> [(URL, String)] {
        func pick(_ map: String, _ res: String = "1k", _ fmt: String = "jpg") -> String? { ((listing[map] as? [String: Any])?[res] as? [String: Any]).flatMap { ($0[fmt] as? [String: Any])?["url"] as? String } }
        switch item.kind {
        case "hdri":
            guard let raw = (((listing["hdri"] as? [String: Any])?["2k"] as? [String: Any])?["hdr"] as? [String: Any])?["url"] as? String, let url = allowedDownload(raw) else { return [] }
            return [(url, "sky.hdr")]
        case "texture":
            var list: [(URL, String)] = []
            for (map, name) in [("Diffuse", "diff.jpg"), ("nor_gl", "nor.jpg"), ("Rough", "rough.jpg")] { if let raw = pick(map), let url = allowedDownload(raw) { list.append((url, name)) } }
            return list.count == 3 ? list : []
        default:
            guard let gltf = ((listing["gltf"] as? [String: Any])?["1k"] as? [String: Any])?["gltf"] as? [String: Any],
                  let raw = gltf["url"] as? String, let url = allowedDownload(raw) else { return [] }
            var list = [(url, url.lastPathComponent)]
            for (relative, info) in (gltf["include"] as? [String: Any]) ?? [:] {
                guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."),
                      let raw = (info as? [String: Any])?["url"] as? String, let url = allowedDownload(raw) else { return [] }
                list.append((url, relative))
            }
            return list
        }
    }
    func downloadPack(_ pack: String) {
        guard !downloading else { return }
        let items = Self.catalog.filter { $0.pack == pack }
        guard !items.isEmpty else { return }
        downloading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 60; config.httpShouldSetCookies = false
            let session = URLSession(configuration: config)
            func fetch(_ url: URL) -> Data? {
                var request = URLRequest(url: url); request.setValue("Su-Studio", forHTTPHeaderField: "User-Agent")
                let done = DispatchSemaphore(value: 0); var result: Data?
                session.dataTask(with: request) { data, response, error in
                    if error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data, data.count < 300_000_000 { result = data }
                    done.signal()
                }.resume()
                done.wait(); return result
            }
            var failed: [String] = []
            for (index, item) in items.enumerated() {
                let folder = self.itemFolder(item)
                if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".complete").path) { continue }
                DispatchQueue.main.async { self.onUpdate?(["status": "libraryProgress", "message": "Đang tải \(item.title) (\(index + 1)/\(items.count))…"]) }
                guard let api = URL(string: "https://api.polyhaven.com/files/\(item.id)"), let data = fetch(api),
                      let listing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { failed.append(item.title); continue }
                let files = Self.downloads(for: item, listing: listing)
                guard !files.isEmpty else { failed.append(item.title); continue }
                try? FileManager.default.removeItem(at: folder)
                var ok = true
                for (url, relative) in files {
                    let dest = folder.appendingPathComponent(relative)
                    // Relative paths were checked in downloads(for:): no "..", nothing absolute.
                    guard let body = fetch(url) else { ok = false; break }
                    do { try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true); try body.write(to: dest) } catch { ok = false; break }
                }
                if ok { try? Data().write(to: folder.appendingPathComponent(".complete")) } else { try? FileManager.default.removeItem(at: folder); failed.append(item.title) }
            }
            DispatchQueue.main.async {
                self.downloading = false
                if !failed.isEmpty { self.onUpdate?(["status": "libraryProgress", "message": "Chưa tải được: \(failed.joined(separator: ", ")). Kiểm tra mạng rồi bấm tải lại."]) }
                self.libraryStatus()
            }
        }
    }

    /// Splits a picture into a background with the subject area filled in and a cut-out subject with transparency,
    /// using macOS's subject lifting (macOS 14+). Without a clear subject, the picture stays a single layer.
    static func separateSubject(_ image: URL, into folder: URL, index: Int) throws -> (background: URL, subject: URL?) {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw NSError(domain: "BlenderRender", code: 9, userInfo: [NSLocalizedDescriptionKey: "Không đọc được ảnh \(image.lastPathComponent)."]) }
        guard #available(macOS 14.0, *) else { return (image, nil) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: picture)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first, !result.allInstances.isEmpty,
              let buffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else { return (image, nil) }
        let context = CIContext()
        let original = CIImage(cgImage: picture), extent = original.extent
        var mask = CIImage(cvPixelBuffer: buffer)
        mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
        // A subject covering almost nothing or almost everything gives no useful depth.
        let coverage = mask.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(coverage, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        guard pixel[0] > 0.02, pixel[0] < 0.85 else { return (image, nil) }
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: 1.2).cropped(to: extent)
        let clear = CIImage(color: .clear).cropped(to: extent)
        let subject = original.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: soft])
        // Background: cut a slightly larger hole, then fill it from the surrounding colours, coarse to fine.
        let scale = max(extent.width, extent.height) / 1000
        let hole = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 10 * scale]).applyingGaussianBlur(sigma: 2 * scale).cropped(to: extent)
        let holed = clear.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: original, kCIInputMaskImageKey: hole])
        var filled = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: extent)
        for radius in [160.0, 60.0, 24.0, 8.0] {
            // CIColorMatrix works on unpremultiplied colour: the blurred, partly transparent ring becomes the average
            // surrounding colour, and boosting alpha lets it cover the hole.
            let spread = holed.clampedToExtent().applyingGaussianBlur(sigma: radius * scale).cropped(to: extent)
            let layer = spread.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 3)])
            filled = layer.composited(over: filled)
        }
        let background = holed.composited(over: filled).cropped(to: extent)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let backgroundURL = folder.appendingPathComponent("nen-\(index).png"), subjectURL = folder.appendingPathComponent("chu-the-\(index).png")
        try context.writePNGRepresentation(of: background, to: backgroundURL, format: .RGBA8, colorSpace: colorSpace)
        try context.writePNGRepresentation(of: subject, to: subjectURL, format: .RGBA8, colorSpace: colorSpace)
        return (backgroundURL, subjectURL)
    }

    // MARK: Free 3D models: Sketchfab search (no login) + the model files Objaverse mirrors on Hugging Face (no login)
    var objaverseIndex: URL { root.appendingPathComponent("library/objaverse/object-paths.json") }
    private var objaversePaths: [String: String]?
    private let searchQueue = DispatchQueue(label: "su-studio.model-search")
    /// Commercial use allowed: CC0, CC Attribution (incl. ShareAlike), Sketchfab Free Standard. No NonCommercial, no NoDerivs.
    static func commercialLicense(_ label: String) -> Bool {
        let l = label.lowercased()
        guard !l.contains("noncommercial"), !l.contains("noderiv"), !l.contains("non-commercial") else { return false }
        return l.contains("cc0") || l.contains("public domain") || l.contains("attribution") || l.contains("free standard") || l == "standard"
    }
    func modelIndexStatus() {
        onUpdate?(["status": "modelIndex", "ready": FileManager.default.fileExists(atPath: objaverseIndex.path)])
    }
    func downloadModelIndex() {
        onUpdate?(["status": "modelIndexProgress", "message": "Đang tải bảng tra cứu model (khoảng 20 MB)…"])
        let dest = objaverseIndex
        searchQueue.async {
            var request = URLRequest(url: URL(string: "https://huggingface.co/datasets/allenai/objaverse/resolve/main/object-paths.json.gz")!)
            request.timeoutInterval = 120; request.setValue("Su-Studio", forHTTPHeaderField: "User-Agent")
            let done = DispatchSemaphore(value: 0); var data: Data?
            URLSession(configuration: .ephemeral).dataTask(with: request) { body, response, error in
                if error == nil, (response as? HTTPURLResponse)?.statusCode == 200 { data = body }; done.signal()
            }.resume()
            done.wait()
            var ok = false
            if let data, data.count > 1_000_000 {
                let temp = dest.deletingLastPathComponent().appendingPathComponent("object-paths.json.gz")
                try? FileManager.default.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? data.write(to: temp)) != nil {
                    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip"); task.arguments = ["-f", temp.path]
                    if (try? task.run()) != nil { task.waitUntilExit(); ok = task.terminationStatus == 0 && FileManager.default.fileExists(atPath: dest.path) }
                }
            }
            DispatchQueue.main.async {
                if !ok { self.onUpdate?(["status": "modelIndexProgress", "message": "Chưa tải được bảng tra cứu. Kiểm tra mạng rồi thử lại."]) }
                self.modelIndexStatus()
            }
        }
    }
    private func paths() -> [String: String]? {
        if let objaversePaths { return objaversePaths }
        guard let data = try? Data(contentsOf: objaverseIndex), let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return nil }
        objaversePaths = map
        return map
    }
    /// Normalises one Sketchfab search result into what the app shows, or nil when it cannot be used.
    static func modelResult(_ m: [String: Any], paths: [String: String], maxFaces: Int = 600_000) -> [String: Any]? {
        guard let uid = m["uid"] as? String, let path = paths[uid] else { return nil }
        let license = ((m["license"] as? [String: Any])?["label"] as? String) ?? ""
        guard commercialLicense(license) else { return nil }
        let faces = m["faceCount"] as? Int ?? 0
        guard faces <= maxFaces else { return nil }
        let images = ((m["thumbnails"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
        let thumb = images.filter { ($0["width"] as? Int ?? 0) >= 200 }.min { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }?["url"] as? String ?? ""
        let user = m["user"] as? [String: Any] ?? [:]
        return ["uid": uid, "path": path, "name": m["name"] as? String ?? "Model", "author": user["displayName"] as? String ?? user["username"] as? String ?? "",
                "authorUrl": user["profileUrl"] as? String ?? "", "license": license, "faces": faces, "animations": m["animationCount"] as? Int ?? 0,
                "likes": m["likeCount"] as? Int ?? 0, "thumbnail": thumb.hasPrefix("https://") ? thumb : "", "url": "https://sketchfab.com/3d-models/\(uid)"]
    }
    func searchModels(_ body: [String: Any]) {
        let requestID = body["requestId"] as? String ?? "", query = String((body["query"] as? String ?? "").prefix(120))
        var reply: [String: Any] = ["status": "modelResults", "requestId": requestID, "query": query, "itemKey": body["itemKey"] ?? ""]
        searchQueue.async {
            defer { DispatchQueue.main.async { self.onUpdate?(reply) } }
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { reply["items"] = []; return }
            guard let map = self.paths() else { reply["status"] = "modelSearchFailed"; reply["message"] = "Cần tải bảng tra cứu model trước."; return }
            var items: [[String: Any]] = [], next: URL? = {
                var c = URLComponents(string: "https://api.sketchfab.com/v3/search")!
                c.queryItems = [.init(name: "type", value: "models"), .init(name: "q", value: query), .init(name: "count", value: "24"), .init(name: "sort_by", value: "-likeCount")]
                return c.url
            }()
            for _ in 0..<3 {
                guard let url = next, url.host == "api.sketchfab.com" else { break }
                var request = URLRequest(url: url); request.timeoutInterval = 30; request.setValue("Su-Studio", forHTTPHeaderField: "User-Agent")
                let done = DispatchSemaphore(value: 0); var json: [String: Any]?
                URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
                    if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data { json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
                    done.signal()
                }.resume()
                done.wait()
                guard let json else { if items.isEmpty { reply["status"] = "modelSearchFailed"; reply["message"] = "Chưa tìm được, kiểm tra mạng rồi thử lại." }; break }
                items += ((json["results"] as? [[String: Any]]) ?? []).compactMap { Self.modelResult($0, paths: map) }
                if items.count >= 8 { break }
                next = (json["next"] as? String).flatMap(URL.init(string:))
            }
            reply["items"] = Array(items.prefix(12))
        }
    }
    func downloadModel(_ body: [String: Any]) {
        var reply: [String: Any] = ["status": "modelDownloaded", "requestId": body["requestId"] ?? "", "uid": body["uid"] ?? "", "itemKey": body["itemKey"] ?? ""]
        let uid = body["uid"] as? String ?? ""
        searchQueue.async {
            defer { DispatchQueue.main.async { self.onUpdate?(reply) } }
            guard uid.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil, let map = self.paths(), let path = map[uid],
                  path.range(of: "^glbs/[0-9-]+/[0-9a-f]{32}\\.glb$", options: .regularExpression) != nil,
                  let url = URL(string: "https://huggingface.co/datasets/allenai/objaverse/resolve/main/" + path) else { reply["status"] = "modelDownloadFailed"; reply["message"] = "Model này không có trong kho tải miễn phí."; return }
            var request = URLRequest(url: url); request.timeoutInterval = 300; request.setValue("Su-Studio", forHTTPHeaderField: "User-Agent")
            let done = DispatchSemaphore(value: 0); var data: Data?
            URLSession(configuration: .ephemeral).dataTask(with: request) { body, response, error in
                if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let body, body.count < 300_000_000 { data = body }; done.signal()
            }.resume()
            done.wait()
            guard let data, data.prefix(4) == Data("glTF".utf8) else { reply["status"] = "modelDownloadFailed"; reply["message"] = "Tải model thất bại hoặc file không phải glTF. Thử lại sau."; return }
            do {
                try FileManager.default.createDirectory(at: self.assets, withIntermediateDirectories: true)
                let dest = self.assets.appendingPathComponent(UUID().uuidString + "-\(uid).glb")
                try data.write(to: dest)
                reply["path"] = dest.path; reply["bytes"] = data.count
            } catch { reply["status"] = "modelDownloadFailed"; reply["message"] = error.localizedDescription }
        }
    }

    static func sandboxProfile(job: URL, home: URL) -> String {
        func q(_ url: URL) -> String { "\"" + url.resolvingSymlinksInPath().path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return """
        (version 1)
        (allow default)
        (deny network*)
        (deny file-write* (subpath \(q(home))))
        (allow file-write* (subpath \(q(job))))
        (allow file-write* (subpath \(q(home.appendingPathComponent("Library/Application Support/Blender")))))
        (allow file-write* (subpath \(q(home.appendingPathComponent("Library/Caches")))))
        """
    }

    /// Validates a request into the job file the driver reads. Paths must stay inside the project assets.
    func job(_ body: [String: Any], output: URL) throws -> [String: Any] {
        let mode = body["mode"] as? String ?? ""
        guard ["model", "script", "image"].contains(mode) else { throw issue("Chọn nguồn dựng: ảnh, model 3D hoặc script.") }
        var job: [String: Any] = ["mode": mode, "output": output.path]
        var duration = body["duration"] as? Double ?? 5
        if mode == "image" {
            let assetFolder = assets.standardizedFileURL.resolvingSymlinksInPath().path
            guard let raw = body["shots"] as? [[String: Any]], (1...12).contains(raw.count) else { throw issue("Thêm từ 1 đến 12 ảnh cho clip.") }
            var shots: [[String: Any]] = [], total = 0.0
            for shot in raw {
                guard let path = shot["path"] as? String else { throw issue("Ảnh trong clip bị thiếu.") }
                let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard file.deletingLastPathComponent().path == assetFolder, FileManager.default.fileExists(atPath: file.path), Self.imageTypes.contains(file.pathExtension.lowercased()) else { throw issue("Không tìm thấy ảnh trong tài nguyên dự án. Chọn lại ảnh.") }
                let seconds = min(30, max(0.5, shot["seconds"] as? Double ?? 3))
                let move = shot["move"] as? String ?? "push"
                let flashes = (shot["flashes"] as? [Double] ?? []).filter { $0 >= 0 && $0 <= seconds }.prefix(8).map { $0 + total }
                shots.append(["path": file.path, "background": file.path, "seconds": seconds, "move": Self.moves.contains(move) ? move : "push",
                              "strength": min(2, max(0.2, shot["strength"] as? Double ?? 1)), "parallax": shot["parallax"] as? Bool ?? true, "flashes": Array(flashes)])
                total += seconds
            }
            guard total <= 60 else { throw issue("Tổng thời lượng các ảnh tối đa 60 giây.") }
            duration = total
            var overlays: [String: Double] = [:]
            for (name, value) in body["overlays"] as? [String: Any] ?? [:] where Self.overlayNames.contains(name) { overlays[name] = min(1, max(0, value as? Double ?? 0)) }
            job["shots"] = shots; job["overlays"] = overlays
        } else if mode == "model" {
            guard let raw = body["modelPath"] as? String else { throw issue("Chưa chọn model 3D.") }
            let model = URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath()
            guard model.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == assets.standardizedFileURL.resolvingSymlinksInPath().path,
                  FileManager.default.fileExists(atPath: model.path), Self.modelTypes.contains(model.pathExtension.lowercased()) else { throw issue("Không tìm thấy model trong tài nguyên dự án. Chọn lại model.") }
            job["model"] = model.path; job["useFileCamera"] = body["useFileCamera"] as? Bool ?? false; job["ground"] = body["ground"] as? Bool ?? true
        } else {
            guard let script = body["script"] as? String, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, script.count <= 100_000 else { throw issue("Chưa có script dựng cảnh.") }
            job["script"] = script
        }
        let fps = body["fps"] as? Int ?? 30
        guard duration >= 0.5, duration <= (mode == "image" ? 60 : 30), [24, 25, 30].contains(fps) else { throw issue("Thời lượng 1–30 giây, 24/25/30 hình/giây.") }
        let vertical = body["aspectRatio"] as? String == "9:16", draft = body["quality"] as? String == "draft"
        let long = draft ? 960 : 1920, short = draft ? 540 : 1080
        let camera = body["camera"] as? String ?? "orbit", light = body["lighting"] as? String ?? "day"
        job["width"] = vertical ? short : long; job["height"] = vertical ? long : short
        job["duration"] = duration; job["fps"] = fps; job["quality"] = draft ? "draft" : "eevee"
        let raw = body["effects"] as? [String: Any] ?? [:]
        var effects: [String: Any] = [:]
        for key in ["motionBlur", "dof", "shake", "bloom"] { effects[key] = raw[key] as? Bool ?? true }
        effects["fog"] = min(0.02, max(0, raw["fog"] as? Double ?? 0))
        let film = raw["film"] as? String ?? "none"
        effects["film"] = ["none", "film35", "contrast", "bleach"].contains(film) ? film : "none"
        // Library: downloaded Poly Haven assets plus the user's own models (only files inside the project assets).
        var library = installed()
        var models = library["models"] as? [String: String] ?? [:]
        let assetFolder = assets.standardizedFileURL.resolvingSymlinksInPath().path
        for (name, raw) in body["models"] as? [String: String] ?? [:] {
            let file = URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath()
            guard name.range(of: "^[a-z0-9_]{1,40}$", options: .regularExpression) != nil, file.deletingLastPathComponent().path == assetFolder,
                  Self.modelTypes.contains(file.pathExtension.lowercased()), FileManager.default.fileExists(atPath: file.path) else { continue }
            models[name] = file.path
        }
        library["models"] = models
        job["library"] = library
        job["effects"] = effects
        if body["preview"] as? Bool == true {
            let last = max(1, Int((duration * Double(fps)).rounded()))
            job["frames"] = Array(Set([1, last / 3, last * 2 / 3, last].map { max(1, $0) })).sorted()
        }
        job["camera"] = ["orbit", "dolly", "pan", "crane", "static"].contains(camera) ? camera : "orbit"
        job["lighting"] = ["day", "golden", "night", "studio"].contains(light) ? light : "day"
        return job
    }
    private func issue(_ message: String) -> NSError { NSError(domain: "BlenderRender", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    func render(_ body: [String: Any]) {
        let requestID = body["requestId"] as? String ?? ""
        func send(_ value: [String: Any]) { var v = value; v["requestId"] = requestID; v["projectId"] = body["projectId"] ?? ""; v["sceneId"] = body["sceneId"] ?? ""; v["clipId"] = body["clipId"] ?? ""; DispatchQueue.main.async { self.onUpdate?(v) } }
        guard !busy else { send(["status": "error", "message": "Blender đang render cảnh khác. Đợi xong hoặc dừng render."]); return }
        guard let driver, FileManager.default.fileExists(atPath: driver.path) else { send(["status": "error", "message": "Thiếu script điều khiển Blender trong app."]); return }
        let folder = root.appendingPathComponent("blender-jobs", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let frames = folder.appendingPathComponent("frames", isDirectory: true)
        let spec: [String: Any]
        do {
            var made = try job(body, output: frames)
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            if var shots = made["shots"] as? [[String: Any]] {
                for index in shots.indices where shots[index]["parallax"] as? Bool == true {
                    let layers = try Self.separateSubject(URL(fileURLWithPath: shots[index]["path"] as! String), into: folder, index: index)
                    shots[index]["background"] = layers.background.path
                    if let subject = layers.subject { shots[index]["subject"] = subject.path }
                }
                made["shots"] = shots
            }
            spec = made
            try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted]).write(to: folder.appendingPathComponent("job.json"))
        } catch { send(["status": "error", "message": error.localizedDescription]); try? FileManager.default.removeItem(at: folder); return }
        cancelled = false
        send(["status": "starting", "message": "Đang mở Blender…"])
        DispatchQueue.global(qos: .userInitiated).async {
            guard let found = self.locate() else { send(["status": "error", "message": "Chưa tìm thấy Blender. Cài Blender 4.x/5.x hoặc chọn Blender.app trước."]); try? FileManager.default.removeItem(at: folder); return }
            let task = Process()
            let args = ["-b", "--factory-startup", "-noaudio", "-Y", "--python-exit-code", "3", "-P", driver.path, "--", folder.appendingPathComponent("job.json").path]
            if self.useSandbox {
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                task.arguments = ["-p", Self.sandboxProfile(job: folder, home: self.home), Self.executable(found.app).path] + args
            } else { task.executableURL = Self.executable(found.app); task.arguments = args }
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
            var tail: [String] = [], lastError = "", buffer = Data(), lastSent = Date.distantPast
            var renderStarted: Date?, lastFrameAt: Date?, framesDone = 0
            let total = Int((spec["duration"] as? Double ?? 5) * Double(spec["fps"] as? Int ?? 30))
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData; guard !chunk.isEmpty else { return }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 10) {
                    let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self); buffer.removeSubrange(buffer.startIndex...nl)
                    tail.append(line); if tail.count > 40 { tail.removeFirst() }
                    if line.hasPrefix("SU_ERROR ") { lastError = String(line.dropFirst(9)) }
                    if line.hasPrefix("SU_STAGE ") { if line.contains("Đang render") { renderStarted = Date() }; send(["status": "running", "progress": 0, "message": String(line.dropFirst(9))]) }
                    if line.hasPrefix("SU_PROGRESS ") { framesDone += 1; lastFrameAt = Date() }
                    if line.hasPrefix("SU_PROGRESS "), let done = Int(line.dropFirst(12).split(separator: "/").first ?? ""), Date().timeIntervalSince(lastSent) > 0.4 || done >= total {
                        let count = (spec["frames"] as? [Int])?.count ?? total
                        lastSent = Date(); send(["status": "running", "progress": Double(done) / Double(max(count, 1)), "message": "Đang render khung \(done)/\(count)…"])
                    }
                }
            }
            do { try task.run() } catch { send(["status": "error", "message": "Không mở được Blender: \(error.localizedDescription)"]); try? FileManager.default.removeItem(at: folder); return }
            DispatchQueue.main.sync { self.process = task }
            task.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.sync { self.process = nil }
            // Clean up before reporting, so a finished render never leaves its job folder behind.
            func finish(_ value: [String: Any]) { try? FileManager.default.removeItem(at: folder); send(value) }
            if self.cancelled { finish(["status": "cancelled", "message": "Đã dừng render."]); return }
            guard task.terminationStatus == 0 else {
                let detail = lastError.isEmpty ? tail.suffix(6).joined(separator: "\n") : lastError
                finish(["status": "error", "message": "Blender báo lỗi (mã \(task.terminationStatus)). \(detail)"]); return
            }
            if let stills = spec["frames"] as? [Int] {
                // Preview: keep the frames as JPEG stills in the assets folder.
                var paths: [String] = []
                let look = (spec["effects"] as? [String: Any])?["film"] as? String ?? "none", grader = CIContext()
                for frame in stills {
                    let png = frames.appendingPathComponent(String(format: "frame_%04d.png", frame))
                    guard let source = NSImage(contentsOf: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let jpeg = NSBitmapImageRep(cgImage: Self.graded(source, look: look, frame: frame, context: grader)).representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { continue }
                    let dest = self.assets.appendingPathComponent(UUID().uuidString + "-blender-preview.jpg")
                    if (try? jpeg.write(to: dest)) != nil { paths.append(dest.path) }
                }
                // Seconds per frame from this preview, to estimate the full clip.
                let perFrame = renderStarted.flatMap { start in lastFrameAt.map { $0.timeIntervalSince(start) / Double(max(framesDone, 1)) } } ?? 0
                finish(paths.isEmpty ? ["status": "error", "message": "Blender không xuất ra khung xem trước nào."] :
                        ["status": "preview", "paths": paths, "frames": stills, "fps": spec["fps"] ?? 30, "secondsPerFrame": perFrame, "message": "Đã render \(paths.count) khung xem trước bằng Blender \(found.version)."])
                return
            }
            send(["status": "running", "progress": 1, "message": "Đang ghép video…"])
            do {
                try FileManager.default.createDirectory(at: self.assets, withIntermediateDirectories: true)
                let output = self.assets.appendingPathComponent(UUID().uuidString + "-blender.mp4")
                let look = (spec["effects"] as? [String: Any])?["film"] as? String ?? "none"
                let seconds = try Self.assemble(frames: frames, fps: spec["fps"] as? Int ?? 30, to: output, look: look)
                finish(["status": "completed", "path": output.path, "name": output.lastPathComponent, "duration": seconds, "message": "Đã render \(String(format: "%.1f", seconds)) giây bằng Blender \(found.version)."])
            } catch { finish(["status": "error", "message": error.localizedDescription]) }
        }
    }
    func cancel() { cancelled = true; process?.terminate() }

    /// Reads a model's real size and part names with Blender (no render), for the model library.
    func inspect(_ body: [String: Any]) {
        var reply: [String: Any] = ["status": "inspected", "requestId": body["requestId"] ?? "", "modelId": body["modelId"] ?? ""]
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { self.onUpdate?(reply) } }
            let fm = FileManager.default
            guard let driver = self.driver, let found = self.locate(), let raw = body["path"] as? String else { reply["status"] = "inspectFailed"; reply["message"] = "Chưa có Blender để đọc model."; return }
            let model = URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath()
            guard model.deletingLastPathComponent().path == self.assets.standardizedFileURL.resolvingSymlinksInPath().path, fm.fileExists(atPath: model.path) else { reply["status"] = "inspectFailed"; reply["message"] = "Không tìm thấy file model."; return }
            let folder = self.root.appendingPathComponent("blender-jobs", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: folder) }
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let job: [String: Any] = ["mode": "measure", "output": folder.path, "width": 64, "height": 64, "duration": 1.0, "fps": 24, "library": ["models": ["subject": model.path]]]
                try JSONSerialization.data(withJSONObject: job).write(to: folder.appendingPathComponent("job.json"))
            } catch { reply["status"] = "inspectFailed"; reply["message"] = error.localizedDescription; return }
            let task = Process(), pipe = Pipe()
            let args = ["-b", "--factory-startup", "-noaudio", "-Y", "--python-exit-code", "3", "-P", driver.path, "--", folder.appendingPathComponent("job.json").path]
            if self.useSandbox { task.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec"); task.arguments = ["-p", Self.sandboxProfile(job: folder, home: self.home), Self.executable(found.app).path] + args }
            else { task.executableURL = Self.executable(found.app); task.arguments = args }
            task.standardOutput = pipe; task.standardError = pipe
            guard (try? task.run()) != nil else { reply["status"] = "inspectFailed"; reply["message"] = "Không mở được Blender."; return }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); task.waitUntilExit()
            if let line = output.split(separator: "\n").first(where: { $0.hasPrefix("SU_MEASURE ") }),
               let info = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(11).utf8))) as? [String: Any] {
                reply.merge(info) { $1 }
            } else {
                reply["status"] = "inspectFailed"
                reply["message"] = output.split(separator: "\n").last(where: { $0.hasPrefix("SU_ERROR ") }).map { String($0.dropFirst(9)) } ?? "Blender không đọc được model."
            }
        }
    }

    /// Sorted PNG frames → H.264 MP4. Returns the clip length in seconds.
    /// Film looks applied while assembling: grain, softer colour, vignette. Same result for previews and clips.
    static func graded(_ image: CGImage, look: String, frame: Int, context: CIContext) -> CGImage {
        guard look != "none" else { return image }
        var picture = CIImage(cgImage: image)
        let extent = picture.extent
        let (saturation, contrast, vignette, grain): (Double, Double, Double, Double) = look == "film35" ? (0.72, 1.06, 0.7, 0.10) : look == "bleach" ? (0.42, 1.22, 0.6, 0.08) : (1.12, 1.16, 0.45, 0.0)
        picture = picture.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast])
        if look == "film35" {
            // Slightly cool shadows, warm highlights, lifted blacks.
            picture = picture.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.96, y: 0.02, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.98, z: 0.02, w: 0),
                                                                           "inputBVector": CIVector(x: 0, y: 0.04, z: 0.92, w: 0), "inputBiasVector": CIVector(x: 0.025, y: 0.025, z: 0.03, w: 0)])
        }
        picture = picture.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: vignette, kCIInputRadiusKey: 1.6])
        if grain > 0, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let shifted = noise.transformed(by: CGAffineTransform(translationX: CGFloat((frame * 97) % 900), y: CGFloat((frame * 53) % 900))).cropped(to: extent)
            let gray = shifted.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: grain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: grain, y: 0, z: 0, w: 0),
                                                                             "inputBVector": CIVector(x: grain, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                                                                             "inputBiasVector": CIVector(x: 0.5 - grain / 2, y: 0.5 - grain / 2, z: 0.5 - grain / 2, w: 0)])
            picture = gray.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: picture])
        }
        return context.createCGImage(picture.cropped(to: extent), from: extent) ?? image
    }

    static func assemble(frames: URL, fps: Int, to output: URL, look: String = "none") throws -> Double {
        let grader = CIContext(options: [.cacheIntermediates: false])
        let files = ((try? FileManager.default.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = files.first, let probe = NSImage(contentsOf: first)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "BlenderRender", code: 2, userInfo: [NSLocalizedDescriptionKey: "Blender không xuất ra khung hình nào."]) }
        let width = probe.width / 2 * 2, height = probe.height / 2 * 2
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 6]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "BlenderRender", code: 3) }
        writer.startSession(atSourceTime: .zero)
        for (index, file) in files.enumerated() {
            try autoreleasepool {
                guard let source = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                let image = graded(source, look: look, frame: index, context: grader)
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixel = buffer else { throw NSError(domain: "BlenderRender", code: 4, userInfo: [NSLocalizedDescriptionKey: "Không tạo được khung video."]) }
                CVPixelBufferLockBaseAddress(pixel, [])
                let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
                ctx?.setFillColor(NSColor.black.cgColor); ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(pixel, [])
                if !adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: CMTimeScale(fps))) { throw writer.error ?? NSError(domain: "BlenderRender", code: 5) }
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }; done.wait()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "BlenderRender", code: 6, userInfo: [NSLocalizedDescriptionKey: "Ghép video thất bại."]) }
        return Double(files.count) / Double(fps)
    }
}
