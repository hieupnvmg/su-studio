import Foundation

final class ElevenLabsTTS: NSObject, URLSessionTaskDelegate {
    var onUpdate: (([String: Any]) -> Void)?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var active = false
    let root: URL
    init(root: URL) { self.root = root }
    var busy: Bool { active }
    static func supportsFileSpeech(_ model: String) -> Bool {
        !model.lowercased().contains("conversational") && !model.lowercased().contains("realtime")
    }
    static func speechPayload(text: String, model: String, previous: String?, next: String?) -> [String: Any] {
        var payload: [String: Any] = ["text": text, "model_id": model]
        // Context stitching is optional and is not supported by every speech model.
        let contextModels: Set<String> = ["eleven_flash_v2_5", "eleven_turbo_v2_5", "eleven_multilingual_v2"]
        if contextModels.contains(model) {
            if let previous = previous, !previous.isEmpty { payload["previous_text"] = previous }
            if let next = next, !next.isEmpty { payload["next_text"] = next }
        }
        return payload
    }
    static func apiError(status: Int, data: Data?, kind: String, model: String?, secrets: [String]) -> String {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let detail = object?["detail"]
        var code = "", message = ""
        if let item = detail as? [String: Any] {
            code = item["status"] as? String ?? ""
            message = item["message"] as? String ?? ""
        } else if let text = detail as? String { message = text }
        else if let items = detail as? [[String: Any]] {
            message = items.compactMap { $0["msg"] as? String }.joined(separator: "; ")
        } else { message = object?["message"] as? String ?? "" }
        func clean(_ raw: String) -> String {
            var text = raw
            for secret in secrets where !secret.isEmpty { text = text.replacingOccurrences(of: secret, with: "[ẩn dữ liệu]") }
            text = text.replacingOccurrences(of: "(?:sk_|xi_)[A-Za-z0-9_-]{12,}", with: "[ẩn key]", options: .regularExpression)
            return String(text.prefix(700))
        }
        code = clean(code); message = clean(message)
        let reason: String
        switch status {
        case 400, 422: reason = "Yêu cầu hoặc model chưa phù hợp; đây không tự động là lỗi quyền API key."
        case 401: reason = "Kiểm tra API key đã lưu."
        case 403: reason = "Kiểm tra quyền API và quyền dùng giọng/model."
        case 429: reason = "Dịch vụ đang giới hạn yêu cầu hoặc hạn mức tài khoản."
        case 300..<400: reason = "Đã chặn chuyển hướng để bảo vệ API key."
        default: reason = "Không hoàn tất được yêu cầu."
        }
        let action = kind == "generate" ? "Tạo giọng đọc" : kind == "models" ? "Tải model" : "Tải giọng"
        let modelLabel = model.map { " · model \($0)" } ?? ""
        let details = [code, message].filter { !$0.isEmpty }.joined(separator: ": ")
        return "\(action) thất bại (HTTP \(status)\(modelLabel)). \(reason)" + (details.isEmpty ? "" : " ElevenLabs: \(details)") + (kind == "generate" ? " Không tự gửi lại yêu cầu." : "")
    }
    func request(_ body: [String: Any], key: String) {
        let requestID = body["requestId"] as? String ?? ""
        func fail(_ message: String) { onUpdate?(["requestId": requestID, "status": "error", "message": message]) }
        guard !active else { fail("ElevenLabs đang xử lý yêu cầu khác. Hãy đợi hoàn tất."); return }
        let kind = body["kind"] as? String ?? ""
        var path = ""
        var payload: [String: Any]?
        if kind == "voices" { path = "/v2/voices?page_size=100&include_total_count=false" }
        else if kind == "models" { path = "/v1/models" }
        else if kind == "generate" {
            guard let voice = body["voice"] as? String, !voice.isEmpty,
                  voice.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
                  let model = body["model"] as? String, !model.isEmpty,
                  let text = body["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 5000 else {
                fail("Chọn giọng, model và lời đọc từ 1 đến 5.000 ký tự cho một cảnh."); return
            }
            path = "/v1/text-to-speech/\(voice)?output_format=mp3_44100_128"
            guard Self.supportsFileSpeech(model) else {
                fail("Model \(model) dành cho luồng hội thoại/realtime. Hãy tải lại danh sách và chọn model tạo file giọng đọc như Eleven v3 hoặc Flash v2.5 nếu tài khoản hỗ trợ."); return
            }
            let direction = (body["direction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard direction.isEmpty || ["eleven_v3", "eleven_v4"].contains(model) else { fail("Cảm xúc cần model Eleven v3 hoặc v4."); return }
            let taggedText = body["taggedText"] as? String ?? text
            guard taggedText == text || ["eleven_v3", "eleven_v4"].contains(model) else { fail("Audio tags cần Eleven v3 hoặc v4."); return }
            let speechText = direction.isEmpty ? taggedText : direction + "\n" + taggedText
            guard speechText.count <= 5000 else { fail("Lời đọc và chỉ dẫn vượt 5.000 ký tự."); return }
            payload = Self.speechPayload(text: speechText, model: model, previous: body["previousText"] as? String, next: body["nextText"] as? String)
        } else { fail("Yêu cầu ElevenLabs không hợp lệ."); return }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io" + path)!)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue(payload == nil ? "application/json" : "audio/mpeg", forHTTPHeaderField: "Accept")
        if let payload = payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session; active = true
        onUpdate?(["requestId": requestID, "status": "running", "message": kind == "generate" ? "ElevenLabs đang tạo giọng đọc…" : "Đang lấy danh sách từ ElevenLabs…"])
        task = session.dataTask(with: request) { [weak self] data, response, error in
            var result: [String: Any] = ["requestId": requestID, "status": "error"]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil {
                result["message"] = kind == "generate" ? "Kết nối bị gián đoạn. Chưa nhận được audio; yêu cầu có thể đã dùng credit. Kiểm tra lịch sử ElevenLabs trước khi tạo lại." : "Không kết nối được ElevenLabs. Hãy thử lại."
            } else if !(200..<300).contains(status) {
                result["httpStatus"] = status
                result["message"] = Self.apiError(status: status, data: data, kind: kind, model: body["model"] as? String, secrets: [key, body["text"] as? String ?? "", body["previousText"] as? String ?? "", body["nextText"] as? String ?? ""])
            } else if kind == "generate" {
                if let data = data, !data.isEmpty, (response?.mimeType ?? "").hasPrefix("audio/") {
                    do {
                        guard let root = self?.root else { return }
                        let folder = root.appendingPathComponent("assets", isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let file = folder.appendingPathComponent(UUID().uuidString + "-voice.mp3")
                        try data.write(to: file, options: .atomic)
                        result["status"] = "completed"; result["path"] = file.path; result["name"] = file.lastPathComponent
                        result["message"] = "Đã tạo audio. Hãy nghe thử rồi duyệt."
                    } catch { result["message"] = "Đã nhận audio nhưng không lưu được trên máy. Kiểm tra dung lượng trước khi tạo lại." }
                } else { result["message"] = "ElevenLabs không trả về audio hợp lệ. Kiểm tra lịch sử dịch vụ trước khi tạo lại." }
            } else if let data = data, let json = try? JSONSerialization.jsonObject(with: data) {
                if kind == "voices", let object = json as? [String: Any], let voices = object["voices"] as? [[String: Any]] {
                    result["voices"] = voices.compactMap { item -> [String: String]? in
                        guard let id = item["voice_id"] as? String, let name = item["name"] as? String else { return nil }
                        return ["id": id, "name": name]
                    }
                    result["hasMore"] = object["has_more"] as? Bool ?? false
                    result["status"] = "completed"
                } else if kind == "models", let models = json as? [[String: Any]] {
                    result["models"] = models.filter { model in
                        Self.supportsFileSpeech(model["model_id"] as? String ?? "") && model["can_do_text_to_speech"] as? Bool == true && (model["languages"] as? [[String: Any]] ?? []).contains { $0["language_id"] as? String == "vi" }
                    }.compactMap { item -> [String: String]? in
                        guard let id = item["model_id"] as? String, let name = item["name"] as? String else { return nil }
                        return ["id": id, "name": name]
                    }
                    result["status"] = "completed"
                } else { result["message"] = "Danh sách ElevenLabs không hợp lệ." }
            } else { result["message"] = "Không đọc được phản hồi ElevenLabs." }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.active = false; self.task = nil
                self.session?.finishTasksAndInvalidate(); self.session = nil
                self.onUpdate?(result)
            }
        }
        task?.resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    deinit { session?.invalidateAndCancel() }
}
