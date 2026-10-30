import Foundation
import AVFoundation

final class NarrationPlayer: NSObject, AVAudioPlayerDelegate {
    struct Clip { let path: URL; let title: String; let sceneID: String }
    var onUpdate: (([String: Any]) -> Void)?
    private let root: URL
    private var clips: [Clip] = []
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var index = 0
    private var projectID = ""
    private var status = "idle"
    init(root: URL) { self.root = root.appendingPathComponent("assets").resolvingSymlinksInPath().standardizedFileURL }
    func command(_ body: [String: Any]) {
        switch body["command"] as? String {
        case "start":
            guard let items = body["clips"] as? [[String: String]], !items.isEmpty, let pid = body["projectId"] as? String else { return }
            var validated: [Clip] = []
            for item in items {
                guard let path = item["path"] else { return }
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
                guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
                    emit(message: "Không tìm thấy file audio trong thư viện: \(item["title"] ?? "cảnh"). Hãy nhập hoặc tạo lại file."); return
                }
                validated.append(Clip(path: url, title: item["title"] ?? "", sceneID: item["sceneId"] ?? ""))
            }
            stop(); clips = validated; projectID = pid; index = 0
            load(playing: true)
        case "pause": player?.pause(); status = "paused"; emit()
        case "resume":
            if status == "completed" { index = 0; load(playing: true) }
            else if player?.play() == true { status = "playing"; emit() }
        case "stop": stop(); emit()
        case "next": if index + 1 < clips.count { let playing = status == "playing"; index += 1; load(playing: playing) }
        case "previous": if index > 0 { let playing = status == "playing"; index -= 1; load(playing: playing) }
        case "seek":
            guard let player = player, let delta = body["seconds"] as? Double, delta.isFinite else { return }
            player.currentTime = max(0, min(max(0, player.duration - 0.05), player.currentTime + max(-60, min(60, delta))))
            emit()
        default: break
        }
    }
    private func load(playing: Bool) {
        timer?.invalidate(); player?.stop()
        guard clips.indices.contains(index) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: clips[index].path)
            self.player = player; player.delegate = self
            guard player.prepareToPlay() else { throw NSError(domain: "NarrationPlayer", code: 1) }
            status = playing ? "playing" : "paused"
            if playing && !player.play() { throw NSError(domain: "NarrationPlayer", code: 2) }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                if self?.status == "playing" { self?.emit() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            emit()
        } catch { status = "error"; player = nil; emit(message: "Không đọc được audio \(clips[index].title). Hãy kiểm tra file hoặc chọn phiên bản khác.") }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { status = "error"; emit(message: "Audio bị gián đoạn. Hãy kiểm tra file của cảnh này."); return }
        if index + 1 < clips.count { index += 1; load(playing: true) }
        else { timer?.invalidate(); timer = nil; status = "completed"; emit() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { status = "error"; emit(message: "File audio không đọc được. Hãy chọn phiên bản khác.") }
    private func emit(message: String = "") {
        let clip = clips.indices.contains(index) ? clips[index] : nil
        onUpdate?(["projectId": projectID, "status": status, "index": index, "total": clips.count, "title": clip?.title ?? "", "sceneId": clip?.sceneID ?? "", "elapsed": player?.currentTime ?? 0, "duration": player?.duration ?? 0, "message": message])
    }
    func stop() { timer?.invalidate(); timer = nil; player?.stop(); player = nil; status = "idle" }
    deinit { timer?.invalidate() }
}
