import Foundation
import Security

struct CredentialFailure: Error {
    let provider: String
    let stage: String
    let code: OSStatus
    var payload: [String: Any] {
        let name = provider == "github" ? "GitHub" : provider == "plenx" ? "PlenX" : "ElevenLabs"
        let reason: String
        switch code {
        case errSecItemNotFound: reason = "Chưa tìm thấy key \(name) đã lưu. Hãy nhập và lưu key trước."
        case errSecUserCanceled: reason = "Quyền truy cập Keychain vừa bị hủy. Bấm thử lại và hoàn tất hộp thoại của macOS nếu có."
        case errSecInteractionNotAllowed: reason = "Keychain đang khóa hoặc chưa cho phép tương tác. Mở khóa Keychain trên Mac rồi thử lại."
        case errSecAuthFailed: reason = "Keychain chưa cho phép app truy cập key. Đóng rồi mở lại Sử Studio; nếu macOS hỏi quyền, hãy kiểm tra và xác nhận trên máy."
        default: reason = "Không truy cập được Keychain. Đóng rồi mở lại app và thử lại. Chi tiết macOS: \(SecCopyErrorMessageString(code, nil) as String? ?? "Không rõ lỗi")"
        }
        let action = stage == "keychainWrite" ? "Lưu Keychain" : stage == "keychainVerify" ? "Đọc lại sau khi lưu" : "Đọc Keychain"
        return ["provider": provider, "status": "error", "stage": stage, "code": Int(code), "message": "\(action) thất bại (mã \(code)). \(reason)"]
    }
}

/// Serialized Keychain operations; no secret is returned to JavaScript or logs.
final class CredentialStore {
    private let service: String
    private let queue = DispatchQueue(label: "local.history.studio.credentials")
    init(service: String = "HistoryStudio") { self.service = service }
    private func query(_ provider: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider]
    }
    private func readSync(_ provider: String, stage: String = "keychainRead") -> Result<String, CredentialFailure> {
        var q = query(provider)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess else { return .failure(CredentialFailure(provider: provider, stage: stage, code: status)) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return .failure(CredentialFailure(provider: provider, stage: stage, code: errSecDecode))
        }
        return .success(value)
    }
    func read(_ provider: String, completion: @escaping (Result<String, CredentialFailure>) -> Void) {
        queue.async { let result = self.readSync(provider); DispatchQueue.main.async { completion(result) } }
    }
    func save(_ provider: String, value: String, completion: @escaping ([String: Any]) -> Void) {
        queue.async {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["elevenlabs", "plenx", "github"].contains(provider), !normalized.isEmpty,
                  !normalized.contains(where: { $0.isWhitespace || $0.isNewline }), provider != "plenx" || normalized.hasPrefix("pk_") else {
                let result: [String: Any] = ["provider": provider, "status": "error", "stage": "validation", "message": "Key không đúng định dạng. Dán nguyên API key, không kèm khoảng trắng hoặc nhãn; key PlenX bắt đầu bằng pk_."]
                DispatchQueue.main.async { completion(result) }; return
            }
            let bytes = Data(normalized.utf8)
            let q = self.query(provider)
            var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
            if status == errSecItemNotFound {
                var add = q; add[kSecValueData as String] = bytes
                status = SecItemAdd(add as CFDictionary, nil)
                if status == errSecDuplicateItem { status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: bytes] as CFDictionary) }
            }
            guard status == errSecSuccess else {
                let error = CredentialFailure(provider: provider, stage: "keychainWrite", code: status)
                DispatchQueue.main.async { completion(error.payload) }; return
            }
            let result: [String: Any]
            switch self.readSync(provider, stage: "keychainVerify") {
            case .success(let stored) where stored == normalized:
                result = ["provider": provider, "status": "saved", "stage": "keychainVerify", "message": "Đã lưu và đọc lại key thành công. Bấm Kiểm tra kết nối để xác thực với dịch vụ."]
            case .failure(let error): result = error.payload
            default: result = ["provider": provider, "status": "error", "stage": "keychainVerify", "message": "Đọc lại key chưa khớp sau khi lưu. Ô nhập vẫn được giữ; hãy thử lưu lại."]
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func existingProviders(completion: @escaping ([String: Bool]) -> Void) {
        queue.async {
            var result: [String: Bool] = [:]
            for provider in ["elevenlabs", "plenx"] {
                var q = self.query(provider); q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
                result[provider] = SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
