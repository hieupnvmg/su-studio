import Cocoa
import AVFoundation
import AVKit
import ImageIO

final class PlenXVideo: NSObject, URLSessionTaskDelegate {
    let root: URL
    var onUpdate: (([String:Any])->Void)?
    private(set) var busy = false
    private let configuration: URLSessionConfiguration
    private lazy var session: URLSession = {
        let c = configuration; c.timeoutIntervalForRequest = 90; c.timeoutIntervalForResource = 300; c.httpShouldSetCookies = false
        return URLSession(configuration:c, delegate:self, delegateQueue:nil)
    }()
    init(root: URL, configuration: URLSessionConfiguration = .ephemeral) { self.root = root.appendingPathComponent("assets").standardizedFileURL.resolvingSymlinksInPath(); self.configuration = configuration; super.init() }
    // Set before a failed api() completion: whether PlenX definitely refused (no task) and its reason.
    var lastFailure:(rejected:Bool,detail:String) = (false,"")
    func api(_ path:String, key:String, payload:[String:Any]? = nil, completion:@escaping ([String:Any]?,Int)->Void) {
        var r = URLRequest(url:URL(string:"https://api.plenxai.com/api/v1/developer"+path)!)
        r.setValue(key,forHTTPHeaderField:"X-API-Key")
        if let payload = payload { r.httpMethod = "POST"; r.setValue("application/json",forHTTPHeaderField:"Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject:payload) }
        session.dataTask(with:r) { data,response,error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, (200..<300).contains(code), let data = data, let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],json["success"] as? Bool != false else {
                self.lastFailure = (error == nil && PlenXFailure.rejected(status:code,data:data), PlenXFailure.detail(data)); completion(nil,code); return
            }; completion(json,code)
        }.resume()
    }
    func request(_ body:[String:Any], key:String) {
        let rid = body["requestId"] as? String ?? ""
        func reply(_ result:[String:Any]) { DispatchQueue.main.async { self.busy = false; var r = result; r["requestId"] = rid; self.onUpdate?(r) } }
        guard !busy, key.hasPrefix("pk_") else { reply(["status":"error","message":"Kiểm tra key PlenX hoặc đợi yêu cầu hiện tại."]); return }; busy = true
        let kind = body["kind"] as? String ?? ""
        if kind == "status" {
            guard let task = body["taskId"] as? String, task.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil else { reply(["status":"error","message":"Mã tác vụ không hợp lệ."]); return }
            api("/status/"+task,key:key) { json,code in
                // No HTTP response at all: the Mac was asleep or the network is not back yet. The task is still on PlenX; keep checking.
                guard let json = json else { reply(code == 0 ? ["status":"queued","taskId":task,"transient":true,"message":"Mất kết nối mạng (máy vừa ngủ?). Sẽ tự kiểm tra lại tác vụ, không tạo lượt mới."] : ["status":"error","taskId":task,"message":"Chưa đọc được tác vụ (HTTP \(code))\(PlenXFailure.reason(self.lastFailure.detail)). Kiểm tra lại, không tạo lại tự động."]); return }
                let state = json["status"] as? String ?? "queued"
                if ["error","failed"].contains(state) { reply(["status":"failed","taskId":task,"message":"PlenX báo tạo video thất bại. Kiểm tra lịch sử trước khi tạo lại."]); return }
                guard ["completed","succeeded"].contains(state) else { reply(["status":"queued","taskId":task,"message":"PlenX đang tạo video…"]); return }
                guard let raw = json["result_url"] as? String,let url = URL(string:raw),url.scheme == "https",url.user == nil,url.password == nil else { reply(["status":"error","taskId":task,"message":"Chưa có URL video hợp lệ."]); return }
                self.session.downloadTask(with:url) { file,response,error in
                    if error != nil || response == nil { reply(["status":"queued","taskId":task,"transient":true,"message":"Video đã tạo xong, đang chờ mạng để tải về…"]); return }
                    guard error == nil,let file = file,let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 1_000_000_000 else { reply(["status":"error","taskId":task,"message":"Video đã tạo nhưng tải chưa thành công. Kiểm tra lại tác vụ để tải, không cần tạo mới."]); return }
                    do {
                        let saved = try Self.storeDownloadedVideo(file, in:self.root)
                        reply(["status":"completed","taskId":task,"path":saved.url.path,"name":saved.url.lastPathComponent,"duration":saved.duration])
                    } catch { reply(["status":"error","taskId":task,"message":error.localizedDescription]) }
                }.resume()
            };return
        }
        guard kind == "generate",let prompt = body["prompt"] as? String,!prompt.isEmpty,prompt.count<=20000,
              let model = body["model"] as? String,model.range(of:"^[A-Za-z0-9._-]+$",options:.regularExpression) != nil else { reply(["status":"error","message":"Thiếu prompt hoặc model video."]);return }
        let endpoint = body["endpoint"] as? String ?? "/developer/generate/video"
        guard ["/developer/generate/video","/developer/generate/video-omni"].contains(endpoint) else { reply(["status":"error","message":"Model chưa có đường API video phù hợp."]);return }
        let multi = body["referencePaths"] != nil
        let paths = multi ? (body["referencePaths"] as? [String] ?? []) : [body["imagePath"] as? String ?? ""]
        let limits = ["veo-3.1-lite":3,"veo-3.1-fast":3,"veo-3.1-relaxed":3,"veo-3.1-quality":3,"grok-video":8,"grok-video-1.5":8,"omni-flash-video":10,"omni-flash-video-no-logo":10,"wan-3.0":10,"flux-3":10,"kling-4.0":8,"kling-4.0-omni":8,"minimax-h3":9,"minimax-h3-turbo":9]
        let duration = body["duration"] as? Int ?? 5,quality = (body["quality"] as? String ?? "720p").lowercased()
        guard !paths.isEmpty, paths.count <= (multi ? (limits[model] ?? 0) : 1), !multi || endpoint.hasSuffix("video-omni"),
              !multi || quality != "360p", !multi || model != "veo-3.1-lite" || duration == 8 else { reply(["status":"error","message":"Số ảnh, model hoặc chất lượng chưa phù hợp chế độ nhiều ảnh. Kiểm tra trước khi tạo lại."]);return }
        // Validate every local image before uploading any of them. Preserve input order.
        var images:[Data]=[]
        for raw in paths {
            let file = URL(fileURLWithPath:raw).standardizedFileURL.resolvingSymlinksInPath()
            guard file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == root.standardizedFileURL.resolvingSymlinksInPath().path, let source = CGImageSourceCreateWithURL(file as CFURL,nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { reply(["status":"error","message":"Không đọc được một ảnh tham chiếu trong dự án. Chưa gửi tạo video."]);return }
            let png = NSMutableData();guard let out = CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil) else { reply(["status":"error","message":"Chưa chuẩn bị được ảnh."]);return };CGImageDestinationAddImage(out,image,nil);guard CGImageDestinationFinalize(out) else { reply(["status":"error","message":"Không chuyển được ảnh."]);return };images.append(png as Data)
        }
        func upload(_ index:Int,_ urls:[String]) {
            if index < images.count {
                self.api("/media-upload/direct",key:key,payload:["image_data":"data:image/png;base64,"+images[index].base64EncodedString(),"filename":"reference-\(index+1).png","media_type":"image","aspect_ratio":"16:9"]) { uploaded,code in
                    guard let raw = (uploaded?["url"] ?? uploaded?["public_url"]) as? String, let url=URL(string:raw),url.scheme=="https",url.user==nil,url.password==nil else { reply(["status":"failed","rejected":true,"message":"Chưa tải được ảnh tham chiếu \(index+1) lên PlenX (HTTP \(code))\(PlenXFailure.reason(self.lastFailure.detail)). Chưa gửi yêu cầu tạo video."]);return }
                    upload(index+1,urls+[raw])
                };return
            }
            let aspect = body["aspectRatio"] as? String == "9:16" ? "9:16" : "16:9"
            var payload: [String:Any] = ["model":model,"prompt":prompt,"duration":duration,"aspect_ratio":aspect]
            if multi { payload["reference_images"]=urls;payload["resolution"]=quality }
            else if endpoint.hasSuffix("video-omni") { payload["input_image_url"]=urls[0];payload["resolution"]=quality }
            else { payload["mode"]="i2v";payload["start_image_url"]=urls[0];payload["quality"]=quality }
            self.api(endpoint.replacingOccurrences(of:"/developer",with:""),key:key,payload:payload) { json,code in
                guard let task = json?["task_id"] as? String,!task.isEmpty else {
                    let failure:(rejected:Bool,detail:String) = json == nil ? self.lastFailure : (false,"")
                    if failure.rejected { reply(["status":"failed","rejected":true,"message":"PlenX từ chối yêu cầu tạo video (HTTP \(code))\(PlenXFailure.reason(failure.detail)). Chưa có tác vụ nào được tạo; sửa prompt, ảnh hoặc model rồi tạo lại."]);return }
                    reply(["status":"error","message":"Chưa xác nhận được yêu cầu tạo video (HTTP \(code))\(PlenXFailure.reason(failure.detail)). Kiểm tra lịch sử PlenX trước khi tạo lại; có thể đã dùng credit."]);return
                };reply(["status":"queued","taskId":task,"message":"PlenX đã nhận yêu cầu tạo video…"])
            }
        }
        upload(0,[])
    }

    static func storeDownloadedVideo(_ temporary: URL, in folder: URL) throws -> (url:URL,duration:Double) {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        // AVFoundation cannot identify a URLSession .tmp file as MP4 on macOS.
        let destination=folder.appendingPathComponent(UUID().uuidString+"-plenx.mp4")
        try FileManager.default.copyItem(at:temporary,to:destination)
        let asset=AVURLAsset(url:destination)
        guard !asset.tracks(withMediaType:.video).isEmpty,asset.duration.seconds.isFinite,asset.duration.seconds>0 else {
            try? FileManager.default.removeItem(at:destination)
            throw NSError(domain:"PlenXVideo",code:1,userInfo:[NSLocalizedDescriptionKey:"File tải về chưa phải video đọc được. Bấm kiểm tra tác vụ để tải lại; không cần tạo lượt mới."])
        }
        return(destination,asset.duration.seconds)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
}

final class StudioTimeline: NSObject, NSWindowDelegate {
    let root: URL
    var onUpdate: (([String:Any])->Void)?
    private var preview: NSWindow?
    private var player: AVPlayer?
    private var exporter: AVAssetExportSession?
    private var timer: Timer?
    private var preparing = false
    var busy: Bool { exporter != nil || preparing }
    init(root:URL) { self.root = root.appendingPathComponent("assets").standardizedFileURL.resolvingSymlinksInPath(); super.init() }
    func windowWillClose(_ notification: Notification) { player?.pause() }
    private func asset(_ path:String?) throws -> AVURLAsset {
        guard let path = path else { throw issue("Thiếu file video hoặc giọng đọc.") }
        let url = URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == root.standardizedFileURL.resolvingSymlinksInPath().path,FileManager.default.fileExists(atPath:url.path) else { throw issue("Không tìm thấy file trong tài nguyên dự án. Nhập lại file bị thiếu.") }
        return AVURLAsset(url:url)
    }
    private func issue(_ message:String)->NSError { NSError(domain:"StudioTimeline",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    func command(_ body:[String:Any]) {
        let kind = body["command"] as? String ?? "preview"
        if kind == "cancel" { exporter?.cancelExport(); return }
        guard !busy else { onUpdate?(["status":"error","message":"Đang xuất MP4. Đợi hoàn tất hoặc hủy xuất trước."]);return }
        if kind == "previewSource" {
            do {
                let source = try asset(body["path"] as? String)
                guard !source.tracks(withMediaType:.video).isEmpty else { throw issue("Clip chưa có video đọc được.") }
                player?.pause();preview?.close()
                let player = AVPlayer(playerItem:AVPlayerItem(asset:source));self.player=player
                let view=AVPlayerView(frame:NSRect(x:0,y:0,width:1000,height:600));view.player=player;view.controlsStyle = .floating
                let window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
                window.delegate=self;window.title="Xem clip gốc";window.contentView=view;window.isReleasedWhenClosed=false;window.center();window.makeKeyAndOrderFront(nil);preview=window;player.play()
                onUpdate?(["status":"preview","message":"Đang xem clip gốc, giữ nguyên tốc độ và âm thanh nguồn."])
            } catch { onUpdate?(["status":"error","message":error.localizedDescription]) }
            return
        }
        guard let entries = body["entries"] as? [[String:Any]], !entries.isEmpty,entries.count<=500 else { onUpdate?(["status":"error","message":"Timeline chưa có clip."]);return }
        if kind == "measure" {
            var values:[[String:Any]]=[]
            for entry in entries {
                let voice = try? asset(entry["audioPath"] as? String), video = try? asset(entry["path"] as? String)
                let audioDuration = voice?.duration.seconds ?? 0, videoDuration = video?.duration.seconds ?? 0
                let duration = audioDuration.isFinite && audioDuration>0 ? audioDuration : videoDuration
                if duration.isFinite && duration>0 { values.append(["id":entry["id"] as? String ?? "","duration":duration,"videoDuration":videoDuration.isFinite ? videoDuration:0,"audioDuration":audioDuration.isFinite ? audioDuration:0]) }
            }
            onUpdate?(["status":"measured","values":values]);return
        }
        var output: URL?
        if kind == "export" {
            let panel = NSSavePanel();panel.nameFieldStringValue = Self.frameOptions(body).short ? "Su-Studio-Short.mp4" : "Su-Studio.mp4";panel.allowedFileTypes=["mp4"]
            guard panel.runModal() == .OK,let url = panel.url else { onUpdate?(["status":"cancelled","message":"Đã hủy chọn nơi lưu."]);return };output = url
        }
        preparing = true
        onUpdate?(["status":"preparing","message":"Đang dựng timeline…"])
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let (composition,video,mix,duration) = try self.compose(entries,options:body)
                let short = Self.frameOptions(body).short
                DispatchQueue.main.async {
                    self.preparing = false
                    if let output = output {
                        guard let exporter = AVAssetExportSession(asset:composition,presetName:short ? AVAssetExportPresetHighestQuality : AVAssetExportPreset1920x1080) else { self.onUpdate?(["status":"error","message":"Máy này chưa tạo được bộ xuất MP4."]);return }
                        exporter.outputURL=output;exporter.outputFileType = .mp4;exporter.videoComposition=video;exporter.audioMix=mix;exporter.shouldOptimizeForNetworkUse=true
                        self.exporter=exporter
                        self.timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in self?.onUpdate?(["status":"exporting","progress":Double(exporter.progress),"message":"Đang xuất MP4… \(Int(exporter.progress*100))%"] ) }
                        exporter.exportAsynchronously {
                            DispatchQueue.main.async {
                                self.timer?.invalidate();self.timer=nil;self.exporter=nil
                                if exporter.status == .completed {
                                    // Re-read the file before calling it done: size, length, sound and black frames.
                                    let narrated=entries.contains { !($0["audioPath"] as? String ?? "").isEmpty } || (body["music"] as? [String:Any])?["path"] != nil
                                    self.onUpdate?(["status":"checking","message":"Đã xuất MP4, đang tự kiểm tra file…"])
                                    DispatchQueue.global(qos:.userInitiated).async {
                                        let issues=ExportCheck.inspect(output,expected:duration,size:video.renderSize,sound:narrated)
                                        DispatchQueue.main.async {
                                            self.onUpdate?(["status":"completed","path":output.path,"issues":issues,"message":"Đã xuất MP4: \(output.lastPathComponent). "+(issues.isEmpty ? "Tự kiểm tra: đúng kích thước và thời lượng, có tiếng, không có đoạn đen." : "Tự kiểm tra thấy: "+issues.joined(separator:" "))])
                                            NSWorkspace.shared.activateFileViewerSelecting([output])
                                        }
                                    }
                                }
                                else { self.onUpdate?(["status":exporter.status == .cancelled ? "cancelled":"error","message":exporter.status == .cancelled ? "Đã hủy xuất.":"Xuất MP4 thất bại. Kiểm tra dung lượng và định dạng clip. \(exporter.error?.localizedDescription ?? "")"]) }
                            }
                        }
                    } else {
                        self.player?.pause();self.preview?.close()
                        let item=AVPlayerItem(asset:composition);item.videoComposition=video;item.audioMix=mix
                        let player=AVPlayer(playerItem:item);self.player=player
                        let view=AVPlayerView(frame:short ? NSRect(x:0,y:0,width:440,height:782) : NSRect(x:0,y:0,width:1000,height:600));view.player=player;view.controlsStyle = .floating
                        let window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
                        window.delegate=self;window.title="Xem thử timeline · \(Int(duration)) giây";window.contentView=view;window.isReleasedWhenClosed=false;window.center();window.makeKeyAndOrderFront(nil);self.preview=window;player.play()
                        self.onUpdate?(["status":"preview","message":"Đã mở trình xem timeline với video và lời kể."])
                    }
                }
            } catch { DispatchQueue.main.async { self.preparing = false; self.onUpdate?(["status":"error","message":error.localizedDescription]) } }
        }
    }
    /// Output frame for a request: Short exports 1080×1920; fill is fit (black bars), blur (blurred copy behind) or crop.
    /// Music volume keyframes (seconds, volume): fade in over 1 s, duck to 30% around each narration
    /// (closer than 0.6 s apart counts as one), fade out over the last 1.5 s.
    static func musicVolumePoints(total:Double,voices:[(Double,Double)],base:Double) -> [(Double,Double)] {
        guard total>0 else { return [] }
        let duck=base*0.3
        var merged:[(Double,Double)]=[]
        for v in voices.filter({ $0.1>$0.0 }).sorted(by:{ $0.0<$1.0 }) {
            if let last=merged.last,v.0-last.1<0.6 { merged[merged.count-1].1=max(last.1,v.1) } else { merged.append(v) }
        }
        func level(_ t:Double)->Double {
            var v=base
            for (s,e) in merged {
                if t>=s && t<=e { v=duck }
                else if t>s-0.3 && t<s { v=min(v,base-(base-duck)*(t-(s-0.3))/0.3) }
                else if t>e && t<e+0.4 { v=min(v,duck+(base-duck)*(t-e)/0.4) }
            }
            let fadeIn=min(1,total/3),fadeOut=min(1.5,total/3)
            if t<fadeIn { v*=t/fadeIn }
            if t>total-fadeOut { v*=max(0,(total-t)/fadeOut) }
            return v
        }
        var times:Set<Double>=[0,total,min(1,total/3),max(0,total-min(1.5,total/3))]
        for (s,e) in merged { for x in [s-0.3,s,e,e+0.4] where x>0 && x<total { times.insert(x) } }
        return times.sorted().map { ($0,level($0)) }
    }
    /// karaoke: highlight the word being spoken when the narration has word timings (default on).
    static func frameOptions(_ options:[String:Any]) -> (short:Bool,fill:String,captions:Bool,size:CGSize,karaoke:Bool) {
        let short = options["format"] as? String == "short"
        let requested = options["fill"] as? String ?? ""
        let fill = ["fit","blur","crop"].contains(requested) ? requested : (short ? "blur" : "fit")
        return (short,fill,options["captions"] as? Bool ?? short,short ? CGSize(width:1080,height:1920) : CGSize(width:1920,height:1080),options["captionStyle"] as? String != "phrase")
    }
    func compose(_ entries:[[String:Any]],options:[String:Any]=[:]) throws -> (AVMutableComposition,AVMutableVideoComposition,AVMutableAudioMix,Double) {
        let composition=AVMutableComposition(),video=AVMutableVideoComposition(),mix=AVMutableAudioMix()
        let frame=Self.frameOptions(options),render=frame.size
        // The built-in layer path stays for plain 16:9 exports; anything framed or captioned uses the custom compositor.
        let custom=frame.short || frame.fill != "fit" || frame.captions
        let style=FrameStyle(size:render,fill:frame.fill)
        var instructions:[AVVideoCompositionInstructionProtocol]=[],audioParameters:[AVAudioMixInputParameters]=[]
        var cursor=CMTime.zero,voiceEnd=CMTime.zero,voices:[(Double,Double)]=[]
        func seconds(_ n:Double)->CMTime { CMTime(seconds:n,preferredTimescale:600) }
        // A scene's narration may run across consecutive entries sharing a narrationGroup (cover visuals).
        func sameGroup(_ i:Int,_ group:String?)->Bool { group != nil && i<entries.count && entries[i]["narrationGroup"] as? String == group }
        for (index,e) in entries.enumerated() {
            let source=try asset(e["path"] as? String)
            guard let src=source.tracks(withMediaType:.video).first,source.duration.seconds.isFinite else { throw issue("Clip \(index+1) không có video hợp lệ.") }
            let start=e["trimStart"] as? Double ?? 0,end=e["trimEnd"] as? Double ?? source.duration.seconds
            let target=e["duration"] as? Double ?? end-start
            guard start.isFinite,end.isFinite,target.isFinite,start>=0,end>start,end<=source.duration.seconds+0.05,target>=0.1,target<=3600 else { throw issue("Clip \(index+1): điểm cắt hoặc thời lượng chưa hợp lệ (file dài \(String(format:"%.2f",source.duration.seconds)) giây).") }
            // Container audio can end after the last video frame. Never stretch an empty video tail.
            let requested=CMTimeRange(start:seconds(start),duration:seconds(min(end,source.duration.seconds)-start))
            let range=CMTimeRangeGetIntersection(requested,otherRange:src.timeRange)
            let group=e["narrationGroup"] as? String
            var span=target,next=index+1
            while sameGroup(next,group) { span+=(entries[next]["duration"] as? Double ?? 0);next+=1 }
            let voiceLength: Double
            if let path=e["audioPath"] as? String,!path.isEmpty {
                voiceLength=try asset(path).duration.seconds
                guard voiceLength.isFinite,voiceLength>0,voiceLength<=span+0.1 else { throw issue(next>index+1 ? "Các hình phủ của clip \(index+1) ngắn hơn lời kể. Bấm Căn theo giọng đọc hoặc tăng thời lượng các hình." : "Clip \(index+1) ngắn hơn lời kể. Bấm Căn theo giọng đọc hoặc tăng thời lượng timeline.") }
                voiceEnd=CMTimeAdd(cursor,seconds(voiceLength));voices.append((cursor.seconds,cursor.seconds+voiceLength))
                if frame.captions {
                    // Real word timings saved with the ElevenLabs audio; older audio falls back to weighted chunks.
                    let timed=FrameStyle.loadWords(audioPath:path)
                    if !timed.isEmpty { style.captions+=FrameStyle.wordCaptions(timed,offset:cursor.seconds,limit:voiceLength,maxWords:frame.short ? 4 : 8,karaoke:frame.karaoke) }
                    else if let text=e["captionText"] as? String { style.captions+=FrameStyle.captions(text,start:cursor.seconds,duration:voiceLength,maxWords:frame.short ? 6 : 10) }
                }
            } else { voiceLength=0 }
            // Round UP to an output frame. Truncating the video time left the last
            // milliseconds of MP3 outside the instructions, invalidating the composition.
            // Inside a narration group only the last entry stretches to cover what is left of the voice.
            let remaining=max(0,CMTimeSubtract(voiceEnd,cursor).seconds)
            let slot=CMTime(value:Int64(ceil((sameGroup(index+1,group) ? target : max(target,remaining))*30)),timescale:30)
            guard range.isValid,range.duration.seconds>0 else { throw issue("Đoạn cắt không còn khung hình video.") }
            guard let track=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw issue("Không thêm được track video.") }
            try track.insertTimeRange(range,of:src,at:cursor);track.scaleTimeRange(CMTimeRange(start:cursor,duration:range.duration),toDuration:slot)
            let transformed=src.naturalSize.applying(src.preferredTransform),size=CGSize(width:abs(transformed.width),height:abs(transformed.height))
            guard size.width>0,size.height>0 else { throw issue("Kích thước clip không hợp lệ.") }
            if custom { instructions.append(FrameInstruction(timeRange:CMTimeRange(start:cursor,duration:slot),trackID:track.trackID,transform:src.preferredTransform,style:style)) } else {
            let scale=min(render.width/size.width,render.height/size.height),rect=CGRect(origin:.zero,size:src.naturalSize).applying(src.preferredTransform)
            var transform=src.preferredTransform.concatenating(CGAffineTransform(translationX:-rect.origin.x,y:-rect.origin.y))
            transform=transform.concatenating(CGAffineTransform(scaleX:scale,y:scale)).concatenating(CGAffineTransform(translationX:(render.width-size.width*scale)/2,y:(render.height-size.height*scale)/2))
            let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:track);layer.setTransform(transform,at:cursor)
            let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=CMTimeRange(start:cursor,duration:slot);instruction.layerInstructions=[layer];instruction.backgroundColor=NSColor.black.cgColor;instructions.append(instruction)
            }
            if e["includeOriginalAudio"] as? Bool == true,let sound=source.tracks(withMediaType:.audio).first,let audio=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(range,of:sound,at:cursor);audio.scaleTimeRange(CMTimeRange(start:cursor,duration:range.duration),toDuration:slot)
                let params=AVMutableAudioMixInputParameters(track:audio);params.setVolume(0.35,at:cursor);audioParameters.append(params)
            }
            if let path=e["audioPath"] as? String,!path.isEmpty {
                let voice=try asset(path)
                guard let sound=voice.tracks(withMediaType:.audio).first,voice.duration.seconds.isFinite,voice.duration.seconds>0 else { throw issue("Lời kể clip \(index+1) không đọc được.") }
                guard voice.duration.seconds<=span+0.1 else { throw issue("Clip \(index+1) ngắn hơn lời kể. Bấm Căn theo giọng đọc hoặc tăng thời lượng timeline để giữ đủ lời.") }
                if let audio=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                    try audio.insertTimeRange(CMTimeRange(start:.zero,duration:voice.duration),of:sound,at:cursor)
                    let params=AVMutableAudioMixInputParameters(track:audio);params.setVolume(1,at:cursor);audioParameters.append(params)
                }
            }
            cursor=CMTimeAdd(cursor,slot)
        }
        // Background music: looped to the end, faded in/out and lowered under the narration.
        if let music=options["music"] as? [String:Any],let path=music["path"] as? String,!path.isEmpty,cursor.seconds>0 {
            let source=try asset(path)
            guard let sound=source.tracks(withMediaType:.audio).first,source.duration.seconds.isFinite,source.duration.seconds>=1 else { throw issue("File nhạc nền không đọc được. Chọn lại file nhạc.") }
            let total=cursor.seconds,base=min(1,max(0,(music["volume"] as? NSNumber)?.doubleValue ?? 0.25))
            if base>0,let audio=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                var at=0.0
                while at<total-0.01 {
                    let length=min(source.duration.seconds,total-at)
                    try audio.insertTimeRange(CMTimeRange(start:.zero,duration:seconds(length)),of:sound,at:seconds(at));at+=length
                }
                let params=AVMutableAudioMixInputParameters(track:audio)
                let points=Self.musicVolumePoints(total:total,voices:music["duck"] as? Bool == false ? [] : voices,base:base)
                params.setVolume(Float(points.first?.1 ?? base),at:.zero)
                for (a,b) in zip(points,points.dropFirst()) where b.0>a.0 {
                    params.setVolumeRamp(fromStartVolume:Float(a.1),toEndVolume:Float(b.1),timeRange:CMTimeRange(start:seconds(a.0),end:seconds(b.0)))
                }
                audioParameters.append(params)
            }
        }
        if custom { video.customVideoCompositorClass=StudioCompositor.self }
        video.renderSize=render;video.frameDuration=CMTime(value:1,timescale:30);video.instructions=instructions;mix.inputParameters=audioParameters
        guard video.isValid(for:composition,timeRange:CMTimeRange(start:.zero,duration:composition.duration),validationDelegate:nil) else { throw issue("Chưa căn được khung hình với lời kể. Hãy căn lại thời lượng trước khi xem thử.") }
        return(composition,video,mix,cursor.seconds)
    }
}

