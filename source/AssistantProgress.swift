import Foundation

/// Public progress only: deliberately never stores reasoning.content or textDelta.
struct AssistantProgress {
    let startedAt: TimeInterval
    var lastEventAt: TimeInterval?
    var lastReplyAt: TimeInterval?
    var phase = "connecting"
    var connection = "checking"
    var summary = ""
    var plan: [[String: String]] = []
    private var messages: [String: String] = [:]
    private var phases: [String: String] = [:]
    private var latestItem = ""
    private var summaryParts: [String: String] = [:]
    init(now: TimeInterval = Date().timeIntervalSince1970) { startedAt = now }
    mutating func received(_ method: String, _ params: [String: Any], now: TimeInterval = Date().timeIntervalSince1970) {
        guard method.hasPrefix("item/") || method.hasPrefix("turn/") || method.hasPrefix("thread/tokenUsage/") else { return }
        lastEventAt = now
        switch method {
        case "turn/started": phase = "working"
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any], let type = item["type"] as? String else { return }
            if type == "reasoning" {
                phase = "preparing"
                if let parts = item["summary"] as? [String], !parts.isEmpty { summary = String(parts.joined(separator: "\n").suffix(6000)) }
                // Never inspect item["content"].
            } else if type == "webSearch" { phase = "searching" }
            else if type == "agentMessage", let itemID = item["id"] as? String {
                phases[itemID] = item["phase"] as? String ?? "final_answer"
                if phases[itemID] != "commentary" { latestItem = itemID; phase = "writing" }
                if let text = item["text"] as? String { messages[itemID] = String(text.prefix(300_000)) }
            }
        case "item/agentMessage/delta":
            let itemID = params["itemId"] as? String ?? "response"
            if phases[itemID] != "commentary" { latestItem = itemID; phase = "writing" }
            if let delta = params["delta"] as? String, (messages[itemID]?.count ?? 0) < 300_000 { messages[itemID, default: ""] += delta }
        case "item/reasoning/summaryTextDelta":
            phase = "preparing"
            let itemID = params["itemId"] as? String ?? "summary"
            let index = params["summaryIndex"] as? Int ?? 0
            let key = itemID + ":" + String(index)
            if let delta = params["delta"] as? String { summaryParts[key, default: ""] += delta }
            summary = String(summaryParts.keys.sorted().compactMap { summaryParts[$0] }.joined(separator: "\n").suffix(6000))
        case "item/reasoning/textDelta":
            phase = "preparing" // Timestamp only; raw reasoning text is discarded.
        case "turn/plan/updated":
            if let rows = params["plan"] as? [[String: Any]] {
                plan = rows.prefix(12).compactMap { row in
                    guard let text = row["step"] as? String, let status = row["status"] as? String else { return nil }
                    return ["step": String(text.prefix(300)), "status": status]
                }
            }
        default: break
        }
    }
    mutating func transportReply(now: TimeInterval = Date().timeIntervalSince1970) { lastReplyAt = now; connection = "responsive" }
    var output: String { messages[latestItem] ?? "" }
    func snapshot(now: TimeInterval = Date().timeIntervalSince1970) -> [String: Any] {
        let partial = PartialStoryboard.read(output)
        return ["startedAt": startedAt, "lastEventAt": lastEventAt as Any? ?? NSNull(), "lastReplyAt": lastReplyAt as Any? ?? NSNull(),
                "phase": phase, "connection": connection, "summary": summary, "plan": plan,
                "receivedCharacters": output.count, "receivedScenes": partial.scenes.count,
                "scenePreviews": partial.scenes.suffix(6).map { ["chapter": $0["chapter"] ?? "", "time": $0["time"] ?? "", "voice": String(($0["voice"] ?? "").prefix(1000))] },
                "documentPreview": String(partial.document.suffix(4000)), "reportedAt": now]
    }
}

enum PartialStoryboard {
    /// Reads only top-level document/scenes, never counts braces inside JSON strings.
    static func read(_ text: String) -> (document: String, scenes: [[String: String]]) {
        let chars = Array(text)
        var i = 0, depth = 0, scenes: [[String: String]] = [], document = ""
        func space(_ index: inout Int) { while index < chars.count && chars[index].isWhitespace { index += 1 } }
        func string(_ index: inout Int) -> String? {
            guard index < chars.count && chars[index] == "\"" else { return nil }
            let start = index; index += 1
            var escaped = false
            while index < chars.count {
                let c = chars[index]; index += 1
                if escaped { escaped = false; continue }
                if c == "\\" { escaped = true; continue }
                if c == "\"" {
                    let data = Data(String(chars[start..<index]).utf8)
                    return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
                }
            }
            // Decode a partial string if the stream ends mid-field/mid-escape.
            var raw = String(chars[start..<index])
            for _ in 0..<7 {
                if let decoded = (try? JSONSerialization.jsonObject(with: Data((raw + "\"").utf8), options: [.fragmentsAllowed])) as? String { return decoded }
                if raw.count <= 1 { break }; raw.removeLast()
            }
            return nil
        }
        while i < chars.count {
            if chars[i] == "\"" {
                let key = string(&i)
                guard depth == 1 else { continue }
                space(&i); guard i < chars.count && chars[i] == ":" else { continue }; i += 1; space(&i)
                if key == "document", i < chars.count, chars[i] == "\"" { document = string(&i) ?? ""; continue }
                if key == "scenes", i < chars.count, chars[i] == "[" {
                    i += 1
                    while i < chars.count {
                        space(&i); if i >= chars.count || chars[i] == "]" { break }
                        if chars[i] == "," { i += 1; continue }
                        guard chars[i] == "{" else { break }
                        let start = i; var objectDepth = 0
                        while i < chars.count {
                            if chars[i] == "\"" { _ = string(&i); continue }
                            if chars[i] == "{" { objectDepth += 1 }
                            if chars[i] == "}" { objectDepth -= 1; i += 1; if objectDepth == 0 { break }; continue }
                            i += 1
                        }
                        guard objectDepth == 0 else { return (document, scenes) }
                        let data = Data(String(chars[start..<i]).utf8)
                        if let scene = (try? JSONSerialization.jsonObject(with: data)) as? [String: String], ["time", "chapter", "voice", "image", "video", "notes"].allSatisfy({ scene[$0] != nil }) { scenes.append(scene) }
                    }
                    if i < chars.count && chars[i] == "]" { i += 1 }
                    continue
                }
                continue
            }
            if chars[i] == "{" || chars[i] == "[" { depth += 1 }
            if chars[i] == "}" || chars[i] == "]" { depth -= 1 }
            i += 1
        }
        return (document, scenes)
    }
}
