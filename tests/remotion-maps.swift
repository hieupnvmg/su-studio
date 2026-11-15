import Foundation
// Remotion map scenes: plan sanitising, install status, project sync and (when installed) a real render.
let work = URL(fileURLWithPath: CommandLine.arguments[1]); let fm = FileManager.default
let template = URL(fileURLWithPath: CommandLine.arguments[2])
try? fm.removeItem(at: work); try fm.createDirectory(at: work, withIntermediateDirectories: true)

// Plan sanitising
let plan: [String: Any] = ["title": String(repeating: "Điện Biên Phủ ", count: 20), "date": "1954", "style": "weird",
    "start": ["center": [103.3, 21.55], "zoom": 8], "end": ["center": [103.05, 21.42], "zoom": 9],
    "sides": [["id": "VN", "name": "Quân ta", "color": "#c0392b"], ["id": "vn", "name": "Trùng id", "color": "red"], ["id": "x", "name": "3"], ["id": "y", "name": "4"], ["id": "z", "name": "5"]],
    "places": [["name": "Điện Biên Phủ", "at": [103.02, 21.39], "kind": "fort"], ["name": "", "at": [1, 1]], ["name": "Sai", "at": [200, 1]], ["name": "Sông", "at": [103.0, 21.5], "kind": "lake"]],
    "moves": [["side": "vn", "path": [[103.42, 21.59], [103.07, 21.44]], "start": 1, "end": 99, "label": "Tiến"], ["side": "nobody", "path": [[1, 1], [2, 2]], "start": 2, "end": 3], ["side": "vn", "path": [[1, 1]], "start": 0, "end": 2], ["side": "vn", "path": [[1, 1], [2, 2]], "start": 3, "end": 3.1]],
    "clashes": [["at": [103.05, 21.43], "time": -5, "label": "Him Lam"], ["at": "x"]]]
let props = RemotionMaps.sanitize(plan, aspect: "9:16", seconds: 12)!
precondition(props["width"] as? Int == 1080 && props["height"] as? Int == 1920 && props["style"] as? String == "vintage" && (props["title"] as! String).count == 80)
let sides = props["sides"] as! [[String: Any]]
precondition(sides.count == 4 && sides[0]["id"] as? String == "vn" && sides[1]["id"] as? String == "side2" && sides[1]["color"] as? String == "#2c5aa0", "ids unique, colours checked, at most four sides: \(sides)")
let places = props["places"] as! [[String: Any]]
precondition(places.count == 2 && places[1]["kind"] as? String == "city", "bad names and coordinates dropped, unknown kind becomes city")
let moves = props["moves"] as! [[String: Any]]
precondition(moves.count == 2 && moves[0]["end"] as? Double == 12 && moves[1]["side"] as? String == "vn", "times clamped, short or one-point moves dropped, unknown side → first: \(moves)")
precondition(moves[0]["kind"] as? String == "advance", "kind defaults to advance")
let retreatPlan = RemotionMaps.sanitize(["start": ["center": [103, 21], "zoom": 8], "moves": [["path": [[103, 21], [103.1, 21.1]], "start": 1, "end": 3, "kind": "retreat"], ["path": [[103, 21], [103.1, 21.1]], "start": 1, "end": 3, "kind": "fly"]]], aspect: "16:9", seconds: 6)!
precondition((retreatPlan["moves"] as! [[String: Any]]).map { $0["kind"] as! String } == ["retreat", "advance"])
let clashes = props["clashes"] as! [[String: Any]]
precondition(clashes.count == 1 && clashes[0]["time"] as? Double == 0)
let world = RemotionMaps.sanitize(["start": ["center": [57, 23], "zoom": 0.4], "end": ["center": [15, 37], "zoom": 30], "moves": [["path": (0..<30).map { [Double($0), 10.0] }, "start": 1, "end": 3]]], aspect: "16:9", seconds: 10)!
precondition((world["start"] as! [String: Any])["zoom"] as? Double == 1 && (world["end"] as! [String: Any])["zoom"] as? Double == 1, "zoom clamped to 1…14; a jump over 4 levels keeps the start view")
precondition(((world["moves"] as! [[String: Any]])[0]["path"] as! [[Double]]).count == 24, "long voyages keep up to 24 points")
precondition(RemotionMaps.sanitize(["start": ["center": [103, 21]]], aspect: "16:9", seconds: 10) == nil, "missing zoom")
precondition(RemotionMaps.sanitize(["start": ["center": [103, 21], "zoom": 8]], aspect: "16:9", seconds: 90) == nil, "too long")
let far = RemotionMaps.sanitize(["start": ["center": [103, 21], "zoom": 5], "end": ["center": [104, 22], "zoom": 12]], aspect: "16:9", seconds: 10)!
precondition((far["end"] as! [String: Any])["zoom"] as? Double == 5, "a zoom jump over 4 levels keeps the start view")