// MARK: - Checking an exported file

enum ExportCheck {
    /// Problems found in an exported MP4 (Vietnamese, ready to show); empty when it looks right.
    static func inspect(_ url: URL, expected: Double, size: CGSize, sound: Bool) -> [String] {
        let asset = AVURLAsset(url: url)
        var issues: [String] = []
        guard let track = asset.tracks(withMediaType: .video).first else { return ["File không có hình."] }
        let natural = track.naturalSize.applying(track.preferredTransform)
        if abs(abs(natural.width) - size.width) > 2 || abs(abs(natural.height) - size.height) > 2 { issues.append("Khung hình \(Int(abs(natural.width)))×\(Int(abs(natural.height))) khác \(Int(size.width))×\(Int(size.height)).") }
        let length = asset.duration.seconds
        if !length.isFinite || abs(length - expected) > 0.5 { issues.append("Thời lượng \(clock(length)) khác timeline \(clock(expected)).") }
        let black = blackRanges(asset, length: length)
        if !black.isEmpty { issues.append("Đoạn đen: " + black.map { clock($0.0) + "–" + clock($0.1) }.joined(separator: ", ") + ".") }
        if sound {
            if let levels = loudness(asset) {
                if levels.peak < 0.003 { issues.append("Video không có tiếng (lời kể hoặc nhạc bị câm).") }
                else if let gap = levels.silences.first { issues.append("Im lặng \(Int(gap.1 - gap.0)) giây từ \(clock(gap.0)).") }
            } else { issues.append("Video không có track âm thanh.") }
        }
        return issues
    }
    static func clock(_ s: Double) -> String { guard s.isFinite else { return "?" }; let n = Int(s.rounded()); return String(format: "%d:%02d", n / 60, n % 60) }

