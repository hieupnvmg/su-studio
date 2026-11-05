import Foundation
let temp=URL(fileURLWithPath:CommandLine.arguments[1])
let fm=FileManager.default
let oldAssets=temp.appendingPathComponent("old/assets"),newAssets=temp.appendingPathComponent("new/assets")
try fm.createDirectory(at:oldAssets,withIntermediateDirectories:true)
try Data("voice".utf8).write(to:oldAssets.appendingPathComponent("A1-voice.mp3"))
try Data("image".utf8).write(to:oldAssets.appendingPathComponent("B2-image.png"))
try Data("unused".utf8).write(to:oldAssets.appendingPathComponent("C3-unused.mp4"))
let state:[String:Any]=["projects":[["id":"p1","title":"Trận Bạch Đằng","scenes":[["id":"s1","assets":["audio":[["path":oldAssets.path+"/A1-voice.mp3"]],"image":[["path":oldAssets.path+"/B2-image.png"],["path":oldAssets.path+"/missing.png"]]]]],"timelineEntries":[["path":"/elsewhere/clip.mp4"]]]]]
precondition(ProjectBackup.referencedAssets(state,assets:oldAssets)==["A1-voice.mp3","B2-image.png","missing.png"])
let archive=temp.appendingPathComponent("backup.zip")
let made=try ProjectBackup.create(state:state,assets:oldAssets,appVersion:"0.14.9",to:archive)
precondition(made.projects==1 && made.files==2,"only referenced, existing files are packed")
// Restore on "another machine": different assets folder, one file already present.
try fm.createDirectory(at:newAssets,withIntermediateDirectories:true)
try Data("kept".utf8).write(to:newAssets.appendingPathComponent("B2-image.png"))
let staged=try ProjectBackup.read(archive,assets:newAssets)
precondition(staged.files==["A1-voice.mp3","B2-image.png"] && staged.manifest["version"] as? String=="0.14.9")
let scene=((staged.state["projects"] as! [[String:Any]])[0]["scenes"] as! [[String:Any]])[0]["assets"] as! [String:[[String:Any]]]
precondition(scene["audio"]![0]["path"] as? String==newAssets.path+"/A1-voice.mp3","asset paths point at this machine")
let entry=((staged.state["projects"] as! [[String:Any]])[0]["timelineEntries"] as! [[String:Any]])[0]
precondition(entry["path"] as? String=="/elsewhere/clip.mp4","other paths untouched")
precondition(!fm.fileExists(atPath:newAssets.appendingPathComponent("A1-voice.mp3").path),"reading does not copy anything")
let copied=try ProjectBackup.apply(staged,assets:newAssets);precondition(copied==1)
let restoredVoice=try String(contentsOf:newAssets.appendingPathComponent("A1-voice.mp3"),encoding:.utf8);precondition(restoredVoice=="voice")
let keptImage=try String(contentsOf:newAssets.appendingPathComponent("B2-image.png"),encoding:.utf8);precondition(keptImage=="kept","existing files are kept")
ProjectBackup.discard(staged);precondition(!fm.fileExists(atPath:staged.folder.path))
// Hostile and foreign archives.
func zip(_ files:[String:String],_ name:String) throws -> URL {
 let dir=temp.appendingPathComponent("z-"+name);try fm.createDirectory(at:dir,withIntermediateDirectories:true)
 for (path,text) in files { let u=dir.appendingPathComponent(path);try fm.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:u) }
 let out=temp.appendingPathComponent(name+".zip")
 let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/zip");p.currentDirectoryURL=dir;p.arguments=["-q","-r",out.path]+files.keys.sorted();p.standardOutput=FileHandle.nullDevice;try p.run();p.waitUntilExit();return out
}
do { _=try ProjectBackup.read(try zip(["notes.txt":"hi"],"foreign"),assets:newAssets);fatalError("foreign zip accepted") } catch {}
let manifest="{\"app\":\"Sử Studio\",\"format\":1}"
do { _=try ProjectBackup.read(try zip(["manifest.json":manifest,"projects.json":"{\"projects\":[{\"title\":\"no id\"}]}"],"broken"),assets:newAssets);fatalError("broken projects accepted") } catch {}
do { _=try ProjectBackup.read(try zip(["manifest.json":"{\"app\":\"Sử Studio\",\"format\":9}","projects.json":"{}"],"future"),assets:newAssets);fatalError("future format accepted") } catch {}
// An entry that climbs out of the extraction folder is refused before extracting.
let slipDir=temp.appendingPathComponent("slip/inner");try fm.createDirectory(at:slipDir,withIntermediateDirectories:true)
try Data(manifest.utf8).write(to:slipDir.appendingPathComponent("manifest.json"));try Data("{\"projects\":[{\"id\":\"p\",\"scenes\":[]}]}".utf8).write(to:slipDir.appendingPathComponent("projects.json"));try Data("x".utf8).write(to:temp.appendingPathComponent("slip/evil.txt"))
let slip=temp.appendingPathComponent("slip.zip");let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/zip");p.currentDirectoryURL=slipDir;p.arguments=["-q",slip.path,"manifest.json","projects.json","../evil.txt"];p.standardOutput=FileHandle.nullDevice;try p.run();p.waitUntilExit()
do { _=try ProjectBackup.read(slip,assets:newAssets);fatalError("path traversal accepted") } catch {}
let clean=temp.appendingPathComponent("clean.zip");let q=Process();q.executableURL=URL(fileURLWithPath:"/usr/bin/zip");q.currentDirectoryURL=slipDir;q.arguments=["-q",clean.path,"manifest.json","projects.json"];try q.run();q.waitUntilExit()
let cleanStaged=try ProjectBackup.read(clean,assets:newAssets);ProjectBackup.discard(cleanStaged)
do { try ProjectBackup.create(state:["projects":[]],assets:oldAssets,appVersion:"x",to:temp.appendingPathComponent("empty.zip"));fatalError("empty backup created") } catch {}
print("Project backup passed: referenced media only, restore to another machine rewrites paths, keeps existing files, rejects foreign, broken, newer and path-traversal archives")
