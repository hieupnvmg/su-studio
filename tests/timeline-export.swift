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
print("Timeline export passed: MP4 1080p, 4 seconds, red/portrait-blue frames, narration, trim, retiming, narration across cover visuals and invalid input guards")
