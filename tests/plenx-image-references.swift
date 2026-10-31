import Cocoa
import Foundation
final class ImageFixture: URLProtocol {
 static var uploads=0,generations=0,failUpload=false
 override class func canInit(with request:URLRequest)->Bool {true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading(){
  assert(request.url?.host=="api.plenxai.com");assert(request.value(forHTTPHeaderField:"X-API-Key")=="pk_fixture")
  var data=request.httpBody
  if data==nil,let stream=request.httpBodyStream {stream.open();var bytes=Data();var buf=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable{let n=stream.read(&buf,maxLength:buf.count);if n<=0{break};bytes.append(buf,count:n)};stream.close();data=bytes}
  let body=data.flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any] ?? [:]
  var code=200;let result:[String:Any]
  if request.url!.path.hasSuffix("/media-upload/direct") {Self.uploads+=1;assert((body["image_data"] as? String)?.hasPrefix("data:image/png;base64,")==true);code=Self.failUpload ? 400:200;result=Self.failUpload ? ["success":false]:["success":true,"url":"https://media.plenxai.com/ref-\(Self.uploads).png"]}
  else {assert(request.url!.path.hasSuffix("/generate/image"));Self.generations+=1;assert(body["references_urls"] as? [String]==["https://media.plenxai.com/ref-1.png","https://media.plenxai.com/ref-2.png"]);assert(body["model"] as? String=="nano-banana-pro");result=["success":true,"task_id":"image-task","status":"queued"]}
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:result));client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading(){}
}
let root=URL(fileURLWithPath:CommandLine.arguments[1]),folder=root.appendingPathComponent("assets");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:4,pixelsHigh:4,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
for name in ["one.png","two.png","three.png"] {try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))}
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ImageFixture.self]
let service=PlenXImages(root:root,configuration:config);var result:[String:Any]?
service.onUpdate={result=$0}
func run(_ paths:[String]) {result=nil;service.requestWithReferences(["requestId":"refs","kind":"generate","model":"nano-banana-pro","prompt":"Keep the same characters","referencePaths":paths],key:"pk_fixture");let deadline=Date().addingTimeInterval(10);while result==nil&&Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};assert(result != nil)}
let paths=["one.png","two.png"].map{folder.appendingPathComponent($0).path}
run(paths);assert(result?["status"] as? String=="queued");assert(ImageFixture.uploads==2&&ImageFixture.generations==1)
run(paths);assert(result?["status"] as? String=="queued");assert(ImageFixture.uploads==2&&ImageFixture.generations==2)
run(["/etc/passwd"]);assert(result?["status"] as? String=="error");assert(ImageFixture.uploads==2&&ImageFixture.generations==2)
ImageFixture.failUpload=true;run([folder.appendingPathComponent("three.png").path]);assert(result?["status"] as? String=="error");assert(ImageFixture.generations==2)
print("Image reference fixtures passed: real local image uploads, ordered references_urls, cache reuse, path guard, no generation on failed reference upload")
