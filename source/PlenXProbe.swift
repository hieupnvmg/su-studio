import Foundation
import AppKit

/// Checks an authenticated, read-only endpoint. Never submits generation jobs.
final class PlenXProbe: NSObject, URLSessionTaskDelegate {
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
        guard key.hasPrefix("pk_"), !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            onUpdate?(["status": "error", "message": "API key PlenX phải bắt đầu bằng pk_ và không chứa khoảng trắng. Hãy kiểm tra key đã lưu."]); return
        }
        let current = generation
        var request = URLRequest(url: URL(string: "https://api.plenxai.com/api/v1/developer/voice/models")!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
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
            return fail(error.code == .timedOut ? "PlenX chưa phản hồi trong thời gian chờ. Hãy thử lại." : "Không kết nối được PlenX. Kiểm tra mạng và thử lại.")
        }
        if error != nil { return fail("Không kết nối được PlenX. Hãy thử lại.") }
        guard let http = response as? HTTPURLResponse else { return fail("Không nhận được phản hồi hợp lệ từ PlenX.") }
        switch http.statusCode {
        case 401: return fail("API key không hợp lệ hoặc đã bị thu hồi. Nhập và lưu key mới rồi kiểm tra lại.")
        case 403: return fail("PlenX từ chối quyền API. Kiểm tra gói Pro/Ultimate và trạng thái tài khoản.")
        case 429: return fail("PlenX đang giới hạn yêu cầu. Đợi một lát rồi thử lại.")
        case 300..<400: return fail("PlenX chuyển hướng yêu cầu. App đã dừng để không chuyển tiếp API key.")
        case 500...599: return fail("Dịch vụ PlenX đang lỗi (HTTP \(http.statusCode)). Thử lại sau.")
        case 200..<300: break
        default: return fail("Kiểm tra thất bại (HTTP \(http.statusCode)). Hãy kiểm tra cấu hình API.")
        }
        guard let data = data, let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], body["success"] as? Bool == true,
              let models = body["models"] as? [[String: Any]] else { return fail("PlenX trả về dữ liệu không hợp lệ hoặc chưa chấp nhận yêu cầu. Chưa xác nhận được API key.") }
        return ["status": "ok", "stage": "api", "httpStatus": http.statusCode, "message": "API key được chấp nhận. Đã đọc được danh sách \(models.count) model giọng đọc.", "checkedAt": Date().timeIntervalSince1970]
    }
    deinit { session?.invalidateAndCancel() }
}

/// Image requests are separate from the read-only connection probe.
final class PlenXImages: NSObject, URLSessionTaskDelegate {
    let root: URL
    var onUpdate: (([String: Any]) -> Void)?
    private var active = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    init(root: URL) { self.root = root }
    func request(_ body: [String: Any], key: String) {
        let requestID = body["requestId"] as? String ?? ""
        func reply(_ result: [String: Any]) { DispatchQueue.main.async { self.active = false; var value = result; value["requestId"] = requestID; self.onUpdate?(value) } }
        guard !active else { reply(["status":"error","message":"PlenX đang xử lý yêu cầu ảnh khác."]); return }
        let kind = body["kind"] as? String ?? ""
        var path = "/models", payload: [String: Any]?
        if kind == "generate" {
            guard let prompt = body["prompt"] as? String, !prompt.isEmpty, prompt.count <= 20000,
                  let model = body["model"] as? String, model.range(of:"^[A-Za-z0-9._-]+$", options:.regularExpression) != nil else { reply(["status":"error","message":"Chọn model và prompt hợp lệ."]); return }
            path = "/generate/image"; payload = ["prompt":prompt,"model":model,"aspect_ratio":"16:9"]
            if let resolution = body["resolution"] as? String, !resolution.isEmpty { payload?["resolution"] = resolution }
        } else if kind == "status" {
            guard let task = body["taskId"] as? String, task.range(of:"^[A-Za-z0-9_-]+$", options:.regularExpression) != nil else { reply(["status":"error","message":"Mã tác vụ không hợp lệ."]); return }
            path = "/status/" + task
        } else if kind != "models" { reply(["status":"error","message":"Yêu cầu không hợp lệ."]); return }
        guard kind == "models" || key.hasPrefix("pk_") else { reply(["status":"error","message":"Lưu API key PlenX trong Cài đặt & kết nối trước."]); return }
        var request = URLRequest(url:URL(string:"https://api.plenxai.com/api/v1/developer" + path)!)
        request.httpMethod = payload == nil ? "GET" : "POST"
        if kind != "models" { request.setValue(key, forHTTPHeaderField:"X-API-Key") }
        if let payload = payload { request.setValue("application/json", forHTTPHeaderField:"Content-Type"); request.httpBody = try? JSONSerialization.data(withJSONObject:payload) }
        active = true
        session.dataTask(with:request) { data,response,error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, (200..<300).contains(status), let data = data,
                  let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any], json["success"] as? Bool != false else {
                reply(["status":"error","message":kind == "generate" ? "Chưa xác nhận được tác vụ PlenX (HTTP \(status)). Không tự gửi lại. Kiểm tra lịch sử PlenX trước khi tạo mới vì có thể đã dùng credit." : "Không đọc được PlenX (HTTP \(status)). Kiểm tra key, quyền API, credit hoặc thử kiểm tra lại tác vụ."]); return
            }
            if kind == "models" {
                let models = (json["image_models"] as? [[String:Any]] ?? []).filter { ($0["aspect_ratios"] as? [String] ?? []).contains("16:9") }
                reply(["status":"models","models":models]); return
            }
            let task = json["task_id"] as? String ?? body["taskId"] as? String ?? ""
            let state = json["status"] as? String ?? "queued"
            if state == "error" || state == "failed" { reply(["status":"failed","taskId":task,"message":"PlenX báo tạo ảnh thất bại. Kiểm tra tác vụ trên PlenX trước khi tạo lại."]); return }
            guard ["completed","succeeded"].contains(state) else { reply(["status":"queued","taskId":task,"message":state == "processing" ? "PlenX đang tạo ảnh…" : "PlenX đang xếp hàng…"]); return }
            guard let raw = json["result_url"] as? String, let url = URL(string:raw), url.scheme == "https", url.user == nil, url.password == nil else { reply(["status":"error","taskId":task,"message":"Chưa có URL ảnh HTTPS hợp lệ. Hãy kiểm tra lại tác vụ."]); return }
            // Media download has no API key; redirects are blocked as for API requests.
            self.session.downloadTask(with:url) { file,response,error in
                guard error == nil, let file = file, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      (http.expectedContentLength < 50_000_000), let data = try? Data(contentsOf:file), data.count <= 50_000_000,
                      let image = NSImage(data:data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else {
                    reply(["status":"error","taskId":task,"message":"Ảnh đã tạo nhưng chưa tải được file hợp lệ. Kiểm tra lại tác vụ để tải lại, không cần tạo mới."]); return
                }
                do {
                    let folder = self.root.appendingPathComponent("assets",isDirectory:true); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let dest = folder.appendingPathComponent(UUID().uuidString + "-plenx.png"); try png.write(to:dest,options:.atomic)
                    reply(["status":"completed","taskId":task,"path":dest.path,"name":dest.lastPathComponent])
                } catch { reply(["status":"error","taskId":task,"message":"Chưa lưu được ảnh. Kiểm tra dung lượng và kiểm tra lại tác vụ."]) }
            }.resume()
        }.resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
