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
if(!ttsAssistantView().includes('media-scene'))throw Error('audio view');
if(!referenceAssistantView().includes('Chuẩn bị ảnh'))throw Error('image view');
if(!workflowNavigation(fixture,'tts').includes('aria-current="step"'))throw Error('navigation');
if(!settingsView().includes('Cài đặt'))throw Error('settings');
if(aiStagesFor(fixture).length!==4)throw Error('source workflow');
if(aiReady(fixture,'production'))throw Error('image gate');
""")
print("UI scripts parse; dashboard, overview, TTS, references, settings, escaping and workflow gate passed")
