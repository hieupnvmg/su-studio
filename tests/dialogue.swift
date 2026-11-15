import Foundation
final class MockDialogue: URLProtocol {
    static var requests = 0
    static var paths: [String] = []
    static var plainOnly = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1; Self.paths.append(request.url!.path)
        if Self.plainOnly && request.url!.path.hasSuffix("/with-timestamps") {
            client!.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:404,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client!.urlProtocol(self,didLoad:Data("{\"detail\":\"Not Found\"}".utf8));client!.urlProtocolDidFinishLoading(self);return
        }
        if request.url!.path == "/v1/music" {
            var raw = request.httpBody
            if raw == nil, let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var buf = [UInt8](repeating: 0, count: 4096); var body = Data(); while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(contentsOf: buf.prefix(n)) }; raw = body }
            let music = try! JSONSerialization.jsonObject(with: raw!) as! [String: Any]
            precondition(music["force_instrumental"] as? Bool == true && music["music_length_ms"] as? Int == 45000 && music["model_id"] as? String == "music_v1" && request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
            client!.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"audio/mpeg"])!,cacheStoragePolicy:.notAllowed)
            client!.urlProtocol(self,didLoad:Data("music-audio".utf8));client!.urlProtocolDidFinishLoading(self);return
        }
        if request.url!.path.hasPrefix("/v1/text-to-speech/") {
            let timed = request.url!.path.hasSuffix("/with-timestamps")
            precondition(request.value(forHTTPHeaderField: "Accept") == (timed ? "application/json" : "audio/mpeg"))
            let body: Data
            if timed {
                // "[calm]\nXin chào [whispers] bạn." with an emotion direction line before the narration.
                let text = Array("[calm]\nXin chào [whispers] bạn.").map(String.init)
                body = try! JSONSerialization.data(withJSONObject:["audio_base64":Data("timed-audio".utf8).base64EncodedString(),"alignment":["characters":text,"character_start_times_seconds":text.indices.map{Double($0)*0.1},"character_end_times_seconds":text.indices.map{Double($0)*0.1+0.08}]])
            } else { body = Data("plain-audio".utf8) }
            client!.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":timed ? "application/json" : "audio/mpeg"])!,cacheStoragePolicy:.notAllowed)
            client!.urlProtocol(self,didLoad:body);client!.urlProtocolDidFinishLoading(self);return
        }
        precondition(request.url!.path == "/v1/text-to-dialogue/with-timestamps")
        precondition(request.url!.query == "output_format=mp3_44100_128")
        precondition(request.value(forHTTPHeaderField: "xi-api-key") == "fixture-key")
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 4096); var body = Data()
            while stream.hasBytesAvailable { let n=stream.read(&bytes,maxLength:bytes.count); if n <= 0 { break };body.append(contentsOf:bytes.prefix(n)) };data=body
        }
        let payload = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
        let inputs = payload["inputs"] as! [[String: String]]
        precondition(inputs.map { $0["voice_id"]! } == ["voice_a", "voice_b"])
        precondition(inputs[0]["text"] == "[angry] Đi thôi!")
        precondition(payload["model_id"] as? String == "eleven_v3")
        let chars = Array("[angry] Đi thôi! Khoan đã.").map(String.init)
        let body = try! JSONSerialization.data(withJSONObject:["audio_base64":Data("fixture-audio".utf8).base64EncodedString(),"alignment":["characters":chars,"character_start_times_seconds":chars.indices.map{Double($0)*0.05},"character_end_times_seconds":chars.indices.map{Double($0)*0.05+0.04}]])
        client!.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client!.urlProtocol(self,didLoad:body);client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:root) }
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockDialogue.self]
let tts=ElevenLabsTTS(root:root,configuration:config)
let inputs=[["text":"[angry] Đi thôi!","voice_id":"voice_a"],["text":"Khoan đã.","voice_id":"voice_b"]]
precondition(ElevenLabsTTS.dialoguePayload(inputs:inputs,model:"eleven_v3") != nil)
precondition(ElevenLabsTTS.dialoguePayload(inputs:inputs,model:"eleven_flash_v2_5") == nil)
precondition(ElevenLabsTTS.dialoguePayload(inputs:[["text":"x","voice_id":"../bad"]],model:"eleven_v3") == nil)
precondition(ElevenLabsTTS.dialoguePayload(inputs:[["text":String(repeating:"x",count:2001),"voice_id":"a"]],model:"eleven_v3") == nil)
precondition(ElevenLabsTTS.dialoguePayload(inputs:(0..<11).map{["text":"x","voice_id":"voice_\($0)"]},model:"eleven_v3") == nil)
var complete=false
tts.onUpdate={ r in
    if r["status"] as? String == "completed" { precondition(FileManager.default.fileExists(atPath:r["path"] as! String));complete=true }
    if r["status"] as? String == "error" { fatalError("Unexpected fixture failure") }
}
tts.request(["requestId":"fixture","kind":"generate","model":"eleven_v3","dialogueInputs":inputs],key:"fixture-key")
let deadline=Date().addingTimeInterval(10)
while !complete && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
precondition(complete && MockDialogue.requests == 1)
// Word timings: tags are skipped, each word keeps its first start and last end, saved beside the audio.
func generate(_ body:[String:Any]) -> [String:Any] {
    var out:[String:Any]?;tts.onUpdate={ r in if ["completed","error"].contains(r["status"] as? String ?? "") { out=r } }
    tts.request(body,key:"fixture-key");let until=Date().addingTimeInterval(10)
    while out==nil && Date()<until { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) };return out ?? [:]
}
var dialogueResult=generate(["requestId":"d2","kind":"generate","model":"eleven_v3","dialogueInputs":inputs])
let dialogueWords=(try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:(dialogueResult["path"] as! String)+".words.json"))) as! [String:Any])["words"] as! [[String:Any]]
precondition(dialogueWords.map{$0["text"] as! String}==["Đi","thôi!","Khoan","đã."],"\(dialogueWords)")
precondition(abs((dialogueWords[0]["start"] as! Double)-0.40)<0.001 && abs((dialogueWords[1]["end"] as! Double)-(15*0.05+0.04))<0.001)
precondition(String(data:try! Data(contentsOf:URL(fileURLWithPath:dialogueResult["path"] as! String)),encoding:.utf8)=="fixture-audio" && dialogueResult["words"] as? Int == 4)
// Single voice with an emotion direction: the direction line and tags never become caption words.
let speech:[String:Any]=["requestId":"s1","kind":"generate","model":"eleven_v3","voice":"voice_a","text":"Xin chào bạn.","taggedText":"Xin chào [whispers] bạn.","direction":"[calm]"]
let timed=generate(speech)
let timedWords=(try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:(timed["path"] as! String)+".words.json"))) as! [String:Any])["words"] as! [[String:Any]]
precondition(timedWords.map{$0["text"] as! String}==["Xin","chào","bạn."] && MockDialogue.paths.last=="/v1/text-to-speech/voice_a/with-timestamps","\(timedWords)")
// No timestamps endpoint (404): one retry for plain audio, no word file.
MockDialogue.plainOnly=true;let before=MockDialogue.requests
let plain=generate(speech)
precondition(plain["status"] as? String=="completed" && MockDialogue.requests==before+2 && MockDialogue.paths.last=="/v1/text-to-speech/voice_a")
precondition(!FileManager.default.fileExists(atPath:(plain["path"] as! String)+".words.json") && String(data:try! Data(contentsOf:URL(fileURLWithPath:plain["path"] as! String)),encoding:.utf8)=="plain-audio")
precondition(ElevenLabsTTS.words(alignment:nil).isEmpty && ElevenLabsTTS.words(alignment:["characters":["a"],"character_start_times_seconds":[0],"character_end_times_seconds":[]]).isEmpty)
// Instrumental background music.
MockDialogue.plainOnly=false
let music=generate(["requestId":"m1","kind":"music","prompt":"Trống trận và sáo trúc, hùng tráng, chậm","seconds":45])
precondition(music["status"] as? String=="completed" && (music["path"] as! String).hasSuffix("-music.mp3") && MockDialogue.paths.last=="/v1/music","\(music)")
precondition(!FileManager.default.fileExists(atPath:(music["path"] as! String)+".words.json"))
let badMusic=generate(["requestId":"m2","kind":"music","prompt":"x","seconds":5]);precondition(badMusic["status"] as? String=="error" && MockDialogue.paths.last=="/v1/music")
print("Dialogue passed: instrumental music generation, word timings from alignment (tags and direction skipped, saved beside audio), plain-audio fallback on 404, ordered voices/tags, endpoint, audio save, model/length/voice guards; no paid requests")
