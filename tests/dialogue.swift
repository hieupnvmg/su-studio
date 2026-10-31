import Foundation
final class MockDialogue: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        precondition(request.url!.path == "/v1/text-to-dialogue")
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
        client!.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"audio/mpeg"])!,cacheStoragePolicy:.notAllowed)
        client!.urlProtocol(self,didLoad:Data("fixture-audio".utf8));client!.urlProtocolDidFinishLoading(self)
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
print("Dialogue passed: ordered voices/tags, endpoint, audio save, model/length/voice guards; no paid requests")
