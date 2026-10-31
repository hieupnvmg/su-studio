import Cocoa
import Foundation
final class FixtureProtocol: URLProtocol {
    static var calls:[(String,[String:Any])]=[]
    static var failGeneration=false
    override class func canInit(with request: URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        assert(request.url?.host=="api.plenxai.com");assert(request.value(forHTTPHeaderField:"X-API-Key")=="pk_fixture")
        var data=request.httpBody
        if data==nil,let stream=request.httpBodyStream { stream.open();var bytes=Data();var buf=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable {let n=stream.read(&buf,maxLength:buf.count);if n<=0 {break};bytes.append(buf,count:n)};stream.close();data=bytes }
        let payload=data.flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any] ?? [:]
        let path=request.url!.path;Self.calls.append((path,payload));let response:[String:Any];var code=200
        if path.hasSuffix("/media-upload/direct") { assert((payload["image_data"] as? String)?.hasPrefix("data:image/png;base64,")==true);response=["success":true,"url":"https://media.plenxai.com/reference.png"] }
        else if path.hasSuffix("/generate/video") || path.hasSuffix("/generate/video-omni") {
            if path.hasSuffix("video-omni") {assert(payload["input_image_url"] as? String == "https://media.plenxai.com/reference.png");assert(payload["resolution"] as? String == "720p");assert(payload["start_image_url"]==nil);assert(payload["quality"]==nil)}
            else { assert(payload["start_image_url"] as? String == "https://media.plenxai.com/reference.png");assert(payload["mode"] as? String == "i2v");assert(payload["quality"] as? String == "720p") };assert(payload["aspect_ratio"] as? String == "16:9");assert(payload["duration"] as? Int == 6);code=Self.failGeneration ? 400:200;response=Self.failGeneration ? ["success":false]:["success":true,"task_id":"task-1","status":"queued"] }
        else { assert(path.hasSuffix("/status/task-1"));response=["success":true,"task_id":"task-1","status":"processing"] }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:response));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let root=URL(fileURLWithPath:CommandLine.arguments[1]);let folder=root.appendingPathComponent("assets");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:4,pixelsHigh:4,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let image=folder.appendingPathComponent("reference.png");try bitmap.representation(using:.png,properties:[:])!.write(to:image)
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[FixtureProtocol.self]
let service=PlenXVideo(root:root,configuration:config)
var result:[String:Any]?
service.onUpdate={result=$0}
func run(_ body:[String:Any]) { result=nil;service.request(body,key:"pk_fixture");let deadline=Date().addingTimeInterval(10);while result==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))};assert(result != nil) }
let generate:[String:Any]=["requestId":"gen","kind":"generate","prompt":"Camera pans slowly","model":"veo-3.1-fast","duration":6,"quality":"720p","imagePath":image.path]
run(generate);assert(result?["status"] as? String == "queued");assert(result?["taskId"] as? String == "task-1");assert(FixtureProtocol.calls.count==2)
run(["requestId":"poll","kind":"status","taskId":"task-1"]);assert(result?["status"] as? String == "queued");assert(FixtureProtocol.calls.count==3)
FixtureProtocol.failGeneration=true;run(generate);assert(result?["status"] as? String == "error");assert(FixtureProtocol.calls.count==5)
run(["requestId":"invalid","kind":"status","taskId":"../other"]);assert(result?["status"] as? String == "error");assert(FixtureProtocol.calls.count==5)
FixtureProtocol.failGeneration=false
var omni=generate;omni["endpoint"]="/developer/generate/video-omni";omni["model"]="kling-4.0"
run(omni);assert(result?["status"] as? String == "queued");assert(FixtureProtocol.calls.last?.0.hasSuffix("/generate/video-omni")==true);assert(FixtureProtocol.calls.count==7)
print("PlenX video fixtures passed: reference upload, I2V payload, task polling, invalid task guard and no paid retry")
