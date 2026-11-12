import Cocoa
import AVFoundation
let testRoot=URL(fileURLWithPath:CommandLine.arguments[1])
let folder=testRoot.appendingPathComponent("assets")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func makeVideo(_ name:String,_ width:Int,_ height:Int,_ color:NSColor) throws {
 let url=folder.appendingPathComponent(name);try? FileManager.default.removeItem(at:url)
 let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
 let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height])
 let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height])
 writer.add(input);writer.startWriting();writer.startSession(atSourceTime:.zero)
 for frame in 0..<60 {
  while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.001) }
  var pixel:CVPixelBuffer?;CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
  CVPixelBufferLockBaseAddress(pixel!,[])
  let ctx=CGContext(data:CVPixelBufferGetBaseAddress(pixel!),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel!),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
  ctx.setFillColor(color.cgColor);ctx.fill(CGRect(x:0,y:0,width:width,height:height));CVPixelBufferUnlockBaseAddress(pixel!,[])
  assert(adaptor.append(pixel!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
 }
 input.markAsFinished();let sem=DispatchSemaphore(value:0);writer.finishWriting {sem.signal()};sem.wait();assert(writer.status == .completed)
}
try makeVideo("red.mp4",640,360,.red);try makeVideo("blue.mp4",360,640,.blue)
let temporary=folder.appendingPathComponent("download.tmp")
try FileManager.default.copyItem(at:folder.appendingPathComponent("red.mp4"),to:temporary)
let saved=try PlenXVideo.storeDownloadedVideo(temporary,in:folder)
assert(saved.url.pathExtension=="mp4" && abs(saved.duration-2)<0.05)
let invalidDownload=folder.appendingPathComponent("invalid.tmp");try Data("not a video".utf8).write(to:invalidDownload)
let before=try FileManager.default.contentsOfDirectory(atPath:folder.path).count
do { _=try PlenXVideo.storeDownloadedVideo(invalidDownload,in:folder);fatalError("invalid download accepted") } catch {}
let after=try FileManager.default.contentsOfDirectory(atPath:folder.path).count;assert(after==before)
let timeline=StudioTimeline(root:testRoot)
let voice=folder.appendingPathComponent("voice.wav").path
let entries:[[String:Any]]=[
 ["id":"one","path":folder.appendingPathComponent("red.mp4").path,"trimStart":0.25,"trimEnd":1.75,"duration":2.0,"audioPath":voice],
 ["id":"two","path":folder.appendingPathComponent("blue.mp4").path,"trimStart":0.0,"duration":2.0,"audioPath":voice]]