// Install status with a fake workspace: nothing, then packages, then the browser.
let maps = RemotionMaps(root: work, template: template)
precondition(maps.status()["ready"] as? Bool == false && maps.packagesReady() == false && maps.browserReady() == false)
try maps.syncProject()
precondition(fm.fileExists(atPath: maps.project.appendingPathComponent("src/MapScene.tsx").path) && fm.fileExists(atPath: maps.project.appendingPathComponent("render.mjs").path))
for (name, version) in maps.pinned() {
    let folder = maps.project.appendingPathComponent("node_modules/\(name)"); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["version": version]).write(to: folder.appendingPathComponent("package.json"))
}
precondition(maps.packagesReady() && !maps.browserReady() && maps.pinned()["remotion"] != nil)
let shell = maps.project.appendingPathComponent("node_modules/.remotion/chrome-headless-shell/mac-arm64/chrome-headless-shell-mac-arm64")
try fm.createDirectory(at: shell, withIntermediateDirectories: true); fm.createFile(atPath: shell.appendingPathComponent("chrome-headless-shell").path, contents: Data())
precondition(maps.browserReady())
try Data("old".utf8).write(to: maps.project.appendingPathComponent("src/MapScene.tsx")); try maps.syncProject()
let synced = try String(contentsOf: maps.project.appendingPathComponent("src/MapScene.tsx"), encoding: .utf8)
precondition(synced != "old" && maps.packagesReady(), "sync refreshes sources and keeps packages")
precondition(RemotionMaps.nodeChecksums["arm64"]?.count == 64 && RemotionMaps.nodeChecksums["x64"]?.count == 64 && ["arm64", "x64"].contains(RemotionMaps.arch))
precondition(RemotionMaps.label("render", 0.5).contains("50%"))

// Real render through the app's code path, only where Remotion is installed (REMOTION_WORKSPACE = a HistoryStudio-like root).
if let installed = ProcessInfo.processInfo.environment["REMOTION_WORKSPACE"] {
    let real = RemotionMaps(root: URL(fileURLWithPath: installed), template: template)
    precondition(real.status()["ready"] as? Bool == true, "workspace ready: \(real.status())")
    let out = work.appendingPathComponent("preview.png"); var done = false, failure: Error?
    var phases: [String] = []; real.onUpdate = { if let p = $0["phase"] as? String { phases.append(p) } }
    real.render(props: RemotionMaps.sanitize(plan, aspect: "16:9", seconds: 6)!, output: out, still: true, frame: 90) { failure = $0; done = true }
    let until = Date().addingTimeInterval(240); while !done && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    precondition(done && failure == nil && (try? Data(contentsOf: out))?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true, "real still render: \(String(describing: failure))")
    precondition(phases.contains("bundle"), "progress forwarded: \(phases)")
    print("  real Remotion still rendered (\((try? fm.attributesOfItem(atPath: out.path)[.size]) ?? 0) bytes)")
}
print("Remotion maps passed: plan sanitising (coordinates, zoom, sides, colours, times, limits), install status, project sync")
