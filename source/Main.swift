import Cocoa
import WebKit
import Security

final class Studio: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    lazy var codex = CodexConnection(root: root)
    let plenxProbe = PlenXProbe()
    let elevenProbe = ElevenLabsProbe()
    lazy var tts = ElevenLabsTTS(root: root)
    lazy var narration = NarrationPlayer(root: root)
    lazy var updater = AppUpdater(root: root)
    let credentials = CredentialStore()
    private var credentialRevisions: [String: Int] = [:]
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HistoryStudio", isDirectory: true)
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        codex.onUpdate = { [weak self] update in self?.reply(update, "nativeCodex") }
        codex.onAssistant = { [weak self] update in self?.reply(update, "nativeAssistant") }
        codex.onModels = { [weak self] update in self?.reply(update, "nativeModels") }
        updater.onUpdate = { [weak self] update in self?.reply(update, "nativeUpdate") }
        narration.onUpdate = { [weak self] update in self?.reply(update, "nativeNarration") }
        tts.onUpdate = { [weak self] update in self?.reply(update, "nativeTTS") }
        plenxProbe.onUpdate = { [weak self] update in self?.reply(update, "nativePlenxTest") }
        elevenProbe.onUpdate = { [weak self] update in self?.reply(update, "nativeElevenTest") }
        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sử Studio"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 1040, height: 680)
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let sub = NSMenu(); sub.addItem(withTitle: "Thoát Sử Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = sub
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: "Chỉnh sửa")
        for (title, action, key) in [
            ("Hoàn tác", "undo:", "z"),
            ("Làm lại", "redo:", "Z"),
            ("Cắt", "cut:", "x"),
            ("Sao chép", "copy:", "c"),
            ("Dán", "paste:", "v"),
            ("Chọn tất cả", "selectAll:", "a")
        ] {
            let command = edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
            command.target = nil // Route through the active WebKit text editor / responder chain.
        }
        editItem.submenu = edit
        NSApp.mainMenu = menu
        window.makeFirstResponder(web)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard tts.busy else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "ElevenLabs đang tạo hoặc tải dữ liệu"
        alert.informativeText = "Đợi hoàn tất để audio được lưu trên máy. Đóng ngay có thể mất kết quả nhưng vẫn dùng credit."
        alert.addButton(withTitle: "Tiếp tục đợi"); alert.addButton(withTitle: "Đóng app")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { codex.stop(); plenxProbe.cancel(); elevenProbe.cancel(); narration.stop() }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Đồng ý")
        alert.addButton(withTitle: "Hủy")
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }
    func reply(_ value: Any, _ function: String = "nativeResult") {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.\(function)(\(json))", completionHandler: nil)
    }
    func editText(_ body: [String: Any]) {
        guard let requestID = body["requestId"] as? String, let text = body["text"] as? String else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 490), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        panel.title = "Soạn văn bản tiếng Việt"
        panel.minSize = NSSize(width: 540, height: 350)
        let content = panel.contentView!
        let label = NSTextField(labelWithString: body["title"] as? String ?? "Nội dung")
        label.frame = NSRect(x: 20, y: 450, width: 720, height: 24)
        label.autoresizingMask = [.width, .minYMargin]
        content.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 64, width: 720, height: 376))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.font = NSFont.systemFont(ofSize: 16)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        content.addSubview(scroll)
        let apply = NSButton(title: "Áp dụng", target: nil, action: nil)
        let cancel = NSButton(title: "Hủy", target: nil, action: nil)
        apply.frame = NSRect(x: 630, y: 16, width: 110, height: 32)
        cancel.frame = NSRect(x: 510, y: 16, width: 110, height: 32)
        apply.autoresizingMask = [.minXMargin, .maxYMargin]
        cancel.autoresizingMask = [.minXMargin, .maxYMargin]
        cancel.keyEquivalent = "\u{1b}"
        let handler = TextEditorActions()
        handler.apply = { [weak self] in
            self?.window.endSheet(panel)
            self?.reply(["requestId": requestID, "accepted": true, "text": editor.string], "nativeTextEdited")
        }
        handler.cancel = { [weak self] in
            self?.window.endSheet(panel)
            self?.reply(["requestId": requestID, "accepted": false], "nativeTextEdited")
        }
        apply.target = handler; apply.action = #selector(TextEditorActions.accept)
        cancel.target = handler; cancel.action = #selector(TextEditorActions.dismiss)
        content.addSubview(apply); content.addSubview(cancel)
        window.beginSheet(panel) { _ in withExtendedLifetime(handler) {} }
        panel.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "updateToken":
            if let token = body["token"] as? String {
                credentials.save("github", value: token) { [weak self] result in
                    self?.reply(result, "nativeUpdateToken")
                }
            }
        case "updateCheck", "updateDownload":
            credentials.read("github") { [weak self] result in
                guard let self = self else { return }
                let token: String?; if case .success(let value) = result { token = value } else { token = nil }
                if action == "updateCheck" { self.updater.check(token: token) } else { self.updater.download(token: token) }
            }
        case "updateInstall":
            guard !tts.busy, !codex.isGenerating else {
                reply(["status": "ready", "message": "Đợi AI/TTS hoàn tất trước khi cài cập nhật."], "nativeUpdate"); return
            }
            let alert = NSAlert(); alert.messageText = "Cài cập nhật và khởi động lại Sử Studio?"
            alert.informativeText = "App sẽ đóng, thay phiên bản và mở lại. Dữ liệu dự án và Keychain được giữ."
            alert.addButton(withTitle: "Cài và mở lại"); alert.addButton(withTitle: "Để sau")
            if alert.runModal() == .alertFirstButtonReturn { updater.install() }
        case "copyPrompt":
            if let text = body["text"] as? String, text.count <= 50000 {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                reply(["copied": true])
            }
        case "narration": narration.command(body)
        case "tts":
            credentials.read("elevenlabs") { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let key): self.tts.request(body, key: key)
                case .failure(let error):
                    var payload = error.payload; payload["requestId"] = body["requestId"]
                    self.reply(payload, "nativeTTS")
                }
            }
        case "editText": editText(body)
        case "codexModels": codex.loadModels()
        case "codexSelectModel":
            if let model = body["model"] as? String, let effort = body["effort"] as? String { codex.chooseModel(model, effort: effort) }
        case "openLink":
            if let raw = body["url"] as? String, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case "assistantGenerate": codex.generateAssistant(body)
        case "assistantCancel": codex.interruptAssistant()
        case "plenxTest", "elevenTest":
            let provider = action == "plenxTest" ? "plenx" : "elevenlabs"
            let name = provider == "plenx" ? "PlenX" : "ElevenLabs"
            let callback = provider == "plenx" ? "nativePlenxTest" : "nativeElevenTest"
            let revision = credentialRevisions[provider, default: 0]
            reply(["status": "checking", "stage": "keychainRead", "message": "Đang đọc key \(name) đã lưu trong Keychain…"], callback)
            credentials.read(provider) { [weak self] result in
                guard let self = self, self.credentialRevisions[provider, default: 0] == revision else { return }
                switch result {
                case .success(let key):
                    if provider == "plenx" { self.plenxProbe.test(key: key) } else { self.elevenProbe.test(key: key) }
                case .failure(let error): self.reply(error.payload, callback)
                }
            }
        case "codexStatus": codex.refresh()
        case "codexLogin": codex.login()
        case "codexCancel": codex.cancel()
        case "codexReopen": codex.reopen()
        case "codexLogout": codex.logout()
        case "load":
            let data = (try? Data(contentsOf: root.appendingPathComponent("projects.json"))) ?? Data("null".utf8)
            let state = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
            let demoData = Bundle.main.url(forResource: "demo", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            let demo = demoData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
            credentials.existingProviders { [weak self] keys in self?.reply(["state": state, "demo": demo, "keys": keys], "nativeLoaded") }
        case "save":
            do {
                if let state = body["state"] { let data = try JSONSerialization.data(withJSONObject: state); try data.write(to: root.appendingPathComponent("projects.json"), options: .atomic) }
                reply(["saved": true])
            } catch { reply(["error": "Không lưu được dự án: \(error.localizedDescription)"]) }
        case "key":
            guard let provider = body["provider"] as? String, ["elevenlabs", "plenx"].contains(provider), let key = body["key"] as? String, !key.isEmpty else { return }
            credentialRevisions[provider, default: 0] += 1
            if provider == "plenx" { plenxProbe.cancel() } else { elevenProbe.cancel() }
            credentials.save(provider, value: key) { [weak self] result in self?.reply(result, "nativeCredential") }
        case "import":
            let panel = NSOpenPanel(); panel.allowedFileTypes = ["xlsx"]; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let file = panel.url, let script = Bundle.main.path(forResource: "import_storyboard", ofType: "py") else { return }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); task.arguments = [script, file.path]
            let pipe = Pipe(); let err = Pipe(); task.standardOutput = pipe; task.standardError = err
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                if task.terminationStatus == 0, let object = try? JSONSerialization.jsonObject(with: data) { reply(object, "nativeImported") }
                else { reply(["error": "Không đọc được storyboard. Cần các cột Cảnh, Thời gian, Voice-over và prompt."]) }
            } catch { reply(["error": error.localizedDescription]) }
        case "asset":
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let file = panel.url, let request = body["request"] as? [String: Any] else { return }
            do {
                if request["kind"] as? String == "image", NSImage(contentsOf: file) == nil {
                    reply(["error": "File đã chọn không phải ảnh đọc được. Hãy chọn PNG, JPEG, WebP hoặc HEIC hợp lệ."]); return
                }
                let folder = root.appendingPathComponent("assets", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(UUID().uuidString + "-" + file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: dest)
                reply(["request": request, "path": dest.path, "name": file.lastPathComponent], "nativeAsset")
            } catch { reply(["error": "Không nhập được tài nguyên: \(error.localizedDescription)"]) }
        case "openAsset":
            if let path = body["path"] as? String, path.hasPrefix(root.appendingPathComponent("assets").path + "/") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case "export":
            guard let project = body["project"] as? [String: Any] else { return }
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let parent = panel.url else { return }
            do {
                let folder = parent.appendingPathComponent("SuStudio-" + String(UUID().uuidString.prefix(8)), isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: project, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("project.json"))
                let scenes = project["scenes"] as? [[String: Any]] ?? []
                var script = ""; var timeline = "CẢNH\tTHỜI GIAN\tCHƯƠNG\n"
                for (i, scene) in scenes.enumerated() {
                    let sceneDir = folder.appendingPathComponent(String(format: "%03d", i + 1), isDirectory: true); try FileManager.default.createDirectory(at: sceneDir, withIntermediateDirectories: true)
                    script += "\nCảnh \(i + 1) — \(scene["time"] as? String ?? "")\n\(scene["voice"] as? String ?? "")\n"
                    timeline += "\(i + 1)\t\(scene["time"] as? String ?? "")\t\(scene["chapter"] as? String ?? "")\n"
                    try JSONSerialization.data(withJSONObject: scene, options: [.prettyPrinted]).write(to: sceneDir.appendingPathComponent("scene.json"))
                    let assets = scene["assets"] as? [String: [[String: Any]]] ?? [:]
                    for (kind, versions) in assets {
                        for (v, asset) in versions.enumerated() {
                            if let path = asset["path"] as? String, path.hasPrefix(root.appendingPathComponent("assets").path + "/") {
                                let url = URL(fileURLWithPath: path)
                                let selected = asset["selected"] as? Bool == true ? "-SELECTED" : ""
                                try FileManager.default.copyItem(at: url, to: sceneDir.appendingPathComponent("\(kind)-v\(v + 1)\(selected).\(url.pathExtension)"))
                            }
                        }
                    }
                }
                try script.write(to: folder.appendingPathComponent("voiceover.txt"), atomically: true, encoding: .utf8)
                try timeline.write(to: folder.appendingPathComponent("timeline.tsv"), atomically: true, encoding: .utf8)
                try "Gói tài nguyên để nhập thủ công vào CapCut, không phải project CapCut. Mỗi thư mục là một cảnh; SELECTED là tài nguyên được chọn. Thời gian lấy từ storyboard, cần căn chỉnh theo audio thực tế.\n".write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(folder); reply(["exported": true])
            } catch { reply(["error": "Xuất thất bại: \(error.localizedDescription)"]) }
        default: break
        }
    }
}
final class TextEditorActions: NSObject {
    var apply: (() -> Void)?
    var cancel: (() -> Void)?
    @objc func accept() { apply?() }
    @objc func dismiss() { cancel?() }
}
@main enum HistoryStudioApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = Studio()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