let (composition,video,mix,duration)=try timeline.compose(entries)
assert(abs(duration-4)<0.05);assert(video.renderSize==CGSize(width:1920,height:1080));assert(mix.inputParameters.count==2)
var fractional=[entries[0]]
fractional[0]["duration"]=AVURLAsset(url:URL(fileURLWithPath:voice)).duration.seconds
let (fractionalComposition,fractionalVideo,_,_)=try timeline.compose(fractional)
assert(fractionalVideo.isValid(for:fractionalComposition,timeRange:CMTimeRange(start:.zero,duration:fractionalComposition.duration),validationDelegate:nil))
assert(fractionalComposition.duration.seconds>=AVURLAsset(url:URL(fileURLWithPath:voice)).duration.seconds)
let output=testRoot.appendingPathComponent("render.mp4");try? FileManager.default.removeItem(at:output)
let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPreset1920x1080)!
exporter.outputURL=output;exporter.outputFileType = .mp4;exporter.videoComposition=video;exporter.audioMix=mix
var done=false;exporter.exportAsynchronously {done=true}
let deadline=Date().addingTimeInterval(60)
while !done && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.1))}
assert(exporter.status == .completed,exporter.error?.localizedDescription ?? "export timeout")
let asset=AVURLAsset(url:output);assert(abs(asset.duration.seconds-4) < 0.1);assert(!asset.tracks(withMediaType:.audio).isEmpty)
let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
let red=NSBitmapImageRep(cgImage:try generator.copyCGImage(at:CMTime(seconds:0.5,preferredTimescale:600),actualTime:nil)).colorAt(x:960,y:540)!.usingColorSpace(.deviceRGB)!
let blue=NSBitmapImageRep(cgImage:try generator.copyCGImage(at:CMTime(seconds:2.5,preferredTimescale:600),actualTime:nil)).colorAt(x:960,y:540)!.usingColorSpace(.deviceRGB)!
assert(red.redComponent > 0.7 && red.blueComponent < 0.3);assert(blue.blueComponent > 0.7 && blue.redComponent < 0.3)
var invalid=entries;invalid[0]["duration"]=0.5
do { _=try timeline.compose(invalid);fatalError("voice truncation accepted") } catch {}
invalid=entries;invalid[0]["path"]="/etc/passwd"
do { _=try timeline.compose(invalid);fatalError("external path accepted") } catch {}
invalid=entries;invalid[0]["trimEnd"]=99.0
do { _=try timeline.compose(invalid);fatalError("invalid trim accepted") } catch {}
// One narration spread across two cover visuals in the same group.
let redPath=folder.appendingPathComponent("red.mp4").path,bluePath=folder.appendingPathComponent("blue.mp4").path
let grouped:[[String:Any]]=[["id":"lead","path":redPath,"duration":0.6,"audioPath":voice,"narrationGroup":"lead"],["id":"cover","path":bluePath,"duration":0.6,"narrationGroup":"lead"]]
let (groupComposition,groupVideo,groupMix,groupDuration)=try timeline.compose(grouped)
assert(abs(groupDuration-1.2)<0.05,"group keeps each visual's length");assert(groupMix.inputParameters.count==1)
assert(groupVideo.isValid(for:groupComposition,timeRange:CMTimeRange(start:.zero,duration:groupComposition.duration),validationDelegate:nil))
var ungrouped=grouped;ungrouped[0]["narrationGroup"]=nil;ungrouped[1]["narrationGroup"]=nil
do { _=try timeline.compose(ungrouped);fatalError("ungrouped short clip accepted") } catch {}
var tight=grouped;tight[0]["duration"]=0.5;tight[1]["duration"]=0.5
let (tightComposition,tightVideo,_,tightDuration)=try timeline.compose(tight)
assert(tightDuration>=AVURLAsset(url:URL(fileURLWithPath:voice)).duration.seconds-0.001,"last cover stretches to the end of the voice")
assert(tightVideo.isValid(for:tightComposition,timeRange:CMTimeRange(start:.zero,duration:tightComposition.duration),validationDelegate:nil))
var short=grouped;short[1]["duration"]=0.2
do { _=try timeline.compose(short);fatalError("group shorter than voice accepted") } catch {}
// Short 9:16: blurred fill behind landscape clips, centre crop, captions burned in.
let chunks=FrameStyle.captions("[calm] Năm 938, Ngô Quyền đóng cọc trên sông Bạch Đằng. Quân Nam Hán thua to!",start:2,duration:6,maxWords:6)
assert(chunks.count>=3 && abs(chunks.first!.start-2)<0.001 && abs(chunks.last!.end-8)<0.001,"captions cover the voice")
assert(!chunks.contains { $0.text.contains("[") },"audio tags are not shown")
assert(chunks.allSatisfy { $0.text.split(separator:" ").count<=8 })
func exportShort(_ items:[[String:Any]],_ options:[String:Any],_ name:String) throws -> AVURLAsset {
 let (c,v,m,_)=try timeline.compose(items,options:options)
 assert(v.renderSize==CGSize(width:1080,height:1920));assert(v.customVideoCompositorClass != nil)
 let out=testRoot.appendingPathComponent(name);try? FileManager.default.removeItem(at:out)
 let e=AVAssetExportSession(asset:c,presetName:AVAssetExportPresetHighestQuality)!
 e.outputURL=out;e.outputFileType = .mp4;e.videoComposition=v;e.audioMix=m
 var finished=false;e.exportAsynchronously {finished=true}
 let limit=Date().addingTimeInterval(90)
 while !finished && Date()<limit {RunLoop.current.run(until:Date().addingTimeInterval(0.1))}
 assert(e.status == .completed,e.error?.localizedDescription ?? "short export timeout")
 return AVURLAsset(url:out)
}
func pixel(_ asset:AVURLAsset,_ t:Double,_ x:Int,_ y:Int) throws -> NSColor {
 let g=AVAssetImageGenerator(asset:asset);g.appliesPreferredTrackTransform=true;g.requestedTimeToleranceBefore = .zero;g.requestedTimeToleranceAfter = .zero
 return NSBitmapImageRep(cgImage:try g.copyCGImage(at:CMTime(seconds:t,preferredTimescale:600),actualTime:nil)).colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
}
var shortEntries=entries;shortEntries[0]["captionText"]="Xin chào Việt Nam"
let shortAsset=try exportShort(shortEntries,["format":"short"],"short.mp4")
let shortTrack=shortAsset.tracks(withMediaType:.video).first!
let shortSize=shortTrack.naturalSize.applying(shortTrack.preferredTransform)
assert(abs(abs(shortSize.width)-1080)<2 && abs(abs(shortSize.height)-1920)<2,"short exports 1080x1920, got \(shortSize)")
assert(!shortAsset.tracks(withMediaType:.audio).isEmpty)
let centre=try pixel(shortAsset,0.5,540,960);assert(centre.redComponent>0.7 && centre.blueComponent<0.3,"landscape clip centred")
let top=try pixel(shortAsset,0.5,540,120);assert(top.redComponent>0.3 && top.blueComponent<0.3,"blurred fill instead of black bars")
let portrait=try pixel(shortAsset,2.5,540,960);assert(portrait.blueComponent>0.7,"portrait clip fills the frame")
var white=false
let g=AVAssetImageGenerator(asset:shortAsset);g.appliesPreferredTrackTransform=true;g.requestedTimeToleranceBefore = .zero;g.requestedTimeToleranceAfter = .zero
let captionFrame=NSBitmapImageRep(cgImage:try g.copyCGImage(at:CMTime(seconds:0.5,preferredTimescale:600),actualTime:nil))
for y in stride(from:1280,through:1410,by:4) { for x in stride(from:150,through:930,by:3) { let c=captionFrame.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!; if c.redComponent>0.85 && c.greenComponent>0.85 && c.blueComponent>0.85 { white=true } } }
assert(white,"caption is burned into the lower third")
let noCaption=NSBitmapImageRep(cgImage:try g.copyCGImage(at:CMTime(seconds:2.5,preferredTimescale:600),actualTime:nil))
var whiteLater=false
for y in stride(from:1280,through:1410,by:4) { for x in stride(from:150,through:930,by:3) { let c=noCaption.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!; if c.redComponent>0.85 && c.greenComponent>0.85 && c.blueComponent>0.85 { whiteLater=true } } }
assert(!whiteLater,"entries without captionText show no caption")
let cropAsset=try exportShort([entries[0]],["format":"short","fill":"crop","captions":false],"crop.mp4")
let corner=try pixel(cropAsset,0.5,40,60);assert(corner.redComponent>0.7 && corner.blueComponent<0.3,"crop fills the whole frame")
// Plain 16:9 stays on the built-in layer path.
let (_,plainVideo,_,_)=try timeline.compose(entries);assert(plainVideo.customVideoCompositorClass == nil)
// The assets folder may not exist yet when the app starts; it is created by the first import or render.
let lateRoot=testRoot.appendingPathComponent("late-\(UUID().uuidString)")
try FileManager.default.createDirectory(at:lateRoot,withIntermediateDirectories:true)
let lateTimeline=StudioTimeline(root:lateRoot)
let lateAssets=lateRoot.appendingPathComponent("assets");try FileManager.default.createDirectory(at:lateAssets,withIntermediateDirectories:true)
try FileManager.default.copyItem(at:folder.appendingPathComponent("red.mp4"),to:lateAssets.appendingPathComponent("late.mp4"))
let (_,_,_,lateDuration)=try lateTimeline.compose([["id":"late","path":lateAssets.appendingPathComponent("late.mp4").path,"duration":1.0]])
precondition(abs(lateDuration-1)<0.05,"files in an assets folder created after start are found")
print("Timeline export passed: assets folder created after start, MP4 1080p, Short 1080x1920 with blurred fill, crop and burned-in captions, 4 seconds, red/portrait-blue frames, narration, trim, retiming, narration across cover visuals and invalid input guards")