    /// Spans of at least 1 s whose sampled frames are almost black (first and last half second ignored: fades).
    static func blackRanges(_ asset: AVAsset, length: Double) -> [(Double, Double)] {
        guard length.isFinite, length > 1.2 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 96, height: 96)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10); generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        var ranges: [(Double, Double)] = [], start: Double?
        var t = 0.5
        while t < length - 0.5 {
            var dark = false
            if let image = try? generator.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) { dark = meanLuma(image) < 0.04 }
            if dark { start = start ?? t } else if let s = start { if t - s >= 1 { ranges.append((s, t)) }; start = nil }
            t += 0.5
        }
        if let s = start, length - 0.5 - s >= 1 { ranges.append((s, length - 0.5)) }
        return ranges
    }
    static func meanLuma(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return 1 }
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum = 0.0
        for i in 0..<(w * h) { sum += 0.2126 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.0722 * Double(p[i * 4 + 2]) }
        return sum / Double(w * h) / 255
    }

    /// Peak level and silent spans (≥ 4 s under about −46 dB) of the first audio track; nil without audio.
    static func loudness(_ asset: AVAsset) -> (peak: Double, silences: [(Double, Double)])? {
        guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var peak = 0.0, windowPeak = 0.0, count = 0, window = 0, silences: [(Double, Double)] = [], quietSince: Double?
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0, pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr, let raw = pointer else { continue }
            raw.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                for i in 0..<(length / 2) {
                    let v = abs(Double(samples[i])) / 32768; peak = max(peak, v); windowPeak = max(windowPeak, v); count += 1
                    if count == 4000 { // half a second at 8 kHz
                        let at = Double(window) * 0.5
                        if windowPeak < 0.005 { quietSince = quietSince ?? at } else if let q = quietSince { if at - q >= 4 { silences.append((q, at)) }; quietSince = nil }
                        window += 1; count = 0; windowPeak = 0
                    }
                }
            }
        }
        if let q = quietSince, Double(window) * 0.5 - q >= 4 { silences.append((q, Double(window) * 0.5)) }
        return (peak, silences)
    }
}

