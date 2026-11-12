import Cocoa
import AVFoundation
// Runs the render pipeline against a fake Blender that writes PNG frames, inside the real sandbox.
let work=URL(fileURLWithPath:CommandLine.arguments[1]),fake=URL(fileURLWithPath:CommandLine.arguments[2]),driver=URL(fileURLWithPath:CommandLine.arguments[3])
let fm=FileManager.default
let home=work.appendingPathComponent("home"),root=home.appendingPathComponent("Library/Application Support/HistoryStudio")
try fm.createDirectory(at:root.appendingPathComponent("assets"),withIntermediateDirectories:true)
precondition(BlenderRender.version(of:fake)=="4.2.3","reads the Blender version")
precondition(BlenderRender.version(of:work)==nil,"a folder that is not Blender is rejected")
let r=BlenderRender(root:root);r.applicationOverride=fake;r.driver=driver;r.home=home
precondition(r.locate()?.version=="4.2.3")
let profile=BlenderRender.sandboxProfile(job:root.appendingPathComponent("blender-jobs/x"),home:home)
precondition(profile.contains("(deny network*)") && profile.contains("(deny file-write* (subpath"),"sandbox denies network and home writes")
// Script check runs the driver's parser with a Python (Blender's own when present).
precondition(BlenderRender.bundledPython(fake)==nil)
let python=URL(fileURLWithPath:"/usr/bin/python3")
let cleanCheck=try BlenderRender.checkScript("ground()\nbox('Thuyền')",driver:driver,python:python)
let importCheck=try BlenderRender.checkScript("import os\nbox()",driver:driver,python:python)
let proseCheck=try BlenderRender.checkScript("Chưa tạo script Python: phiên này được giới hạn",driver:driver,python:python)
precondition(cleanCheck.isEmpty && importCheck.first?.contains("import os")==true && proseCheck.first?.contains("cú pháp")==true,"script check")
// Job validation
let model=root.appendingPathComponent("assets/abc-thuyen.glb");try Data("glTF".utf8).write(to:model)
let out=URL(fileURLWithPath:"/tmp/frames")
var j=try r.job(["mode":"model","modelPath":model.path,"aspectRatio":"9:16","duration":4.0,"fps":24,"camera":"dolly","lighting":"golden"],output:out)
precondition(j["width"] as? Int==1080 && j["height"] as? Int==1920 && j["camera"] as? String=="dolly" && j["ground"] as? Bool==true)
j=try r.job(["mode":"script","script":"box()","quality":"draft","camera":"bogus","lighting":"bogus"],output:out)
precondition(j["width"] as? Int==960 && j["height"] as? Int==540 && j["camera"] as? String=="orbit" && j["lighting"] as? String=="day")
j=try r.job(["mode":"script","script":"box()","duration":10.0,"fps":24,"preview":true,"effects":["fog":0.9,"shake":false]],output:out)
let fx=j["effects"] as! [String:Any]
precondition(fx["fog"] as? Double==0.02 && fx["shake"] as? Bool==false && fx["bloom"] as? Bool==true,"effects clamped with defaults")
precondition(j["frames"] as? [Int]==[1,80,160,240],"preview picks four frames across the clip")
for bad:[String:Any] in [["mode":"model","modelPath":"/etc/hosts"],["mode":"model","modelPath":root.appendingPathComponent("assets/missing.glb").path],["mode":"script","script":"  "],["mode":"other"],["mode":"script","script":"box()","duration":120.0],["mode":"script","script":"box()","fps":60]] {
 do { _=try r.job(bad,output:out);fatalError("accepted \(bad)") } catch {}
}
// A model picked after the assets folder was first created is still accepted.
let lateRoot=work.appendingPathComponent("late");try fm.createDirectory(at:lateRoot,withIntermediateDirectories:true)
let late=BlenderRender(root:lateRoot)
try fm.createDirectory(at:late.assets,withIntermediateDirectories:true);let lateModel=late.assets.appendingPathComponent("m.glb");try Data("glTF".utf8).write(to:lateModel)
_=try late.job(["mode":"model","modelPath":lateModel.path],output:out)
// Poly Haven library: download plans only use Poly Haven hosts and safe relative paths.
let tex=BlenderRender.catalog.first{$0.kind=="texture"}!,phModel=BlenderRender.catalog.first{$0.kind=="model"}!,sky=BlenderRender.catalog.first{$0.kind=="hdri"}!
func file(_ u:String)->[String:Any]{["url":u,"size":10]}
let texListing:[String:Any]=["Diffuse":["1k":["jpg":file("https://dl.polyhaven.org/a_diff.jpg")]],"nor_gl":["1k":["jpg":file("https://dl.polyhaven.org/a_nor.jpg")]],"Rough":["1k":["jpg":file("https://dl.polyhaven.org/a_rough.jpg")]]]
precondition(BlenderRender.downloads(for:tex,listing:texListing).map{$0.1}==["diff.jpg","nor.jpg","rough.jpg"])
precondition(BlenderRender.downloads(for:tex,listing:["Diffuse":texListing["Diffuse"]!]).isEmpty,"incomplete texture skipped")
var evil=texListing;evil["Rough"]=["1k":["jpg":file("https://evil.example.com/x.jpg")]];precondition(BlenderRender.downloads(for:tex,listing:evil).isEmpty,"foreign host refused")
let gltf:[String:Any]=["gltf":["1k":["gltf":["url":"https://dl.polyhaven.org/m.gltf","size":1,"include":["textures/a.jpg":file("https://dl.polyhaven.org/a.jpg"),"m.bin":file("https://dl.polyhaven.org/m.bin")]]]]]
precondition(Set(BlenderRender.downloads(for:phModel,listing:gltf).map{$0.1})==["m.gltf","textures/a.jpg","m.bin"])
var climb=gltf;climb["gltf"]=["1k":["gltf":["url":"https://dl.polyhaven.org/m.gltf","size":1,"include":["../../escape.jpg":file("https://dl.polyhaven.org/a.jpg")]]]]
precondition(BlenderRender.downloads(for:phModel,listing:climb).isEmpty,"path traversal refused")
precondition(BlenderRender.downloads(for:sky,listing:["hdri":["2k":["hdr":file("https://dl.polyhaven.org/s.hdr")]]]).map{$0.1}==["sky.hdr"])
let libRender=BlenderRender(root:work.appendingPathComponent("libtest"))
let skyFolder=libRender.itemFolder(sky);try fm.createDirectory(at:skyFolder,withIntermediateDirectories:true);try Data().write(to:skyFolder.appendingPathComponent("sky.hdr"))
precondition((libRender.installed()["hdri"] as! [String:String]).isEmpty,"unfinished downloads are not used")
try Data().write(to:skyFolder.appendingPathComponent(".complete"))
precondition((libRender.installed()["hdri"] as! [String:String])[sky.key]?.hasSuffix("sky.hdr")==true)
// User models: only safe names and files inside the project assets; film look sanitised.
let userModel=r.assets.appendingPathComponent("u-huey.glb");try Data("glTF".utf8).write(to:userModel)
let withLib=try r.job(["mode":"script","script":"box()","models":["huey":userModel.path,"Bad Name":userModel.path,"etc":"/etc/hosts"],"effects":["film":"film35"]],output:out)
let libModels=(withLib["library"] as! [String:Any])["models"] as! [String:String]
precondition(libModels["huey"]==userModel.path && libModels["Bad Name"]==nil && libModels["etc"]==nil,"user models validated")
precondition((withLib["effects"] as! [String:Any])["film"] as? String=="film35")
let weird=try r.job(["mode":"script","script":"box()","effects":["film":"weird"]],output:out);precondition((weird["effects"] as! [String:Any])["film"] as? String=="none")
// Film look keeps the frame size and changes the picture; "none" leaves it untouched.
let ctx=CGContext(data:nil,width:64,height:36,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(NSColor(red:0.2,green:0.6,blue:0.3,alpha:1).cgColor);ctx.fill(CGRect(x:0,y:0,width:64,height:36));let flat=ctx.makeImage()!
let ci=CIContext(),graded=BlenderRender.graded(flat,look:"film35",frame:3,context:ci)
precondition(graded.width==64 && graded.height==36 && BlenderRender.graded(flat,look:"none",frame:3,context:ci)===flat)
let gp=NSBitmapImageRep(cgImage:graded).colorAt(x:32,y:18)!.usingColorSpace(.deviceRGB)!
precondition(abs(gp.greenComponent-0.6)>0.02,"film look changes colour")
// Image mode: shots must be pictures in the project; timings add up; flashes are shifted onto the clip timeline.
func png(_ name:String,_ w:Int,_ h:Int) throws -> URL {
 let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.setFillColor(NSColor(red:0.3,green:0.5,blue:0.7,alpha:1).cgColor);ctx.fill(CGRect(x:0,y:0,width:w,height:h))
 let url=r.assets.appendingPathComponent(name);try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:url);return url
}
let shotA=try png("shot-a.png",320,180),shotB=try png("shot-b.png",320,180)
let imageJob=try r.job(["mode":"image","shots":[["path":shotA.path,"seconds":2.0,"move":"orbit","flashes":[0.5,9.0]],["path":shotB.path,"seconds":3.0,"move":"weird","parallax":false,"flashes":[1.0]]],"overlays":["smoke":0.5,"lava":1.0,"rain":4.0]],output:out)
let shots=imageJob["shots"] as! [[String:Any]]
precondition(imageJob["duration"] as? Double==5.0 && shots[0]["move"] as? String=="orbit" && shots[1]["move"] as? String=="push","durations add up, unknown moves fall back")
precondition(shots[0]["flashes"] as? [Double]==[0.5] && shots[1]["flashes"] as? [Double]==[3.0],"flashes outside a shot dropped, later shots shifted")
let overlays=imageJob["overlays"] as! [String:Double];precondition(overlays["smoke"]==0.5 && overlays["lava"]==nil && overlays["rain"]==1.0,"overlays filtered and clamped")
for bad:[String:Any] in [["mode":"image","shots":[]],["mode":"image","shots":[["path":"/etc/hosts"]]],["mode":"image","shots":Array(repeating:["path":shotA.path,"seconds":30.0],count:3)]] {
 do { _=try r.job(bad,output:out);fatalError("accepted image job \(bad)") } catch {}
}
// A flat picture has no subject: separation keeps a single layer and never fails.
let flatLayers=try BlenderRender.separateSubject(shotA,into:work,index:0);precondition(flatLayers.subject==nil && flatLayers.background==shotA)
// Free model search: only models mirrored in Objaverse, light enough, with a licence that allows commercial use.
for (label,ok) in [("CC Attribution",true),("CC Attribution-ShareAlike",true),("CC0 Public Domain",true),("Free Standard",true),("CC Attribution-NonCommercial",false),("CC Attribution-NoDerivs",false),("CC Attribution-NonCommercial-ShareAlike",false),("",false)] {
 precondition(BlenderRender.commercialLicense(label)==ok,label)
}
let uidA=String(repeating:"a",count:32),uidB=String(repeating:"b",count:32)
let searchPaths=[uidA:"glbs/000-001/\(uidA).glb"]
func sfModel(_ uid:String,_ license:String,_ faces:Int)->[String:Any]{["uid":uid,"name":"Huey","faceCount":faces,"animationCount":1,"likeCount":5,"license":["label":license],"user":["displayName":"pilot","profileUrl":"https://sketchfab.com/pilot"],"thumbnails":["images":[["width":100,"url":"https://media.sketchfab.com/s.jpg"],["width":448,"url":"https://media.sketchfab.com/m.jpg"]]]]}
let usable=BlenderRender.modelResult(sfModel(uidA,"CC Attribution",90000),paths:searchPaths)!
precondition(usable["thumbnail"] as? String=="https://media.sketchfab.com/m.jpg" && usable["author"] as? String=="pilot" && usable["animations"] as? Int==1 && (usable["url"] as? String ?? "").hasSuffix(uidA))
precondition(BlenderRender.modelResult(sfModel(uidB,"CC Attribution",90000),paths:searchPaths)==nil,"not downloadable without login")
precondition(BlenderRender.modelResult(sfModel(uidA,"CC Attribution-NonCommercial",90000),paths:searchPaths)==nil,"non-commercial dropped")
precondition(BlenderRender.modelResult(sfModel(uidA,"CC Attribution",2_000_000),paths:searchPaths)==nil,"too heavy dropped")
// Full render through the fake Blender inside the sandbox.
var updates:[[String:Any]]=[]
r.onUpdate={updates.append($0)}
func run(_ body:[String:Any]) -> [String:Any] {
 updates=[];r.render(body)
 let deadline=Date().addingTimeInterval(120)
 while Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)); if let last=updates.last,["completed","preview","error","cancelled"].contains(last["status"] as? String ?? "") { return last } }
 fatalError("render timeout")
}
let done=run(["requestId":"r1","projectId":"p","clipId":"c1","mode":"script","script":"box()","duration":2.0,"fps":24,"aspectRatio":"16:9","quality":"draft"])
precondition(done["status"] as? String=="completed","render completes: \(done)")
precondition(updates.contains { $0["status"] as? String=="running" && ($0["message"] as? String ?? "").contains("khung") },"progress is reported")
let clip=AVURLAsset(url:URL(fileURLWithPath:done["path"] as! String))
precondition(abs(clip.duration.seconds-2)<0.1,"48 frames at 24 fps make 2 seconds, got \(clip.duration.seconds)")
let track=clip.tracks(withMediaType:.video).first!;precondition(track.naturalSize==CGSize(width:960,height:540))
precondition(done["requestId"] as? String=="r1" && done["clipId"] as? String=="c1" && done["projectId"] as? String=="p")
precondition(!fm.fileExists(atPath:home.appendingPathComponent("escaped.txt").path),"the sandbox kept writes inside the job folder")
let jobs=(try? fm.contentsOfDirectory(atPath:root.appendingPathComponent("blender-jobs").path)) ?? [];precondition(jobs.isEmpty,"job folders are cleaned up")
let preview=run(["requestId":"pv","clipId":"c1","mode":"script","script":"box()","duration":1.0,"fps":24,"preview":true])
let stills=preview["paths"] as? [String] ?? []
precondition(preview["status"] as? String=="preview" && stills.count==4 && stills.allSatisfy { fm.fileExists(atPath:$0) && $0.hasSuffix("-blender-preview.jpg") },"preview returns JPEG stills: \(preview)")
let imageClip=run(["requestId":"img","clipId":"c2","mode":"image","fps":24,"quality":"draft","shots":[["path":shotA.path,"seconds":1.0,"move":"push"]],"overlays":["dust":0.5]])
precondition(imageClip["status"] as? String=="completed","image clip renders: \(imageClip)")
// Driver errors surface with their message.
let failed=run(["requestId":"r2","mode":"script","script":"FAIL","duration":1.0,"fps":24])
precondition(failed["status"] as? String=="error" && (failed["message"] as? String ?? "").contains("Script dựng cảnh lỗi"),"\(failed)")
// Cancel stops Blender.
updates=[];r.render(["requestId":"r3","mode":"script","script":"SLOW","duration":3.0,"fps":24])
let started=Date();while Date().timeIntervalSince(started)<1.0 { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
precondition(r.busy);r.render(["requestId":"r4","mode":"script","script":"box()"]);RunLoop.current.run(until:Date().addingTimeInterval(0.3));precondition(updates.contains { $0["requestId"] as? String=="r4" && $0["status"] as? String=="error" },"one render at a time")
r.cancel()
let stopDeadline=Date().addingTimeInterval(20);while Date()<stopDeadline && !(updates.last?["status"] as? String=="cancelled") { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
precondition(updates.last?["status"] as? String=="cancelled" && !r.busy,"cancel")
print("Blender render passed: free model search filters, image mode jobs and subject separation, Poly Haven plans and installs, user model validation, film look, version detection, job validation, sandboxed run with progress, PNG frames to H.264, driver errors, single render, cancel, job cleanup")
