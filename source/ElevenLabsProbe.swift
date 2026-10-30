import Foundation

/// Checks an authenticated, read-only endpoint. Never submits generation jobs.
final class ElevenLabsProbe: NSObject, URLSessionTaskDelegate {
    var onUpdate: (([String: Any]) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var generation = UUID()
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
    }
    func test(key: String) {
        cancel()
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            onUpdate?(["status": "error", "message": "API key ElevenLabs không được trống hoặc chứa khoảng trắng. Hãy kiểm tra key đã lưu."]); return
        }
        let current = generation
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v2/voices?page_size=1&include_total_count=false")!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        onUpdate?(["status": "checking", "stage": "api", "message": "Đã đọc key từ Keychain. Đang kiểm tra với dịch vụ…"])
        task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = Self.result(data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self = self, current == self.generation else { return }
                self.task = nil; self.session?.finishTasksAndInvalidate(); self.session = nil
                self.onUpdate?(result)
            }
        }
        task?.resume()
    }
    // Do not forward a stored API key to redirected destinations.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    static func result(data: Data?, response: URLResponse?, error: Error?) -> [String: Any] {
        func fail(_ text: String) -> [String: Any] { var value: [String: Any] = ["status": "error", "stage": "api", "message": text]; if let http = response as? HTTPURLResponse { value["httpStatus"] = http.statusCode }; return value }
        if let error = error as? URLError {
            return fail(error.code == .timedOut ? "ElevenLabs chưa phản hồi trong thời gian chờ. Hãy thử lại." : "Không kết nối được ElevenLabs. Kiểm tra mạng và thử lại.")
        }
        if error != nil { return fail("Không kết nối được ElevenLabs. Hãy thử lại.") }
        guard let http = response as? HTTPURLResponse else { return fail("Không nhận được phản hồi hợp lệ từ ElevenLabs.") }
        let body = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let detail = body?["detail"] as? [String: Any]
        if [401, 403].contains(http.statusCode), detail?["status"] as? String == "missing_permissions" {
            return fail("Key thiếu quyền đọc giọng. Vào ElevenLabs → Developers → API Keys, bật Voices: Read rồi kiểm tra lại.")
        }
        switch http.statusCode {
        case 401: return fail("API key không hợp lệ hoặc đã bị thu hồi. Nhập và lưu key mới rồi kiểm tra lại.")
        case 403: return fail("ElevenLabs từ chối quyền API. Kiểm tra quyền Voices: Read và trạng thái tài khoản.")
        case 429: return fail("ElevenLabs đang giới hạn yêu cầu. Đợi một lát rồi thử lại.")
        case 300..<400: return fail("ElevenLabs chuyển hướng yêu cầu. App đã dừng để không chuyển tiếp API key.")
        case 500...599: return fail("Dịch vụ ElevenLabs đang lỗi (HTTP \(http.statusCode)). Thử lại sau.")
        case 200..<300: break
        default: return fail("Kiểm tra thất bại (HTTP \(http.statusCode)). Hãy kiểm tra cấu hình API.")
        }
        guard let body = body, body["detail"] == nil,
              let voices = body["voices"] as? [[String: Any]], body["has_more"] is Bool else {
            return fail("ElevenLabs trả về dữ liệu không hợp lệ. Chưa xác nhận được API key.")
        }
        return ["status": "ok", "stage": "api", "httpStatus": http.statusCode, "message": voices.isEmpty ? "API key được chấp nhận. Đọc được danh sách giọng nhưng hiện chưa có giọng." : "API key được chấp nhận và có quyền đọc danh sách giọng.", "checkedAt": Date().timeIntervalSince1970]

    }
    deinit { session?.invalidateAndCancel() }
}
