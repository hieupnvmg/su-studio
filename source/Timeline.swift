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
    func api(_ path:String, key:String, payload:[String:Any]? = nil, completion:@escaping ([String:Any]?,Int)->Void) {
        var r = URLRequest(url:URL(string:"https://api.plenxai.com/api/v1/developer"+path)!)
        r.setValue(key,forHTTPHeaderField:"X-API-Key")
        if let payload = payload { r.httpMethod = "POST"; r.setValue("application/json",forHTTPHeaderField:"Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject:payload) }
        session.dataTask(with:r) { data,response,error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, (200..<300).contains(code), let data = data, let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],json["success"] as? Bool != false else { completion(nil,code); return }; completion(json,code)
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
                guard let json = json else { reply(["status":"error","taskId":task,"message":"Chưa đọc được tác vụ (HTTP \(code)). Kiểm tra lại, không tạo lại tự động."]); return }
                let state = json["status"] as? String ?? "queued"
                if ["error","failed"].contains(state) { reply(["status":"failed","taskId":task,"message":"PlenX báo tạo video thất bại. Kiểm tra lịch sử trước khi tạo lại."]); return }
                guard ["completed","succeeded"].contains(state) else { reply(["status":"queued","taskId":task,"message":"PlenX đang tạo video…"]); return }
                guard let raw = json["result_url"] as? String,let url = URL(string:raw),url.scheme == "https",url.user == nil,url.password == nil else { reply(["status":"error","taskId":task,"message":"Chưa có URL video hợp lệ."]); return }
                self.session.downloadTask(with:url) { file,response,error in
                    guard error == nil,let file = file,let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 1_000_000_000 else { reply(["status":"error","taskId":task,"message":"Video đã tạo nhưng tải chưa thành công. Kiểm tra lại tác vụ để tải, không cần tạo mới."]); return }
                    do {
                        let saved = try Self.storeDownloadedVideo(file, in:self.root)
                        reply(["status":"completed","taskId":task,"path":saved.url.path,"name":saved.url.lastPathComponent,"duration":saved.duration])
                    } catch { reply(["status":"error","taskId":task,"message":error.localizedDescription]) }
                }.resume()
            };return
        }
        guard kind == "generate",let prompt = body["prompt"] as? String,!prompt.isEmpty,prompt.count<=20000,
              let model = body["model"] as? String,model.range(of:"^[A-Za-z0-9._-]+$",options:.regularExpression) != nil,
              let raw = body["imagePath"] as? String else { reply(["status":"error","message":"Thiếu prompt, model hoặc ảnh tham chiếu."]);return }
        let file = URL(fileURLWithPath:raw).standardizedFileURL.resolvingSymlinksInPath()
        guard file.deletingLastPathComponent()==root, let source = CGImageSourceCreateWithURL(file as CFURL,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { reply(["status":"error","message":"Không đọc được ảnh tham chiếu trong dự án."]);return }
        let png = NSMutableData();guard let out = CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil) else { reply(["status":"error","message":"Chưa chuẩn bị được ảnh."]);return };CGImageDestinationAddImage(out,image,nil);guard CGImageDestinationFinalize(out) else { reply(["status":"error","message":"Không chuyển được ảnh."]);return }
        api("/media-upload/direct",key:key,payload:["image_data":"data:image/png;base64,"+(png as Data).base64EncodedString(),"filename":"reference.png","media_type":"image","aspect_ratio":"16:9"]) { uploaded,code in
            guard let uploaded = uploaded,let imageURL = (uploaded["url"] ?? uploaded["public_url"]) as? String else { reply(["status":"error","message":"Chưa tải được ảnh tham chiếu lên PlenX (HTTP \(code)). Chưa xác nhận tạo video."]);return }
            let duration = body["duration"] as? Int ?? 5,quality = body["quality"] as? String ?? "720p"
            self.api("/generate/video",key:key,payload:["model":model,"prompt":prompt,"mode":"i2v","start_image_url":imageURL,"duration":duration,"quality":quality,"aspect_ratio":"16:9"]) { json,code in
                guard let task = json?["task_id"] as? String,!task.isEmpty else { reply(["status":"error","message":"Chưa xác nhận được yêu cầu tạo video (HTTP \(code)). Kiểm tra lịch sử PlenX trước khi tạo lại; có thể đã dùng credit."]);return };reply(["status":"queued","taskId":task,"message":"PlenX đã nhận yêu cầu tạo video…"])
            }
        }
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
        guard url.deletingLastPathComponent()==root,FileManager.default.fileExists(atPath:url.path) else { throw issue("Không tìm thấy file trong tài nguyên dự án. Nhập lại file bị thiếu.") }
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
                if duration.isFinite && duration>0 { values.append(["id":entry["id"] as? String ?? "","duration":duration,"videoDuration":videoDuration.isFinite ? videoDuration:0]) }
            }
            onUpdate?(["status":"measured","values":values]);return
        }
        var output: URL?
        if kind == "export" {
            let panel = NSSavePanel();panel.nameFieldStringValue = "Su-Studio.mp4";panel.allowedFileTypes=["mp4"]
            guard panel.runModal() == .OK,let url = panel.url else { onUpdate?(["status":"cancelled","message":"Đã hủy chọn nơi lưu."]);return };output = url
        }
        preparing = true
        onUpdate?(["status":"preparing","message":"Đang dựng timeline…"])
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let (composition,video,mix,duration) = try self.compose(entries)
                DispatchQueue.main.async {
                    self.preparing = false
                    if let output = output {
                        guard let exporter = AVAssetExportSession(asset:composition,presetName:AVAssetExportPreset1920x1080) else { self.onUpdate?(["status":"error","message":"Máy này chưa tạo được bộ xuất MP4."]);return }
                        exporter.outputURL=output;exporter.outputFileType = .mp4;exporter.videoComposition=video;exporter.audioMix=mix;exporter.shouldOptimizeForNetworkUse=true
                        self.exporter=exporter
                        self.timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in self?.onUpdate?(["status":"exporting","progress":Double(exporter.progress),"message":"Đang xuất MP4… \(Int(exporter.progress*100))%"] ) }
                        exporter.exportAsynchronously {
                            DispatchQueue.main.async {
                                self.timer?.invalidate();self.timer=nil;self.exporter=nil
                                if exporter.status == .completed { self.onUpdate?(["status":"completed","path":output.path,"message":"Đã xuất MP4: \(output.lastPathComponent)"]);NSWorkspace.shared.activateFileViewerSelecting([output]) }
                                else { self.onUpdate?(["status":exporter.status == .cancelled ? "cancelled":"error","message":exporter.status == .cancelled ? "Đã hủy xuất.":"Xuất MP4 thất bại. Kiểm tra dung lượng và định dạng clip. \(exporter.error?.localizedDescription ?? "")"]) }
                            }
                        }
                    } else {
                        self.player?.pause();self.preview?.close()
                        let item=AVPlayerItem(asset:composition);item.videoComposition=video;item.audioMix=mix
                        let player=AVPlayer(playerItem:item);self.player=player
                        let view=AVPlayerView(frame:NSRect(x:0,y:0,width:1000,height:600));view.player=player;view.controlsStyle = .floating
                        let window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
                        window.delegate=self;window.title="Xem thử timeline · \(Int(duration)) giây";window.contentView=view;window.isReleasedWhenClosed=false;window.center();window.makeKeyAndOrderFront(nil);self.preview=window;player.play()
                        self.onUpdate?(["status":"preview","message":"Đã mở trình xem timeline với video và lời kể."])
                    }
                }
            } catch { DispatchQueue.main.async { self.preparing = false; self.onUpdate?(["status":"error","message":error.localizedDescription]) } }
        }
    }
    func compose(_ entries:[[String:Any]]) throws -> (AVMutableComposition,AVMutableVideoComposition,AVMutableAudioMix,Double) {
        let composition=AVMutableComposition(),video=AVMutableVideoComposition(),mix=AVMutableAudioMix()
        var instructions:[AVVideoCompositionInstructionProtocol]=[],audioParameters:[AVAudioMixInputParameters]=[]
        var cursor=CMTime.zero
        func seconds(_ n:Double)->CMTime { CMTime(seconds:n,preferredTimescale:600) }
        for (index,e) in entries.enumerated() {
            let source=try asset(e["path"] as? String)
            guard let src=source.tracks(withMediaType:.video).first,source.duration.seconds.isFinite else { throw issue("Clip \(index+1) không có video hợp lệ.") }
            let start=e["trimStart"] as? Double ?? 0,end=e["trimEnd"] as? Double ?? source.duration.seconds
            let target=e["duration"] as? Double ?? end-start
            guard start.isFinite,end.isFinite,target.isFinite,start>=0,end>start,end<=source.duration.seconds+0.05,target>=0.1,target<=3600 else { throw issue("Clip \(index+1): điểm cắt hoặc thời lượng chưa hợp lệ (file dài \(String(format:"%.2f",source.duration.seconds)) giây).") }
            let range=CMTimeRange(start:seconds(start),duration:seconds(min(end,source.duration.seconds)-start)),slot=seconds(target)
            guard let track=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw issue("Không thêm được track video.") }
            try track.insertTimeRange(range,of:src,at:cursor);track.scaleTimeRange(CMTimeRange(start:cursor,duration:range.duration),toDuration:slot)
            let transformed=src.naturalSize.applying(src.preferredTransform),size=CGSize(width:abs(transformed.width),height:abs(transformed.height))
            guard size.width>0,size.height>0 else { throw issue("Kích thước clip không hợp lệ.") }
            let scale=min(1920/size.width,1080/size.height),rect=CGRect(origin:.zero,size:src.naturalSize).applying(src.preferredTransform)
            var transform=src.preferredTransform.concatenating(CGAffineTransform(translationX:-rect.origin.x,y:-rect.origin.y))
            transform=transform.concatenating(CGAffineTransform(scaleX:scale,y:scale)).concatenating(CGAffineTransform(translationX:(1920-size.width*scale)/2,y:(1080-size.height*scale)/2))
            let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:track);layer.setTransform(transform,at:cursor)
            let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=CMTimeRange(start:cursor,duration:slot);instruction.layerInstructions=[layer];instruction.backgroundColor=NSColor.black.cgColor;instructions.append(instruction)
            if e["includeOriginalAudio"] as? Bool == true,let sound=source.tracks(withMediaType:.audio).first,let audio=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(range,of:sound,at:cursor);audio.scaleTimeRange(CMTimeRange(start:cursor,duration:range.duration),toDuration:slot)
                let params=AVMutableAudioMixInputParameters(track:audio);params.setVolume(0.35,at:cursor);audioParameters.append(params)
            }
            if let path=e["audioPath"] as? String,!path.isEmpty {
                let voice=try asset(path)
                guard let sound=voice.tracks(withMediaType:.audio).first,voice.duration.seconds.isFinite,voice.duration.seconds>0 else { throw issue("Lời kể clip \(index+1) không đọc được.") }
                guard voice.duration.seconds<=target+0.1 else { throw issue("Clip \(index+1) ngắn hơn lời kể. Bấm Căn theo giọng đọc hoặc tăng thời lượng timeline để giữ đủ lời.") }
                if let audio=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                    try audio.insertTimeRange(CMTimeRange(start:.zero,duration:voice.duration),of:sound,at:cursor)
                    let params=AVMutableAudioMixInputParameters(track:audio);params.setVolume(1,at:cursor);audioParameters.append(params)
                }
            }
            cursor=CMTimeAdd(cursor,slot)
        }
        video.renderSize=CGSize(width:1920,height:1080);video.frameDuration=CMTime(value:1,timescale:30);video.instructions=instructions;mix.inputParameters=audioParameters
        return(composition,video,mix,cursor.seconds)
    }
}