// MARK: - Framing and burned-in captions (Short 9:16, blurred fill, subtitles)

struct TimedCaption {
    let start: Double; let end: Double; let text: String
    var words: [String] = []
    /// Index into `words` drawn in the highlight colour (karaoke captions).
    var highlight: Int? = nil
}
struct TimedWord { let text: String; let start: Double; let end: Double }

final class FrameStyle {
    let size: CGSize
    let fill: String
    var captions: [TimedCaption] = []
    init(size: CGSize, fill: String) { self.size = size; self.fill = fill }
    var vertical: Bool { size.height > size.width }
    func caption(at seconds: Double) -> TimedCaption? { captions.first { seconds >= $0.start && seconds < $0.end } }

    /// Word timings saved beside an ElevenLabs audio file, in seconds from the start of that audio.
    static func loadWords(audioPath: String) -> [TimedWord] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: audioPath + ".words.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["words"] as? [[String: Any]] else { return [] }
        let words = list.compactMap { item -> TimedWord? in
            guard let text = item["text"] as? String, !text.isEmpty, let start = (item["start"] as? NSNumber)?.doubleValue,
                  let end = (item["end"] as? NSNumber)?.doubleValue, start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
            return TimedWord(text: text, start: start, end: end)
        }
        return zip(words, words.dropFirst()).allSatisfy({ $0.start <= $1.start }) ? words : []
    }

    /// Captions from real word timings: short chunks that break after punctuation, shown while they are spoken.
    /// With karaoke on, each chunk repeats once per word so the spoken word is highlighted.
    static func wordCaptions(_ words: [TimedWord], offset: Double, limit: Double, maxWords: Int, karaoke: Bool) -> [TimedCaption] {
        guard !words.isEmpty, maxWords > 0, limit > 0 else { return [] }
        var chunks: [[TimedWord]] = [], current: [TimedWord] = []
        for word in words where word.start < limit {
            current.append(word)
            let last = word.text.last.map { ".,;:!?…".contains($0) } ?? false
            if current.count >= maxWords || last && current.count >= 2 || word.text.last.map({ ".!?…".contains($0) }) == true { chunks.append(current); current = [] }
        }
        // A lone trailing word joins the previous chunk only when it continues that sentence without a pause.
        if !current.isEmpty {
            if current.count == 1, let i = chunks.indices.last, chunks[i].count < maxWords + 1, let prev = chunks[i].last,
               !(prev.text.last.map { ".!?…".contains($0) } ?? false), current[0].start - prev.end <= 0.8 { chunks[i] += current } else { chunks.append(current) }
        }
        var result: [TimedCaption] = []
        for (n, chunk) in chunks.enumerated() {
            let begin = chunk[0].start, lastEnd = min(limit, chunk[chunk.count - 1].end)
            // Hold until the next chunk unless there is a real pause, so captions do not flicker between words.
            let next = n + 1 < chunks.count ? chunks[n + 1][0].start : nil
            let finish = min(limit, next.map { $0 - lastEnd <= 0.8 ? $0 : lastEnd + 0.35 } ?? lastEnd + 0.35)
            let texts = chunk.map(\.text), text = texts.joined(separator: " ")
            guard finish > begin else { continue }
            if !karaoke { result.append(TimedCaption(start: offset + begin, end: offset + finish, text: text, words: texts)); continue }
            for (i, word) in chunk.enumerated() {
                let from = i == 0 ? begin : max(begin, word.start), to = i + 1 < chunk.count ? max(from, chunk[i + 1].start) : finish
                if to > from { result.append(TimedCaption(start: offset + from, end: offset + to, text: text, words: texts, highlight: i)) }
            }
        }
        return result
    }

    /// Splits narration into short readable chunks timed by character weight across the voice duration.
    static func captions(_ text: String, start: Double, duration: Double, maxWords: Int) -> [TimedCaption] {
        let clean = text.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        let words = clean.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, duration.isFinite, duration > 0, maxWords > 0 else { return [] }
        func ends(_ word: String, _ marks: String) -> Bool { word.last.map { marks.contains($0) } ?? false }
        var chunks: [[String]] = [], current: [String] = []
        for word in words {
            current.append(word)
            if current.count >= maxWords || ends(word, ".,;:!?…") && current.count >= max(2, maxWords / 2) || ends(word, ".!?…") { chunks.append(current); current = [] }
        }
        if !current.isEmpty { if current.count == 1, let last = chunks.indices.last, chunks[last].count < maxWords + 2 { chunks[last] += current } else { chunks.append(current) } }
        let weights = chunks.map { chunk -> Double in
            let last = chunk.last ?? ""
            return Double(chunk.joined(separator: " ").count) + (ends(last, ".!?…") ? 6 : ends(last, ",;:") ? 3 : 0)
        }
        let total = weights.reduce(0, +)
        var cursor = start, result: [TimedCaption] = []
        for (chunk, weight) in zip(chunks, weights) {
            let length = duration * weight / total
            result.append(TimedCaption(start: cursor, end: cursor + length, text: chunk.joined(separator: " ")))
            cursor += length
        }
        return result
    }
}

