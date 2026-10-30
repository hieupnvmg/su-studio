import Foundation
import JavaScriptCore
let c=JSContext()!
c.exceptionHandler={_,e in fatalError(e!.toString())}
c.evaluateScript("var window={};var document={addEventListener:function(){}};function setInterval(){};var crypto={randomUUID:function(){return 'test-id'}};")
for file in ["source/assistant.js", "source/script-import.js", "source/ui.js", "source/updater.js", "source/tts.js", "source/assistant-progress.js", "source/reference-images.js", "source/tts-batch.js", "source/model-picker.js", "source/native-editor.js", "source/narration-player.js"] { c.setObject(try String(contentsOfFile:file,encoding:.utf8),forKeyedSubscript:"source" as NSString);c.evaluateScript("new Function(source)") }
for name in ["ui.js","assistant.js","script-import.js","reference-images.js","narration-player.js","tts-batch.js","tts.js","assistant-progress.js","model-picker.js","updater.js"] { c.evaluateScript(try String(contentsOfFile:"source/"+name,encoding:.utf8)) }
let html=try String(contentsOfFile:"source/index.html",encoding:.utf8)
let inline=String(html.components(separatedBy:"<script>")[1].components(separatedBy:"</script>")[0].components(separatedBy:"render();if(native)")[0])
c.evaluateScript(inline)
c.evaluateScript("""
const fixture={id:'p',title:'Test <script>',scenes:[{id:'s',time:'00:00–00:20',chapter:'Chương 1',voice:'Lời kể',image:'Prompt',video:'Prompt video',approvals:{script:true,audio:true},assets:{audio:[{selected:true,path:'/test.mp3',text:'Lời kể'}]}}],references:[],guide:{sourceMode:'script',sourceScript:'Lời kể',brief:{duration:10,audience:'Test'},steps:{storyboard:{approved:true,draft:{scenes:[],document:'',sources:[]}}}}};
state.projects=[fixture];selected='p';page='assistant';aiViewedStage='tts';
if(!studioDashboard().includes('Test &lt;script&gt;'))throw Error('dashboard escaping');
if(!projectOverview().includes('Quy trình của dự án'))throw Error('overview');
fixture.scenes[0].ttsDirection='[angry]';
if(sceneHasCurrentAudio(fixture.scenes[0]))throw Error('old emotion must be stale');
if(bulkAudioCandidates(fixture).length)throw Error('stale emotion bulk approval');
if(narrationClips(fixture).length)throw Error('stale emotion player');
fixture.scenes[0].assets.audio[0].direction='[angry]';
if(!sceneHasCurrentAudio(fixture.scenes[0]))throw Error('matching emotion');
if(!ttsSupportsDirection('eleven_v3')||ttsSupportsDirection('eleven_multilingual_v2'))throw Error('emotion model gate');
if(!ttsAssistantView().includes('Cảm xúc & cách đọc'))throw Error('emotion UI');
if(!ttsAssistantView().includes('media-scene'))throw Error('audio view');
if(!referenceAssistantView().includes('Chuẩn bị ảnh'))throw Error('image view');
if(!workflowNavigation(fixture,'tts').includes('aria-current="step"'))throw Error('navigation');
if(!settingsView().includes('Cài đặt'))throw Error('settings');
if(aiStagesFor(fixture).length!==4)throw Error('source workflow');
if(aiReady(fixture,'production'))throw Error('image gate');
const old={id:'keep',chapter:'A',voice:'V',image:'I',video:'C',approvals:{script:true,audio:true,image:true,video:true},assets:{image:[{id:'img',selected:true,path:'/saved.png'}]}};
const kept=retainStoryboardAssets([old],[{chapter:'A',voice:'V',image:'I',video:'C'}])[0];
if(kept.id!=='keep'||kept.assets.image[0].path!=='/saved.png'||!kept.approvals.image)throw Error('retain images');
const changed=retainStoryboardAssets([old],[{chapter:'A',voice:'V',image:'new prompt',video:'C'}])[0];
if(!changed.assets.image.length||changed.approvals.image)throw Error('prompt edit retains file with review');
const different=retainStoryboardAssets([old],[{chapter:'B',voice:'new',image:'I',video:'C'}])[0];
if(different.assets.image)throw Error('do not assign images to unrelated scenes');
fixture.scenes[0].assets.image=[{id:'img',selected:true,path:'/saved.png'}];
if(pendingReferences(fixture).length!==1)throw Error('bulk images');
const reopened=JSON.parse(JSON.stringify(fixture));
if(reopened.scenes[0].assets.image[0].path!=='/saved.png')throw Error('image persistence');
if(!referenceAssistantView().includes('Duyệt tất cả ảnh (1)'))throw Error('visible bulk approval');
if(referenceAssistantView().indexOf('Duyệt tất cả ảnh (1)')<referenceAssistantView().indexOf('reference-scene-s'))throw Error('image approval below scenes');
if(ttsAssistantView().indexOf('Duyệt tất cả (')<ttsAssistantView().indexOf('tts-scene-s'))throw Error('audio approval below scenes');
if(!referenceAssistantView().includes('Tạo ảnh bằng PlenX'))throw Error('PlenX controls');
let saves=0;save=function(){saves++};render=function(){};toast=function(){};
fixture.scenes[0].plenxImageJob={status:'queued',prompt:fixture.scenes[0].image,model:'test-model',taskId:'task-1'};
plenxImagePending={requestId:'image-1',kind:'status',projectId:'p',sceneId:'s',sourcePrompt:fixture.scenes[0].image};
window.nativePlenxImage({requestId:'image-1',status:'completed',taskId:'task-1',path:'/generated.png',name:'generated.png'});
if(fixture.scenes[0].assets.image.filter(a=>a.selected).length!==1||fixture.scenes[0].assets.image.at(-1).path!=='/generated.png'||fixture.scenes[0].approvals.image||!saves)throw Error('generated image saved and awaits review');
const versions=fixture.scenes[0].assets.image.length;
window.nativePlenxImage({requestId:'image-1',status:'completed',path:'/duplicate.png'});
if(fixture.scenes[0].assets.image.length!==versions)throw Error('duplicate completion');
fixture.scenes[0].plenxImageJob={status:'queued',prompt:'old prompt',model:'test-model',taskId:'task-2'};
plenxImagePending={requestId:'image-2',kind:'status',projectId:'p',sceneId:'s',sourcePrompt:'old prompt'};
window.nativePlenxImage({requestId:'image-2',status:'completed',taskId:'task-2',path:'/old.png',name:'old.png'});
if(fixture.scenes[0].assets.image.at(-1).selected)throw Error('stale prompt result not selected');
""")
print("UI scripts parse; dashboard, overview, TTS, references, settings, escaping and workflow gate passed")
