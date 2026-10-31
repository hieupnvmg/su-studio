import Foundation
import JavaScriptCore
let c=JSContext()!
c.exceptionHandler={_,e in fatalError(e!.toString())}
c.evaluateScript("var window={};var document={addEventListener:function(){}};function setInterval(){};var crypto={randomUUID:function(){return 'test-id'}};")
for file in ["source/assistant.js", "source/script-import.js", "source/ui.js", "source/updater.js", "source/tts.js", "source/assistant-progress.js", "source/reference-images.js", "source/tts-batch.js", "source/model-picker.js", "source/native-editor.js", "source/narration-player.js", "source/media-studio.js", "source/auto-tags.js", "source/visual-bible.js"] { c.setObject(try String(contentsOfFile:file,encoding:.utf8),forKeyedSubscript:"source" as NSString);c.evaluateScript("new Function(source)") }
for name in ["ui.js","assistant.js","script-import.js","reference-images.js","narration-player.js","tts-batch.js","tts.js","assistant-progress.js","model-picker.js","updater.js","media-studio.js","auto-tags.js","visual-bible.js"] { c.evaluateScript(try String(contentsOfFile:"source/"+name,encoding:.utf8)) }
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
if(aiStagesFor(fixture).length!==5)throw Error('source workflow');
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
confirm=function(){return true};let sent=[];send=function(action,body){sent.push({action,body})};
const batchFixture={id:'batch',title:'Batch',plenxImageModel:'img-model',scenes:[{id:'a',voice:'one',image:'prompt one',video:'move one',chapter:'One',time:'00:00–00:02',approvals:{script:true},assets:{}},{id:'b',voice:'two',image:'prompt two',video:'move two',chapter:'Two',time:'00:02–00:04',approvals:{script:true},assets:{}},{id:'c',voice:'three',image:'existing',video:'move three',chapter:'Three',time:'00:04–00:06',approvals:{script:true,image:true},assets:{image:[{id:'existing',selected:true,path:'/existing.png'}]}}]};
state.projects=[batchFixture];selected='batch';batchFixture.visualBible={style:'Test style',characters:[],approved:true,noCharacters:true};batchFixture.scenes[2].assets.image[0].reviewedDesignSignature=designSignature(batchFixture,batchFixture.scenes[2]);plenxImageModels=[{id:'img-model',name:'Image',resolutions:['1k']}];
startImageBatch();if(sent.length!==1||sent[0].body.sceneId!=='a'||batchFixture.imageBatch.total!==2)throw Error('sequential missing-image queue');
window.nativePlenxImage({requestId:'wrong',status:'completed',path:'/wrong.png'});
if(batchFixture.imageBatch.completed!==0)throw Error('stale callback queue');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/a.png',name:'a.png'});
if(batchFixture.imageBatch.completed!==1||sent.length!==2||sent[1].body.sceneId!=='b')throw Error('next image');
stopImageBatch();window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/b.png',name:'b.png'});
if(batchFixture.imageBatch.status!=='paused'||sent.length!==2||!batchFixture.scenes[2].assets.image[0].selected)throw Error('stop retains results and existing image');
batchFixture.scenes.forEach(s=>s.approvals.image=true);
plenxVideoModels=[{id:'vid-model',name:'Video',modes:['i2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video'],durations:[2],qualities:['720p']}];
batchFixture.videoSettings={model:'vid-model',duration:2,quality:'720p'};sent=[];
startVideoBatch();if(sent.length!==1||sent[0].action!=='plenxVideo'||sent[0].body.imagePath!=='/a.png')throw Error('video queue reference image');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'error',message:'fixture failure'});
if(batchFixture.videoBatch.status!=='paused'||sent.length!==1)throw Error('paid video not retried');
batchFixture.scenes[0].assets.video=[{id:'clip',selected:true,path:'/clip.mp4',duration:2}];
let edits=timelineEntries(batchFixture);edits[0].trimStart=.2;edits[0].trimEnd=1.8;
if(resolvedTimeline(batchFixture)[0].path!=='/clip.mp4')throw Error('timeline resolves scene clip');
moveTimeline(edits[0].id,1);if(timelineEntries(batchFixture)[1].sceneId!=='a')throw Error('timeline reorder');
const saved=JSON.parse(JSON.stringify(batchFixture));
if(saved.timelineEntries[1].trimStart!==.2||saved.timelineEntries[1].trimEnd!==1.8)throw Error('timeline edit persistence');
if(!productionView().includes('Xuất MP4'))throw Error('production editor');
plenxVideoModels.push({id:'kling-4.0',name:'Kling 4.0',modes:['i2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video-omni'],qualities:['1080p'],durations:[5]});
if(!videoCatalog().some(m=>m.id==='kling-4.0')||videoEndpoint(plenxVideoModels[1])!=='/developer/generate/video-omni')throw Error('Omni model catalog');
plenxVideoModels[0].qualities=['720p','1080p','4K'];
if(!productionView().includes('1080p')||!productionView().includes('4K'))throw Error('source quality options');
if(!productionView().includes('▶ Xem clip'))throw Error('source clip preview button');
sent=[];previewSourceClip('a','clip');if(sent[0]?.body.command!=='previewSource'||sent[0]?.body.path!=='/clip.mp4')throw Error('source preview payload');
batchFixture.imageBatch={status:'running',completed:1,total:2,message:'Đang tạo cảnh 2'};
if(!productionView().includes('Dừng tạo ảnh sau ảnh hiện tại')||!productionView().includes('Đang tạo ảnh · 1/2'))throw Error('visible image queue on video page');
if(!productionView().includes('disabled onclick=\"startVideoBatch()\"'))throw Error('video disabled during image queue');
""")
c.evaluateScript("""
if(audioTagIssue('Ông im lặng, nhưng không khuất phục.','[calm] Ông im lặng, [angry] nhưng không khuất phục.'))throw Error('multiple inline tags');
if(!audioTagIssue('Ông im lặng.','[calm] Ông bỏ đi.'))throw Error('reject rewritten narration');
if(!audioTagIssue('Ông im lặng.','[explosion] Ông im lặng.'))throw Error('reject unsupported tags');
const taggedScene={id:'tag-scene',voice:'Ông im lặng, nhưng không khuất phục.',approvals:{script:true,audio:true},assets:{audio:[{selected:true,path:'/old.mp3',text:'Ông im lặng, nhưng không khuất phục.'}]}};
const tagProject={id:'tag-project',title:'Test',scenes:[taggedScene],guide:{steps:{},brief:{}}};state.projects=[tagProject];selected=tagProject.id;
tagProject.audioTagJob={requestId:'tag-request',status:'running',sceneIds:[taggedScene.id],sources:[taggedScene.voice]};
window.nativeAssistant({projectId:tagProject.id,requestId:'tag-request',stage:'audio_tags',status:'completed',result:{scenes:[{chapter:taggedScene.id,voice:'[calm] Ông im lặng, [angry] nhưng không khuất phục.'}]}});
if(ttsScript(taggedScene)!==taggedScene.voice||!taggedScene.audioTagDraft)throw Error('suggestion does not auto apply');
applyAudioTags(taggedScene.id);
if(taggedScene.approvals.audio||!ttsScript(taggedScene).includes('[angry]')||ttsAssetCurrent(taggedScene,taggedScene.assets.audio[0]))throw Error('applied tags invalidate old audio');
const persisted=JSON.parse(JSON.stringify(taggedScene));if(ttsScript(persisted)!==ttsScript(taggedScene))throw Error('persist tags');
taggedScene.voice='Lời mới.';if(ttsScript(taggedScene)!=='Lời mới.')throw Error('do not use old tags after text edit');
""")
c.evaluateScript("""
const bible={style:'Muted cinematic',approved:true,noCharacters:false,characters:[{id:'hero',name:'Mai Thúc Loan',description:'Áo vải nâu, tóc buộc',approved:true,images:[{id:'portrait',path:'/hero.png',selected:true}]}]};
const sceneDesign={id:'scene-design',voice:'Lời kể',image:'Một người bên sông',characterIds:['hero'],designAssigned:true,approvals:{image:true,video:true},assets:{image:[{id:'old-image',path:'/old.png',selected:true}]}};
const visualProject={id:'visual',visualBible:bible,scenes:[sceneDesign]};
if(!isDesignApproved(visualProject)||designIssue(visualProject,sceneDesign,{max_references:4}))throw Error('valid visual bible');
if(characterReferencePaths(visualProject,sceneDesign)[0]!=='/hero.png')throw Error('actual reference path');
if(!sceneDesignPrompt(visualProject,sceneDesign).includes('Mai Thúc Loan'))throw Error('identity prompt');
if(!designIssue(visualProject,sceneDesign,{max_references:0}))throw Error('unsupported reference model blocked');
if(currentSceneImage(visualProject,sceneDesign))throw Error('legacy image needs visual review');
sceneDesign.assets.image[0].designSignature=designSignature(visualProject,sceneDesign);
if(!currentSceneImage(visualProject,sceneDesign))throw Error('matching visual image');
bible.characters[0].images[0].id='new-portrait';
if(currentSceneImage(visualProject,sceneDesign))throw Error('changed identity invalidates match');
const persistedDesign=JSON.parse(JSON.stringify(visualProject));
if(characterReferencePaths(persistedDesign,persistedDesign.scenes[0])[0]!=='/hero.png')throw Error('portrait persistence');
sceneDesign.characterIds=[];
if(characterReferencePaths(visualProject,sceneDesign).length)throw Error('landscape has no character images');
sceneDesign.characterIds=['hero'];visualProject.plenxImageModel='identity-model';state.projects=[visualProject];selected=visualProject.id;plenxImageModels=[{id:'identity-model',name:'Identity',max_references:4,resolutions:['1k']}];sent=[];plenxImagePending=null;
generatePlenxImage(sceneDesign.id);
if(sent[0]?.body.referencePaths?.[0]!=='/hero.png'||!sent[0]?.body.prompt.includes('Mai Thúc Loan'))throw Error('identity image request includes actual reference');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/consistent.png',name:'consistent.png'});
if(!currentSceneImage(visualProject,sceneDesign))throw Error('generated image identity snapshot');
sent=[];generateCharacterImage('hero');
if(sent[0]?.body.characterId!=='hero')throw Error('character generation request');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/new-portrait.png',name:'new-portrait.png'});
if(selectedCharacterImage(bible.characters[0]).path!=='/new-portrait.png'||bible.approved||bible.characters[0].approved)throw Error('portrait awaits approval');
if(currentSceneImage({...visualProject,visualBible:{...bible,approved:true}},sceneDesign))throw Error('new portrait marks old scene image stale');
""")
print("UI scripts parse; dashboard, overview, TTS, references, settings, escaping and workflow gate passed")