final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let orientation: CGImagePropertyOrientation
    let style: FrameStyle
    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, style: FrameStyle) {
        self.timeRange = timeRange; self.trackID = trackID; self.style = style
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): orientation = .right
        case (0, -1, 1, 0): orientation = .left
        case (-1, 0, 0, -1): orientation = .down
        default: orientation = .up
        }
    }
}

final class StudioCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: Any]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    private let queue = DispatchQueue(label: "su-studio.compositor")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var captionCache: [String: CIImage] = [:]
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? FrameInstruction, let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "StudioTimeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không dựng được khung hình."])); return
            }
            let frame = self.render(instruction, source: request.sourceFrame(byTrackID: instruction.trackID), at: request.compositionTime.seconds)
            self.context.render(frame, to: output, bounds: CGRect(origin: .zero, size: instruction.style.size), colorSpace: CGColorSpaceCreateDeviceRGB())
            request.finish(withComposedVideoFrame: output)
        } }
    }
    func render(_ instruction: FrameInstruction, source: CVPixelBuffer?, at seconds: Double) -> CIImage {
        let style = instruction.style, size = style.size, canvasRect = CGRect(origin: .zero, size: size)
        var canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvasRect)
        if let source = source {
            var image = CIImage(cvPixelBuffer: source).oriented(instruction.orientation)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let width = image.extent.width, height = image.extent.height
            if width > 0, height > 0 {
                func placed(_ img: CIImage, _ scale: CGFloat) -> CIImage {
                    img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                        .transformed(by: CGAffineTransform(translationX: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2))
                }
                let fit = min(size.width / width, size.height / height), cover = max(size.width / width, size.height / height)
                if style.fill == "crop" { canvas = placed(image, cover).cropped(to: canvasRect).composited(over: canvas) }
                else {
                    if style.fill == "blur", abs(width / height - size.width / size.height) > 0.02 {
                        // Blur a quarter-size copy and scale it back up: same look, a fraction of the cost.
                        let small = placed(image, cover / 4).transformed(by: CGAffineTransform(translationX: -(size.width - size.width / 4) / 2, y: -(size.height - size.height / 4) / 2))
                        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 10)
                            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.12, kCIInputSaturationKey: 1.1])
                            .transformed(by: CGAffineTransform(scaleX: 4, y: 4)).cropped(to: canvasRect)
                        canvas = blurred.composited(over: canvas)
                    }
                    canvas = placed(image, fit).composited(over: canvas)
                }
            }
        }
        if let caption = style.caption(at: seconds), let text = captionImage(caption, style: style) {
            let centerY = size.height * (style.vertical ? 0.30 : 0.11)
            canvas = text.transformed(by: CGAffineTransform(translationX: (size.width - text.extent.width) / 2, y: max(0, centerY - text.extent.height / 2))).composited(over: canvas)
        }
        return canvas.cropped(to: canvasRect)
    }
    private func captionImage(_ caption: TimedCaption, style: FrameStyle) -> CIImage? {
        let text = caption.text, key = text + "#" + (caption.highlight.map(String.init) ?? "-")
        if let cached = captionCache[key] { return cached }
        let size = style.size, fontSize: CGFloat = style.vertical ? 68 : 52, maxWidth = size.width * (style.vertical ? 0.84 : 0.78), pad: CGFloat = 28
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.65); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -3)
        let base: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let fill = NSMutableAttributedString(string: text, attributes: base.merging([.foregroundColor: NSColor.white]) { $1 })
        if let range = Self.wordRange(caption) { fill.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 1, green: 0.84, blue: 0.1, alpha: 1), range: range) }
        let stroke = NSAttributedString(string: text, attributes: base.merging([.foregroundColor: NSColor.black, .strokeColor: NSColor.black, .strokeWidth: 16, .shadow: shadow]) { $1 })
        let bounds = fill.boundingRect(with: NSSize(width: maxWidth, height: size.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let width = Int(ceil(maxWidth + pad * 2)), height = Int(ceil(bounds.height + pad * 2))
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        let rect = NSRect(x: pad, y: pad, width: maxWidth, height: ceil(bounds.height))
        stroke.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        fill.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let made = cg.makeImage() else { return nil }
        let image = CIImage(cgImage: made)
        if captionCache.count > 400 { captionCache.removeAll() }
        captionCache[key] = image
        return image
    }
    /// Range of the highlighted word inside the caption text (words joined by single spaces).
    static func wordRange(_ caption: TimedCaption) -> NSRange? {
        guard let index = caption.highlight, caption.words.indices.contains(index) else { return nil }
        let before = caption.words[..<index].map { ($0 as NSString).length + 1 }.reduce(0, +)
        let range = NSRange(location: before, length: (caption.words[index] as NSString).length)
        return NSMaxRange(range) <= (caption.text as NSString).length ? range : nil
    }
}
