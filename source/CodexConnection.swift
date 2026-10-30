import Cocoa

/// Public account and generation RPCs. Tokens stay inside Codex/Keychain.
final class CodexConnection {
    var onUpdate: (([String: Any]) -> Void)?
    var onAssistant: (([String: Any]) -> Void)?
    var onModels: (([String: Any]) -> Void)?
    private var models: [[String: Any]] = []
    private var loadingModels = false
    private var selectedModel = ""
    private var selectedEffort = ""
    private var selectionURL: URL { home.deletingLastPathComponent().appendingPathComponent("model-selection.json") }
    private var startupCompletions: [() -> Void] = []
    private struct AssistantJob {
        let requestID: String
        let projectID: String
        let stage: String
        var threadID: String?
        var turnID: String?
        var finalText = ""
        var model = ""
        var effort = ""
    }
    var isGenerating: Bool { assistantJob != nil }
    private var assistantJob: AssistantJob?
    private var lastAssistantProgress = ""
    private var assistantProgress: AssistantProgress?
    private var progressTimer: Timer?
    private var lastPingAt: TimeInterval = 0
    private var pingPending = false
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var callbacks: [Int: ([String: Any]) -> Void] = [:]
    private var ready = false
    private var loginID: String?
    private var authURL: URL?
    private var snapshot: [String: Any] = ["status": "idle"]
    private let home: URL
    init(root: URL) {
        home = root.appendingPathComponent("codex", isDirectory: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent("model-selection.json")), let choice = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] { selectedModel = choice["model"] ?? ""; selectedEffort = choice["effort"] ?? "" }
    }
    private func emitModels(_ status: String = "ready", message: String = "") {
        onModels?(["status": status, "models": models, "selectedModel": selectedModel, "selectedEffort": selectedEffort, "message": message])
    }
    func loadModels() {
        guard !loadingModels else { return }
        loadingModels = true; emitModels("loading")
        start { [weak self] in self?.modelPage(cursor: nil, collected: [], seen: []) }
        if process == nil { loadingModels = false; emitModels("error", message: "Chưa mở được Codex để lấy danh sách model.") }
    }
    private func modelPage(cursor: String?, collected: [[String: Any]], seen: Set<String>) {
        var params: [String: Any] = ["limit": 100, "includeHidden": false]
        if let cursor = cursor { params["cursor"] = cursor }
        request("model/list", params) { [weak self] response in
            guard let self = self else { return }
            guard let result = response["result"] as? [String: Any], let rows = result["data"] as? [[String: Any]] else {
                self.loadingModels = false; self.emitModels("error", message: "Không lấy được danh sách model. Hãy đăng nhập và thử lại."); return
            }
            let all = collected + rows
            if let next = result["nextCursor"] as? String, !next.isEmpty {
                guard !seen.contains(next), seen.count < 20 else { self.loadingModels = false; self.emitModels("error", message: "Danh sách model phân trang không hợp lệ. Hãy thử lại."); return }
                self.modelPage(cursor: next, collected: all, seen: seen.union([next])); return
            }
            var ids = Set<String>()
            self.models = all.compactMap { row in
                guard let model = row["model"] as? String, !model.isEmpty, row["hidden"] as? Bool != true, ids.insert(model).inserted else { return nil }
                if let modalities = row["inputModalities"] as? [String], !modalities.contains("text") { return nil }
                let efforts = (row["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { option -> [String: String]? in
                    guard let effort = option["reasoningEffort"] as? String, !effort.isEmpty else { return nil }
                    return ["reasoningEffort": effort, "description": option["description"] as? String ?? ""]
                }
                return ["model": model, "displayName": row["displayName"] as? String ?? model, "description": row["description"] as? String ?? "", "efforts": efforts, "defaultEffort": row["defaultReasoningEffort"] as? String ?? "", "isDefault": row["isDefault"] as? Bool ?? false]
            }
            self.loadingModels = false
            self.emitModels(self.models.isEmpty ? "error" : "ready", message: self.models.isEmpty ? "Codex chưa trả về model hỗ trợ văn bản." : "")
        }
    }
    func chooseModel(_ model: String, effort: String) {
        if model.isEmpty {
            guard effort.isEmpty else { emitModels("error", message: "Chọn model trước khi chọn mức suy luận."); return }
        } else {
            guard let entry = models.first(where: { $0["model"] as? String == model }) else { emitModels("error", message: "Model không còn trong danh sách. Làm mới và chọn lại."); return }
            let supported = entry["efforts"] as? [[String: String]] ?? []
            guard effort.isEmpty || supported.contains(where: { $0["reasoningEffort"] == effort }) else { emitModels("error", message: "Mức suy luận không được model hỗ trợ."); return }
        }
        do {
            try JSONSerialization.data(withJSONObject: ["model": model, "effort": effort]).write(to: selectionURL, options: .atomic)
            selectedModel = model; selectedEffort = effort; emitModels("ready", message: "Đã lưu. Áp dụng từ lượt AI tiếp theo.")
        } catch { emitModels("error", message: "Không lưu được lựa chọn model trên máy.") }
    }
    static func executable() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    private func publish(_ changes: [String: Any]) {
        snapshot.merge(changes) { _, new in new }
        onUpdate?(snapshot)
    }
    func refresh() {
        guard loginID == nil else { onUpdate?(snapshot); return }
        start { [weak self] in self?.readAccount() }
    }
    private func start(_ completion: @escaping () -> Void) {
        if ready { completion(); return }
        if process != nil { startupCompletions.append(completion); onUpdate?(snapshot); return }
        guard let binary = Self.executable() else {
            publish(["status": "missing", "message": "Không tìm thấy Codex CLI. Cài hoặc cập nhật ứng dụng ChatGPT/Codex rồi thử lại."])
            return
        }
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let task = Process(), stdin = Pipe(), stdout = Pipe()
            task.executableURL = binary
            task.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"keyring\""]
            var environment = ProcessInfo.processInfo.environment
            // Configure the child's documented Codex home, isolated from the user's other clients.
            environment["CODEX_HOME"] = home.path
            for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL"] { environment.removeValue(forKey: key) }
            task.environment = environment
            task.currentDirectoryURL = home
            task.standardInput = stdin; task.standardOutput = stdout
            // Do not log OAuth URLs or token-bearing diagnostics into the project.
            task.standardError = FileHandle.nullDevice
            input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
            buffer = Data(); process = task
            output?.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                DispatchQueue.main.async { self?.consume(data) }
            }
            task.terminationHandler = { [weak self] task in
                DispatchQueue.main.async {
                    guard let self = self, self.process === task else { return }
                    self.clearTransport()
                    self.publish(["status": "error", "message": "Codex đã dừng. Bấm Thử lại để kết nối lại."])
                    self.finishAssistant(status: "error", message: "Kết nối Codex bị ngắt. Bản nháp trước đó vẫn được giữ; bạn có thể thử lại.")
                }
            }
            publish(["status": "starting", "message": "Đang khởi động Codex…"])
            try task.run()
            request("initialize", ["clientInfo": ["name": "su_studio", "title": "Sử Studio", "version": "0.2.0"]]) { [weak self] response in
                guard let self = self else { return }
                guard response["error"] == nil else { self.fail("Không khởi tạo được Codex. Hãy cập nhật ChatGPT/Codex và thử lại."); return }
                self.write(["method": "initialized"])
                self.ready = true
                completion()
                let waiting = self.startupCompletions; self.startupCompletions.removeAll()
                waiting.forEach { $0() }
            }
        } catch { fail("Không mở được Codex: \(error.localizedDescription)") }
    }
    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let handle = input else { return }
        do { try handle.write(contentsOf: data + Data([10])) }
        catch { fail("Mất kết nối với Codex. Hãy thử lại.") }
    }
    private func request(_ method: String, _ params: [String: Any] = [:], completion: @escaping ([String: Any]) -> Void) {
        sequence += 1; let id = sequence
        callbacks[id] = completion
        write(["id": id, "method": method, "params": params])
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let callback = self?.callbacks.removeValue(forKey: id) else { return }
            callback(["error": ["message": "Codex không phản hồi trong 30 giây."]])
        }
    }
    private func consume(_ data: Data) {
        if data.isEmpty { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: 0..<newline); buffer.removeSubrange(0...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            assistantProgress?.transportReply()
            if let id = message["id"] as? Int, let callback = callbacks.removeValue(forKey: id) { callback(message); continue }
            guard let method = message["method"] as? String else { continue }
            if let serverID = message["id"] {
                write(["id": serverID, "error": ["code": -32601, "message": "Sử Studio does not support client tool execution or permission grants."]]); continue
            }
            let params = message["params"] as? [String: Any] ?? [:]
            receiveAssistantEvent(method, params)
            if method == "account/login/completed" {
                guard let current = loginID, params["loginId"] as? String == current else { continue }
                loginID = nil; authURL = nil
                if params["success"] as? Bool == true { readAccount() }
                else { publish(["status": "error", "message": "Đăng nhập chưa hoàn tất hoặc đã hết hạn. Bạn có thể thử lại."]) }
            } else if method == "account/updated", loginID == nil { readAccount() }
            else if method == "account/rateLimits/updated" { publish(["limits": sanitizedLimits(params)]) }
        }
    }
    func login() {
        guard loginID == nil else { reopen(); return }
        start { [weak self] in
            guard let self = self else { return }
            self.publish(["status": "starting", "message": "Đang chuẩn bị đăng nhập…"])
            self.request("account/login/start", ["type": "chatgpt"]) { [weak self] response in
                guard let self = self else { return }
                guard let result = response["result"] as? [String: Any], let id = result["loginId"] as? String,
                      let raw = result["authUrl"] as? String, let url = URL(string: raw), url.scheme == "https",
                      ["auth.openai.com", "chatgpt.com", "auth0.openai.com"].contains(url.host?.lowercased() ?? "") else {
                    self.publish(["status": "error", "message": "Không bắt đầu được đăng nhập. Có thể cổng đăng nhập đang bận; đóng trang đăng nhập Codex khác rồi thử lại."]); return
                }
                self.loginID = id; self.authURL = url
                self.publish(["status": "waiting", "message": "Hoàn tất đăng nhập trong trình duyệt. App sẽ tự cập nhật khi thành công."])
                if !NSWorkspace.shared.open(url) { self.publish(["message": "Không mở được trình duyệt. Bấm Mở lại trang đăng nhập để thử lại."]) }
            }
        }
    }
    func reopen() { if let url = authURL { NSWorkspace.shared.open(url) } }
    func cancel() {
        guard let id = loginID else { return }
        loginID = nil; authURL = nil
        request("account/login/cancel", ["loginId": id]) { [weak self] _ in self?.readAccount() }
        publish(["status": "checking", "message": "Đang hủy đăng nhập…"])
    }
    func logout() {
        guard ready, loginID == nil else { return }
        publish(["status": "checking", "message": "Đang đăng xuất Sử Studio…"])
        request("account/logout") { [weak self] response in
            guard let self = self else { return }
            if response["error"] != nil { self.publish(["status": "error", "message": "Chưa đăng xuất được. Hãy thử lại."]) }
            else { self.readAccount() }
        }
    }
    private func readAccount() {
        publish(["status": "checking", "message": "Đang kiểm tra tài khoản…"])
        request("account/read", ["refreshToken": false]) { [weak self] response in
            guard let self = self else { return }
            guard let result = response["result"] as? [String: Any] else {
                self.publish(["status": "error", "message": "Chưa đọc được trạng thái tài khoản. Hãy thử lại."]); return
            }
            guard let account = result["account"] as? [String: Any], ["chatgpt", "chatgptAuthTokens"].contains(account["type"] as? String ?? "") else {
                self.publish(["status": "signedOut", "message": "Đăng nhập bằng tài khoản ChatGPT để kết nối Codex.", "email": NSNull(), "plan": NSNull(), "limits": []]); return
            }
            self.publish(["status": "signedIn", "message": "Đã đăng nhập Codex bằng ChatGPT.", "email": account["email"] as? String ?? "", "plan": account["planType"] as? String ?? "", "limits": []])
            self.loadModels()
            self.request("account/rateLimits/read") { [weak self] response in
                guard let self = self, self.snapshot["status"] as? String == "signedIn" else { return }
                if let result = response["result"] as? [String: Any] { self.publish(["limits": self.sanitizedLimits(result)]) }
            }
        }
    }
    private func sanitizedLimits(_ result: [String: Any]) -> [[String: Any]] {
        let buckets: [[String: Any]]
        if let map = result["rateLimitsByLimitId"] as? [String: [String: Any]], !map.isEmpty { buckets = map.keys.sorted().compactMap { map[$0] } }
        else if let bucket = result["rateLimits"] as? [String: Any] { buckets = [bucket] }
        else { return [] }
        return buckets.flatMap { bucket -> [[String: Any]] in
            ["primary", "secondary"].compactMap { name in
                guard let window = bucket[name] as? [String: Any], let used = window["usedPercent"] as? Double else { return nil }
                return ["name": bucket["limitName"] as? String ?? bucket["limitId"] as? String ?? "Codex", "used": min(100, max(0, used)), "minutes": window["windowDurationMins"] ?? NSNull(), "resetsAt": window["resetsAt"] ?? NSNull()]
            }
        }
    }
    private func fail(_ message: String) { finishAssistant(status: "error", message: message); stop(); publish(["status": "error", "message": message]) }
    private func clearTransport() {
        output?.readabilityHandler = nil; output = nil; input = nil; process = nil
        ready = false; callbacks.removeAll(); loginID = nil; authURL = nil; buffer = Data()
        loadingModels = false
        startupCompletions.removeAll()
    }
    func stop() { finishAssistant(status: "interrupted", message: "Đã dừng trợ lý AI."); let task = process; clearTransport(); if task?.isRunning == true { task?.terminate() } }
    func generateAssistant(_ payload: [String: Any]) {
        guard let requestID = payload["requestId"] as? String, let projectID = payload["projectId"] as? String,
              let stage = payload["stage"] as? String, AssistantPlan.stages.contains(stage), let context = payload["context"] as? [String: Any] else { return }
        guard assistantJob == nil else {
            onAssistant?(["requestId": requestID, "projectId": projectID, "stage": stage, "status": "error", "message": "Một yêu cầu AI khác đang chạy. Hãy đợi hoặc dừng yêu cầu đó trước."]); return
        }
        if !selectedModel.isEmpty && !models.isEmpty {
            guard let entry = models.first(where: { $0["model"] as? String == selectedModel }), selectedEffort.isEmpty || (entry["efforts"] as? [[String: String]] ?? []).contains(where: { $0["reasoningEffort"] == selectedEffort }) else {
                onAssistant?(["requestId": requestID, "projectId": projectID, "stage": stage, "status": "error", "message": "Model hoặc mức suy luận đã lưu không còn trong danh sách. Vào Kết nối dịch vụ để chọn lại."]); return
            }
        }
        assistantJob = AssistantJob(requestID: requestID, projectID: projectID, stage: stage)
        assistantJob?.model = selectedModel; assistantJob?.effort = selectedEffort
        assistantProgress = AssistantProgress()
        beginProgressTimer()
        lastAssistantProgress = ""
        emitAssistant("running", "Đang kết nối tài khoản ChatGPT…")
        start { [weak self] in
            guard let self = self, self.assistantJob?.requestID == requestID else { return }
            self.request("account/read", ["refreshToken": false]) { [weak self] response in
                guard let self = self, self.assistantJob?.requestID == requestID else { return }
                let account = (response["result"] as? [String: Any])?["account"] as? [String: Any]
                guard ["chatgpt", "chatgptAuthTokens"].contains(account?["type"] as? String ?? "") else {
                    self.finishAssistant(status: "error", message: "Hãy đăng nhập ChatGPT trong Kết nối dịch vụ trước khi dùng trợ lý."); return
                }
                self.startAssistantThread(stage: stage, context: context, requestID: requestID)
            }
        }
        if ["missing", "error"].contains(snapshot["status"] as? String ?? ""), process == nil {
            finishAssistant(status: "error", message: snapshot["message"] as? String ?? "Chưa kết nối được Codex.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { [weak self] in
            guard let self = self, self.assistantJob?.requestID == requestID else { return }
            self.interruptAssistant()
        }
    }
    private func startAssistantThread(stage: String, context: [String: Any], requestID: String) {
        let workspace = home.deletingLastPathComponent().appendingPathComponent("assistant-workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        emitAssistant("running", stage == "research" ? "AI đang đối chiếu tư liệu và chuẩn bị bản nghiên cứu…" : "AI đang chuẩn bị gợi ý cho bước này…")
        let config: [String: Any] = ["web_search": stage == "research" ? "live" : "disabled", "features.shell_tool": false, "features.multi_agent": false]
        var threadParams: [String: Any] = ["cwd": workspace.path, "sandbox": "read-only", "approvalPolicy": "never", "ephemeral": true, "config": config, "baseInstructions": AssistantPlan.instructions]
        if let model = assistantJob?.model, !model.isEmpty { threadParams["model"] = model }
        request("thread/start", threadParams) { [weak self] response in
            guard let self = self else { return }
            guard self.assistantJob?.requestID == requestID else {
                if let threadID = ((response["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String { self.request("thread/unsubscribe", ["threadId": threadID]) { _ in } }
                return
            }
            guard let result = response["result"] as? [String: Any], let thread = result["thread"] as? [String: Any], let threadID = thread["id"] as? String else {
                self.finishAssistant(status: "error", message: "Không mở được phiên AI. Hãy kiểm tra kết nối Codex và thử lại."); return
            }
            self.assistantJob?.threadID = threadID
            if let actual = result["model"] as? String { self.assistantJob?.model = actual }
            if self.assistantJob?.effort.isEmpty == true, let effort = result["reasoningEffort"] as? String { self.assistantJob?.effort = effort }
            var turnParams: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": AssistantPlan.prompt(stage: stage, context: context)]], "outputSchema": AssistantPlan.schema, "summary": "concise", "sandboxPolicy": ["type": "readOnly", "networkAccess": false], "approvalPolicy": "never"]
            if let model = self.assistantJob?.model, !model.isEmpty { turnParams["model"] = model }
            if let effort = self.assistantJob?.effort, !effort.isEmpty { turnParams["effort"] = effort }
            self.request("turn/start", turnParams) { [weak self] response in
                guard let self = self else { return }
                guard self.assistantJob?.requestID == requestID else {
                    if let turnID = ((response["result"] as? [String: Any])?["turn"] as? [String: Any])?["id"] as? String { self.request("turn/interrupt", ["threadId": threadID, "turnId": turnID]) { _ in } }
                    return
                }
                guard let turn = (response["result"] as? [String: Any])?["turn"] as? [String: Any], let turnID = turn["id"] as? String else {
                    self.finishAssistant(status: "error", message: "Codex chưa bắt đầu được tác vụ. Kiểm tra hạn mức hoặc đăng nhập lại rồi thử lại."); return
                }
                self.assistantJob?.turnID = turnID
            }
        }
    }
    private func receiveAssistantEvent(_ method: String, _ params: [String: Any]) {
        guard let job = assistantJob, let threadID = job.threadID, params["threadId"] as? String == threadID else { return }
        assistantProgress?.received(method, params)
        if method == "turn/started", let turn = params["turn"] as? [String: Any] { assistantJob?.turnID = turn["id"] as? String }
        if method == "item/started", let item = params["item"] as? [String: Any], item["type"] as? String == "webSearch" {
            emitAssistant("running", "AI đang tìm và đối chiếu nguồn trên web…")
        }
        if method == "item/agentMessage/delta" { emitAssistant("running", "AI đang soạn nội dung. Bạn có thể dừng nếu cần.") }
        if method == "item/reasoning/summaryTextDelta" { emitAssistant("running", "Codex đang chuẩn bị nội dung; có tóm tắt tiến trình để xem.") }
        if method == "item/completed", let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage", let text = item["text"] as? String, !text.isEmpty {
            assistantJob?.finalText = text
        }
        guard method == "turn/completed", let turn = params["turn"] as? [String: Any] else { return }
        if let expected = job.turnID, let actual = turn["id"] as? String, expected != actual { return }
        if turn["status"] as? String == "completed" {
            assistantProgress?.phase = "validating"
            if let data = assistantJob?.finalText.data(using: .utf8), let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], AssistantPlan.isValid(result, stage: job.stage) {
                finishAssistant(status: "completed", message: "Bản nháp đã sẵn sàng để bạn xem và duyệt.", result: result)
            } else { finishAssistant(status: "error", message: "AI trả về nội dung chưa đúng cấu trúc. Bản đã duyệt vẫn được giữ; hãy thử tạo lại.") }
        } else { finishAssistant(status: "error", message: turn["status"] as? String == "interrupted" ? "Đã dừng yêu cầu AI. Bạn có thể tạo lại khi sẵn sàng." : "AI chưa hoàn tất. Có thể kết nối hoặc hạn mức đang bị giới hạn; hãy thử lại.") }
    }
    private func emitAssistant(_ status: String, _ message: String, result: [String: Any]? = nil, force: Bool = false) {
        guard let job = assistantJob else { return }
        if status == "running" {
            if lastAssistantProgress == message && !force { return }
            lastAssistantProgress = message
        }
        var update: [String: Any] = ["requestId": job.requestID, "projectId": job.projectID, "stage": job.stage, "status": status, "message": message, "model": job.model, "effort": job.effort]
        if let result = result { update["result"] = result }
        if let progress = assistantProgress { update["progress"] = progress.snapshot() }
        onAssistant?(update)
    }
    private func finishAssistant(status: String, message: String, result: [String: Any]? = nil) {
        let threadID = assistantJob?.threadID
        progressTimer?.invalidate(); progressTimer = nil
        assistantProgress?.phase = status == "completed" ? "finished" : "stopped"
        emitAssistant(status, message, result: result); assistantJob = nil
        assistantProgress = nil; pingPending = false
        if ready, let threadID = threadID { request("thread/unsubscribe", ["threadId": threadID]) { _ in } }
    }
    func interruptAssistant() {
        guard let job = assistantJob else { return }
        if let threadID = job.threadID, let turnID = job.turnID { request("turn/interrupt", ["threadId": threadID, "turnId": turnID]) { _ in } }
        finishAssistant(status: "interrupted", message: "Đã dừng yêu cầu. Nội dung đã duyệt vẫn được giữ.")
    }
    private func beginProgressTimer() {
        progressTimer?.invalidate(); lastPingAt = 0; pingPending = false
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self, let job = self.assistantJob else { return }
            if self.process?.isRunning != true { self.assistantProgress?.connection = self.process == nil ? "checking" : "stopped" }
            let now = Date().timeIntervalSince1970
            if self.ready && !self.pingPending && now - self.lastPingAt >= 20 {
                self.lastPingAt = now; self.pingPending = true
                let requestID = job.requestID
                self.request("account/read", ["refreshToken": false]) { [weak self] response in
                    guard let self = self, self.assistantJob?.requestID == requestID else { return }
                    self.pingPending = false
                    if response["error"] == nil { self.assistantProgress?.transportReply() }
                    else { self.assistantProgress?.connection = "unresponsive" }
                }
            }
            self.emitAssistant("running", self.lastAssistantProgress.isEmpty ? "Đang chờ phản hồi từ Codex…" : self.lastAssistantProgress, force: true)
        }
        progressTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    deinit { stop() }
}
