import Foundation
import JavaScriptCore
let c=JSContext()!
c.exceptionHandler={_,e in fatalError(e!.toString())}
c.evaluateScript("var window={};var document={addEventListener:function(){}};function setInterval(){};var crypto={randomUUID:function(){return 'test-id'}};")
for file in ["source/assistant.js", "source/script-import.js", "source/ui.js", "source/changelog.js", "source/updater.js", "source/tts.js", "source/assistant-progress.js", "source/reference-images.js", "source/tts-batch.js", "source/model-picker.js", "source/native-editor.js", "source/backup.js", "source/blender.js", "source/narration-player.js", "source/media-studio.js", "source/auto-tags.js", "source/short-clips.js", "source/visual-bible.js", "source/dialogue.js", "source/video-references.js", "source/excel-import.js", "source/angle-images.js"] { c.setObject(try String(contentsOfFile:file,encoding:.utf8),forKeyedSubscript:"source" as NSString);c.evaluateScript("new Function(source)") }
for name in ["assistant.js","assistant-progress.js","model-picker.js","ui.js"] { c.evaluateScript(try String(contentsOfFile:"source/"+name,encoding:.utf8)) }
let html=try String(contentsOfFile:"source/index.html",encoding:.utf8)
precondition(html.range(of:"<script src=\"dialogue.js\"")!.lowerBound < html.range(of:"render();if(native)send('load')")!.lowerBound, "Load state only after workflow scripts are ready")
let buildScript=try String(contentsOfFile:"source/build.sh",encoding:.utf8)
for part in html.components(separatedBy:"<script src=\"").dropFirst() { let name=part.components(separatedBy:"\"")[0]; precondition(buildScript.contains("$STUDIO_SOURCE/"+name+"\""),"build.sh does not copy "+name) }
let inline=String(html.components(separatedBy:"<script>")[1].components(separatedBy:"</script>")[0].components(separatedBy:"render();if(native)")[0])
c.evaluateScript(inline)
for name in ["script-import.js","changelog.js","updater.js","reference-images.js","narration-player.js","tts-batch.js","tts.js","media-studio.js","auto-tags.js","short-clips.js","visual-bible.js","dialogue.js","video-references.js","excel-import.js","angle-images.js","archive-media.js","backup.js","blender.js"] { c.evaluateScript(try String(contentsOfFile:"source/"+name,encoding:.utf8)) }
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
if(aiStagesFor(fixture).join()!=='storyboard,archive,tts,design,references,blender,production')throw Error('source workflow');
if(aiReady(fixture,'production'))throw Error('image gate');
const parallel=JSON.parse(JSON.stringify(fixture));parallel.id='parallel';parallel.guide.steps.storyboard={approved:true};parallel.scenes.forEach(s=>{s.approvals={script:true}});if(aiStageApproved(parallel,'tts'))throw Error('parallel fixture audio');if(!aiReady(parallel,'tts')||!aiReady(parallel,'design'))throw Error('picture waits for audio');if(!aiParallelHint(parallel,'design')||!workflowNavigation(parallel,'design').includes('Làm song song được'))throw Error('parallel hint');if(aiReady(parallel,'production'))throw Error('clips before images');if(aiCurrent(parallel)!=='tts')throw Error('optional archive is not next');{const savedProjects=state.projects,savedSelected=selected,savedSave=save,savedRender=render,savedToast=toast;let toasts=[];save=render=function(){};toast=function(m){toasts.push(m)};const savedUUID=crypto.randomUUID;let seq=0;crypto.randomUUID=function(){return 'tid'+(++seq)};const tp=JSON.parse(JSON.stringify(parallel));tp.id='timeline';tp.timelineEntries=undefined;tp.scenes[0].archiveAssets=[{id:'arc',kind:'image',title:'Photo',path:'/arc.mp4',originalPath:'/arc.jpg',duration:1}];state.projects=[tp];selected=tp.id;const n=timelineEntries(tp).length;const html=timelineView(tp);if((html.match(/timeline-add/g)||[]).length!==n+1)throw Error('one insert slot per gap');openTimelineInsert(1);if(!timelineView(tp).includes('id="timeline-insert"')||!timelineInsertPanel(tp).includes('Photo'))throw Error('insert chooser lists project media');timelineInsertCover=false;insertTimelineLibrary('a:'+tp.scenes[0].id+':arc',1);const lib=timelineEntries(tp)[1];if(lib.assetId!=='arc'||lib.duration!==5||!lib.muteNarration||timelineInsertAt!==null)throw Error('library insert at slot');window.nativeTimelineImported({projectId:tp.id,insertAt:0,files:[{name:'a.mp4',path:'/a.mp4',duration:7.5},{name:'b.png',path:'/b.mp4',originalPath:'/b.png',duration:1,kind:'image'}],errors:['bad.mov']});const r=resolvedTimeline(tp);if(r.length!==n+3||r[0].name!=='a.mp4'||r[1].name!=='b.png'||r[1].duration!==5||r[1].sourceDuration!==1||!r[1].image||timelineSelected!==r[1].id)throw Error('multi-file import keeps order and position');if(!toasts.some(m=>m.includes('bad.mov')))throw Error('import reports skipped files');window.nativeTimelineImported({projectId:tp.id,path:'/legacy.mp4',name:'legacy.mp4',duration:3});if(!resolvedTimeline(tp).some(e=>e.name==='legacy.mp4'))throw Error('legacy single-file reply');timelineProject=tp.id;window.nativeTimeline({status:'measured',values:[{id:r[1].id,duration:1,videoDuration:1},{id:lib.id,duration:1,videoDuration:1},{id:r[0].id,duration:7.5,videoDuration:7.5}]});if(timelineEntries(tp).find(e=>e.id===r[1].id).duration!==5||timelineEntries(tp).find(e=>e.id===lib.id).duration!==5)throw Error('fit keeps still hold time');const tg=JSON.parse(JSON.stringify(parallel));tg.id='group';tg.timelineEntries=undefined;if(tg.scenes.length<2)tg.scenes.push({...JSON.parse(JSON.stringify(tg.scenes[0])),id:'second-scene',chapter:'Hai'});state.projects=[tg];selected=tg.id;tg.scenes[0].assets={...tg.scenes[0].assets,video:[{id:'lead-video',path:'/lead.mp4',selected:true,duration:6}]};const ge=timelineEntries(tg);const lead=ge[0];lead.duration=24;const sid=tg.scenes[0].id;openTimelineInsert(1);if(!timelineInsertPanel(tg).includes('Dùng chung lời kể của Cảnh 1')||!timelineInsertPanel(tg).includes("coverOf:'"+sid+"'"))throw Error('slot after scene offers shared narration');window.nativeTimelineImported({projectId:tg.id,insertAt:1,coverOf:sid,files:[{name:'c.mp4',path:'/c.mp4',duration:8},{name:'d.png',path:'/d.mp4',originalPath:'/d.png',duration:1,kind:'image'}]});const gr=resolvedTimeline(tg);if(gr.slice(0,3).some(e=>e.narrationGroup!==lead.id)||gr[3].narrationGroup||gr.slice(0,3).some(e=>Math.abs(e.duration-8)>0.01))throw Error('covers join the scene group and split its length');if(!gr[1].title.startsWith('Cảnh 1 · hình 2/3')||!timelineNarrationLane(gr).includes('chạy qua 3 hình'))throw Error('group labels');if(timelineView(tg).includes('Tắt lời kể đoạn này')&&timelineSelected===gr[2].id&&timelineGroupControls(tg,gr[2]).includes('Tắt lời kể'))throw Error('covers have no own narration toggle');timelineProject=tg.id;window.nativeTimeline({status:'measured',values:[{id:lead.id,duration:30,videoDuration:6,audioDuration:30},{id:gr[1].id,duration:8,videoDuration:8,audioDuration:0},{id:gr[2].id,duration:1,videoDuration:1,audioDuration:0}]});const fitted=timelineGroups(tg).get(lead.id);if(fitted.length!==3||Math.abs(fitted.reduce((n,e)=>n+e.duration,0)-30)>0.02||fitted.some(e=>Math.abs(e.duration-10)>0.02))throw Error('fit spreads voice across group');const savedSend=send;let previewBody=null;send=function(action,body){previewBody=body};timelineRequest('preview',gr[2].id);send=savedSend;const previewIds=(previewBody?.entries||[]).map(e=>e.id);if(previewIds.length!==3||!previewIds.includes(lead.id))throw Error('previewing a cover plays its group');moveTimeline(lead.id,1);const moved=timelineEntries(tg);if(moved[0].sceneId!==tg.scenes[1].id||moved[1].id!==lead.id||moved[2].coverOf!==sid||moved[3].coverOf!==sid)throw Error('scene moves with its covers');toasts=[];const hadConfirm='confirm' in globalThis,savedConfirm=globalThis.confirm;globalThis.confirm=function(){return true};removeTimeline(lead.id);if(hadConfirm)globalThis.confirm=savedConfirm;else delete globalThis.confirm;if(timelineEntries(tg).some(e=>e.coverOf)||!toasts.some(m=>m.includes('tách 2 hình')))throw Error('covers detach when scene removed');crypto.randomUUID=savedUUID;state.projects=savedProjects;selected=savedSelected;save=savedSave;render=savedRender;toast=savedToast}{const savedProjects=state.projects,savedSelected=selected,savedSave=save,savedRender=render,savedToast=toast,savedScene=typeof sceneIndex==='undefined'?0:sceneIndex;let toasts=[];save=render=function(){};toast=function(m){toasts.push(m)};const ep=JSON.parse(JSON.stringify(parallel));ep.id='edit';state.projects=[ep];selected=ep.id;sceneIndex=0;const es=ep.scenes[0];const all=()=>({script:true,audio:true,image:true,video:true});es.approvals=all();editField('notes',(es.notes||'')+' x');editField('chapter',(es.chapter||'')+' x');editField('time','00:00–00:31');if(JSON.stringify(es.approvals)!==JSON.stringify(all()))throw Error('notes/chapter/time keep approvals');es.approvals=all();editField('voice',es.voice+' sửa');if(!es.approvals.script||es.approvals.audio||!es.approvals.image||!es.approvals.video)throw Error('voice edit only resets audio');if(!toasts.some(m=>m.includes('giọng đọc')))throw Error('voice edit explains');es.approvals=all();editField('image',es.image+' close up');if(!es.approvals.script||!es.approvals.audio||es.approvals.image||es.approvals.video)throw Error('image edit resets image and clip');es.approvals=all();editField('voice','  ');if(es.approvals.script||!es.approvals.image)throw Error('emptied field withdraws only script');state.projects=savedProjects;selected=savedSelected;sceneIndex=savedScene;save=savedSave;render=savedRender;toast=savedToast}{const savedProjects=state.projects,savedSelected=selected,savedSave=save,savedRender=render,savedToast=toast;save=render=toast=function(){};state.projects=[parallel];selected=parallel.id;const ps=parallel.scenes[0];ps.angleImageMode=false;ps.assets={...ps.assets,image:[{id:'pi',path:'/p.png',selected:true,prompt:ps.image}]};approveReference(ps.id);if(!ps.approvals.image||ps.approvals.audio)throw Error('approve image before audio');state.projects=savedProjects;selected=savedSelected;save=savedSave;render=savedRender;toast=savedToast}const unready=JSON.parse(JSON.stringify(parallel));unready.guide.steps.storyboard={};unready.scenes[0].approvals={};if(aiReady(unready,'tts')||aiReady(unready,'design'))throw Error('storyboard gate');
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
c.evaluateScript("""
const partialProject={id:'partial',scenes:[],timelineEntries:[{id:'ready-1',path:'/one.mp4',name:'One',duration:2},{id:'missing',sceneId:'missing',duration:3},{id:'ready-2',path:'/two.mp4',name:'Two',duration:4}]};
state.projects=[partialProject];selected=partialProject.id;sent=[];
timelineRequest('preview');
if(sent.length!==1||sent[0].body.entries.map(e=>e.id).join(',')!=='ready-1,ready-2')throw Error('partial preview plays available clips in timeline order');
if(partialProject.timelineEntries.length!==3)throw Error('preview preserves missing timeline slots');
sent=[];timelineRequest('export');if(sent.length)throw Error('full export still requires all clips');
sent=[];timelineRequest('preview','missing');if(sent.length)throw Error('missing individual preview blocked');
partialProject.timelineEntries=[];sent=[];timelineRequest('preview');if(sent.length)throw Error('empty preview blocked');
""")
c.evaluateScript("""
const dialogScene={id:'dialog-scene',voice:'Original narration',chapter:'Dialogue',time:'00:00',approvals:{script:true,audio:true},assets:{audio:[{id:'old',selected:true,path:'/old.mp3',text:'Original narration'}]},dialogue:{enabled:true,turns:[{id:'t1',speakerId:'a',text:'[angry] Đi thôi!'},{id:'t2',speakerId:'b',text:'[whispers] Khoan đã.'}]}};
const dialogProject={id:'dialog-project',scenes:[dialogScene],ttsSettings:{voice:'',model:'eleven_v3'},dialogueSpeakers:[{id:'a',name:'A <script>',voice:'voice_a'},{id:'b',name:'B',voice:'voice_b'}],guide:{sourceMode:'script',steps:{storyboard:{approved:true,draft:{scenes:[]}}},brief:{}}};
state.projects=[dialogProject];selected=dialogProject.id;ttsPending=null;sent=[];
if(dialogueIssue(dialogProject,dialogScene,'eleven_v3'))throw Error('valid dialogue');
if(!dialogueIssue(dialogProject,dialogScene,'eleven_flash_v2_5'))throw Error('dialogue model validation');
if(ttsAssetCurrent(dialogScene,dialogScene.assets.audio[0]))throw Error('narration not current for dialogue');
if(!dialogueSceneView(dialogProject,dialogScene,false).includes('A &lt;script&gt;'))throw Error('speaker escaping');
generateSceneTTS(dialogScene.id);
if(sent.length!==1||sent[0].body.dialogueInputs[1].voice_id!=='voice_b'||sent[0].body.dialogueInputs[0].text!=='[angry] Đi thôi!')throw Error('ordered multi voice request');
window.nativeTTS({requestId:ttsPending.requestId,status:'completed',path:'/dialogue.mp3',name:'Dialogue'});
const dialogueAudio=dialogScene.assets.audio.find(a=>a.selected);
if(!ttsAssetCurrent(dialogScene,dialogueAudio)||narrationClips(dialogProject)[0].path!=='/dialogue.mp3')throw Error('dialogue integrates with player');
editDialogueSpeaker('b','voice','new_voice');if(ttsAssetCurrent(dialogScene,dialogueAudio)||dialogScene.approvals.audio)throw Error('voice change invalidates approval');
sent=[];startAllAudio();if(!sent[0]?.body.dialogueInputs||sent[0].body.dialogueInputs[1].voice_id!=='new_voice')throw Error('batch carries dialogue');
window.nativeTTS({requestId:ttsPending.requestId,status:'completed',path:'/dialogue-new.mp3',name:'New'});
if(dialogProject.ttsBatch.status!=='completed')throw Error('dialogue batch completes');
const oldSignature=dialogueSignature(dialogProject,dialogScene);moveDialogueTurn(dialogScene.id,'t2',-1);if(dialogueSignature(dialogProject,dialogScene)===oldSignature)throw Error('order invalidates dialogue');
dialogScene.dialogue.turns[0].text='x'.repeat(2001);if(!dialogueIssue(dialogProject,dialogScene,'eleven_v3'))throw Error('dialogue length validation');
const dialogSaved=JSON.parse(JSON.stringify(dialogProject));if(dialogSaved.dialogueSpeakers[1].voice!=='new_voice'||dialogSaved.scenes[0].dialogue.turns[0].id!=='t2')throw Error('dialogue persists');
""")
c.evaluateScript("""
const promptScene={id:'prompt-scene',chapter:'Test',voice:'Lời',image:'Image',video:'Old video prompt',approvals:{script:true,audio:true,image:true,video:true},assets:{image:[{id:'reference',path:'/image.png',selected:true}],audio:[{id:'voice',path:'/voice.mp3',selected:true}],video:[{id:'clip',path:'/old.mp4',selected:true,prompt:'Old video prompt'}]}};
const promptProject={id:'prompt-project',title:'CEO NVIDIA',scenes:[promptScene],videoSettings:{model:'test-i2v',duration:5,quality:'1080p'},guide:{brief:{},steps:{storyboard:{approved:true,draft:{scenes:[{chapter:'Test',voice:'Lời',image:'Image',video:'Old video prompt'}]},approvedResult:{scenes:[{chapter:'Test',voice:'Lời',image:'Image',video:'Old video prompt'}]}}}}};
state.projects=[promptProject];selected=promptProject.id;plenxImagePending=null;
setSceneVideoPrompt(promptScene.id,'New <camera> motion');
if(promptScene.video!=='New <camera> motion'||promptScene.approvals.video||!promptScene.approvals.audio||!promptScene.approvals.image||!promptScene.approvals.script)throw Error('video prompt only invalidates video approval');
if(promptScene.assets.video[0].path!=='/old.mp4'||!promptScene.assets.video[0].selected)throw Error('old clip preserved');
if(promptProject.guide.steps.storyboard.draft.scenes[0].video!==promptScene.video||promptProject.guide.steps.storyboard.approvedResult.scenes[0].video!==promptScene.video)throw Error('prompt sync to unchanged storyboard');
if(!videoPromptView(promptScene).includes('New &lt;camera&gt; motion')||!videoPromptView(promptScene).includes('Tạo clip mới'))throw Error('prompt editor escaping and old clip notice');
plenxVideoModels=[{id:'test-i2v',name:'Test',modes:['i2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video']}];sent=[];
generateSceneVideo(promptScene.id);
const outboundVideoPrompt=sent[0]?.body.prompt;
if(!outboundVideoPrompt?.endsWith(promptScene.video)||!outboundVideoPrompt.includes('CEO NVIDIA')||!outboundVideoPrompt.includes('phim tài liệu hiện đại'))throw Error('video payload keeps edited prompt and adds era context');
if(sent[0].body.sourcePrompt!==promptScene.video)throw Error('persisted source stays editable');
if(visualPromptBrief({visualPromptBrief:legacyVisualPromptBrief}).includes('hoặc yếu tố hiện đại')||visualPromptBrief({visualPromptBrief:'Cổ trang theo yêu cầu'})!=='Cổ trang theo yêu cầu')throw Error('replace legacy brief and preserve custom briefs');
const oldStyle={style:legacyVisualStyle,characters:[]};
if(sceneDesignPrompt({...promptProject,visualBible:oldStyle},promptScene).includes(legacyVisualStyle)||oldStyle.style!==legacyVisualStyle)throw Error('legacy style is replaced at generation without modifying stored project');
const sentPrompt=promptScene.video;setSceneVideoPrompt(promptScene.id,'blocked');if(promptScene.video!==sentPrompt)throw Error('editing blocked during active request');
plenxImagePending=null;promptScene.videoJob.status='failed';
setAIStoryPrompt(0,'video','Draft only');if(promptScene.video!==sentPrompt||promptProject.guide.steps.storyboard.draft.scenes[0].video!=='Draft only')throw Error('storyboard edits stay draft until approval');
if(!storyboardVoiceView(promptProject.guide.steps.storyboard).includes('Prompt tạo video'))throw Error('storyboard exposes editable video prompt');
""")
c.evaluateScript("""
const multiScene={id:'multi',chapter:'Cast',voice:'Narration',video:'SHOT 1 @IMAGE_2; SHOT 2 @IMAGE_1',approvals:{script:true,audio:true,image:true,video:true},assets:{image:[{id:'main',selected:true,path:'/main.png',name:'Main'}],video:[]},videoReferenceMode:'references',videoReferences:[{id:'face',path:'/face.png',name:'Face'},{id:'wide',path:'/wide.png',name:'Wide'}]};
const multiProject={id:'multi-project',scenes:[multiScene],videoSettings:{model:'grok-video',quality:'720p',duration:6}};state.projects=[multiProject];selected=multiProject.id;plenxImagePending=null;
plenxVideoModels=[{id:'grok-video',name:'Grok',modes:['i2v','r2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video','/developer/generate/video-omni']}];const refModel=plenxVideoModels[0];
if(videoReferenceIssue(multiScene,refModel,videoSettings(multiProject)))throw Error('valid multi refs');
if(!videoReferenceIssue(multiScene,{...refModel,modes:['i2v']},videoSettings(multiProject)))throw Error('unsupported model blocked');
sent=[];generateSceneVideo(multiScene.id);if(sent[0]?.body.referencePaths.join(',')!=='/face.png,/wide.png'||sent[0]?.body.endpoint!=='/developer/generate/video-omni'||sent[0]?.body.prompt?.endsWith('SHOT 1 <IMAGE_2>; SHOT 2 <IMAGE_1>')!==true)throw Error('ordered references and model syntax sent');
const snapshot=plenxImagePending;plenxImagePending=null;moveVideoReference(multiScene.id,'wide',-1);if(multiScene.videoReferences[0].path!=='/wide.png'||multiScene.approvals.video||!multiScene.approvals.image||!multiScene.approvals.audio)throw Error('reorder preserves other approvals');
nativeVideoResult({status:'completed',path:'/late.mp4',name:'Late',duration:6},snapshot);if(multiScene.assets.video[0].selected)throw Error('late result with old references not selected');
window.nativeAsset({request:{project:multiProject.id,scene:multiScene.id,kind:'image',videoReference:true},path:'/imported.png',name:'Imported'});if(multiScene.videoReferences.length!==3||multiScene.assets.image[0].path!=='/main.png'||!multiScene.approvals.image)throw Error('reference import preserves primary image');
const savedMulti=JSON.parse(JSON.stringify(multiProject));if(savedMulti.scenes[0].videoReferences[0].path!=='/wide.png'||savedMulti.scenes[0].videoReferences[2].path!=='/imported.png')throw Error('reference order persists');
multiScene.video='@IMAGE_4';if(!videoReferenceIssue(multiScene,refModel,videoSettings(multiProject)))throw Error('nonexistent prompt reference blocked');
""")
c.evaluateScript("""
multiScene.video='Old prompt';multiScene.videoReferences=[{id:'a1',path:'/a.png',angle:'Trung rộng',action:'Nhìn đội quân',seconds:3},{id:'a2',path:'/b.png',angle:'Cận mặt',action:'Nói dứt khoát'}];multiProject.videoSettings.duration=8;
const angleResult=buildAnglePrompt(multiScene,videoSettings(multiProject));if(angleResult.issue||!angleResult.text.includes('0.00–3.00')||!angleResult.text.includes('3.00–8.00')||!angleResult.text.includes('MỘT video')||!angleResult.text.includes('SHOT 2 — @IMAGE_2'))throw Error('one clip multi angle plan duration and binding');
plenxImagePending=null;applyAnglePrompt(multiScene.id);if(multiScene.previousAnglePrompt!=='Old prompt'||multiScene.video!==angleResult.text)throw Error('apply shot plan preserves previous prompt');restoreAnglePrompt(multiScene.id);if(multiScene.video!=='Old prompt')throw Error('restore prompt');
multiScene.videoReferences[1].seconds=6;if(!buildAnglePrompt(multiScene,videoSettings(multiProject)).issue)throw Error('overlong shot plan rejected');delete multiScene.videoReferences[1].seconds;multiScene.videoReferences[0].action='';if(!buildAnglePrompt(multiScene,videoSettings(multiProject)).issue)throw Error('missing action rejected');
const promptGuide={id:'brief',scenes:[],guide:{brief:{},steps:{}}};state.projects=[promptGuide];selected=promptGuide.id;
if(!visualPromptBriefView(promptGuide,false).includes('Định hướng prompt ảnh'))throw Error('visual brief shown from beginning');setVisualPromptBrief('Detailed custom lighting');if(aiContext(promptGuide,'ideas').visualPromptBrief!=='Detailed custom lighting')throw Error('visual brief passed to AI from first step');
""")
c.evaluateScript("""
const fakeFields={newTitle:{value:''},newAudience:{value:'Test audience'},newDialog:{close:function(){}}};document.getElementById=function(k){return fakeFields[k]||{value:'',textContent:''}};window.scrollTo=function(){};
state.projects=[];sent=[];excelImportPending={requestId:'cancel',mode:'new'};window.nativeImported({requestId:'cancel',cancelled:true});if(state.projects.length||excelImportPending)throw Error('cancel import leaves no blank project');
excelImportPending={requestId:'bad',mode:'new'};window.nativeImported({requestId:'bad',error:'Invalid'});if(state.projects.length)throw Error('invalid import does not create project');
excelImportPending={requestId:'excel',mode:'new',audience:'Test'};
const excelData={requestId:'excel',filename:'sample.xlsx',title:'Excel title',scenes:[{id:'raw',time:'00:00–00:25',chapter:'One',voice:'Exact original',image:'Image prompt',video:'Video prompt',notes:'Notes',approvals:{},assets:{}}],references:[{name:'Sources',rows:[{A:'Reference note'}]}],importInfo:{sheet:'Storyboard',headerRow:5,columns:{voice:'D'},durationSeconds:25,warnings:[]}};
window.nativeImported(excelData);const importedProject=project();if(state.projects.length!==1||importedProject.scenes.length||importedProject.guide.steps.storyboard.approved||importedProject.guide.steps.storyboard.draft.scenes[0].video!=='Video prompt'||importedProject.references.length!==1||sent.length)throw Error('import draft preserves fields and does not generate AI/media');
if(storyboardIssue(importedProject,importedProject.guide.steps.storyboard.draft))throw Error('imported storyboard ready for review');
approveAI();if(importedProject.scenes[0].voice!=='Exact original'||!importedProject.scenes[0].approvals.script||importedProject.scenes[0].assets.audio)throw Error('approval leads to TTS without generating');
const beforeImportScenes=importedProject.scenes;excelImportPending={requestId:'replace',mode:'replace',projectId:importedProject.id};window.nativeImported({...excelData,requestId:'replace'});if(importedProject.scenes!==beforeImportScenes||importedProject.guide.steps.storyboard.approved)throw Error('replacement retains active scenes until review');
""")
c.evaluateScript("""
let angleSequence=0;crypto.randomUUID=function(){return 'angle-id-'+(++angleSequence)};
const angleScene={id:'angle-scene',chapter:'Angles',time:'00:00–00:08',voice:'Narration',image:'Original image',video:'SHOT 1 @IMAGE_1; SHOT 2 @IMAGE_2',characterIds:['hero'],designAssigned:true,approvals:{script:true,audio:true,image:false},assets:{},angleImageMode:true,videoReferenceMode:'references',videoReferences:[{id:'wide',angle:'Wide',imagePrompt:'Wide shot, troops',images:[],approved:false},{id:'close',angle:'Close',imagePrompt:'Close up, hero',images:[],approved:false}]};
const angleProject={id:'angle-project',scenes:[angleScene],plenxImageModel:'angle-model',visualBible:{style:'Muted historical',approved:true,characters:[{id:'hero',name:'Hero',description:'Red cloak',approved:true,images:[{id:'hero-ref',path:'/hero.png',selected:true}]}]}};
state.projects=[angleProject];selected=angleProject.id;plenxImagePending=null;plenxImageModels=[{id:'angle-model',name:'Fixture',max_references:8,resolutions:['1k']}];sent=[];
startAngleImageBatch(angleScene.id);if(sent.length!==1||sent[0].body.angleImageId!=='wide'||!sent[0].body.prompt.includes('Wide shot, troops')||sent[0].body.referencePaths[0]!=='/hero.png')throw Error('first angle receives own prompt and shared identity');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/wide.png',name:'Wide'});
if(sent.length!==2||plenxImagePending.angleImageId!=='close'||!sent[1].body.prompt.includes('Close up, hero'))throw Error('queue sends second independent prompt');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/close.png',name:'Close'});
if(angleProject.imageBatch.status!=='completed'||angleScene.videoReferences[0].path!=='/wide.png'||angleScene.videoReferences[1].path!=='/close.png'||angleScene.videoReferences.some(r=>r.approved))throw Error('results stored per angle without auto approval');
if(!videoReferenceIssue(angleScene,{id:'grok-video',modes:['r2v'],endpoints:['/developer/generate/video-omni']},{duration:8,quality:'720p'}))throw Error('unapproved angles block video');
approveAllAngleImages(angleScene.id);if(!angleImagesComplete(angleProject,angleScene)||!angleScene.approvals.image||selectedSceneAsset(angleScene,'image').path!=='/wide.png')throw Error('approved angles select primary and complete scene');
editAngleImagePrompt(angleScene.id,'close','Changed close');if(angleScene.videoReferences[1].approved||angleScene.approvals.image||angleScene.videoReferences[1].images.length!==1)throw Error('editing preserves versions and requires reapproval');
sent=[];startAngleImageBatch(angleScene.id);if(sent.length!==1||plenxImagePending.angleImageId!=='close')throw Error('batch skips existing current angle');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'error',message:'Fixture error'});if(angleProject.imageBatch.status!=='paused'||sent.length!==1)throw Error('queue pauses without retry on failure');
clearAngleJob(angleScene.id,'close');sent=[];startAngleImageBatch(angleScene.id);stopImageBatch();window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/close-new.png',name:'New close'});if(angleProject.imageBatch.status!=='paused'||angleScene.videoReferences[1].images.length!==2)throw Error('stop retains current result and versions');
const savedAngles=JSON.parse(JSON.stringify(angleProject));if(savedAngles.scenes[0].videoReferences[1].imagePrompt!=='Changed close'||savedAngles.scenes[0].videoReferences[1].images.length!==2)throw Error('angle prompt and versions persist');
window.nativeAsset({request:{project:angleProject.id,scene:angleScene.id,kind:'image',angleImageId:'close'},path:'/manual-close.png',name:'Manual'});if(angleScene.videoReferences[1].path!=='/manual-close.png'||angleScene.videoReferences[1].approved)throw Error('manual import belongs to angle and awaits review');
angleProject.imageBatch.status='running';recoverAssistantState();if(angleProject.imageBatch.status!=='paused')throw Error('restart pauses angle queue');
if(!videoReferencesView(angleProject,angleScene).includes('Prompt tạo riêng ảnh góc máy này'))throw Error('separate prompt editor shown');
""")
c.evaluateScript("""
let shortSeq=0;crypto.randomUUID=function(){return 'short-id-'+(++shortSeq)};confirm=function(){return true};save=function(){};render=function(){};toast=function(){};
if(minutesLabel(0.5)!=='30 giây'||minutesLabel(1.5)!=='90 giây'||minutesLabel(10)!=='10 phút')throw Error('duration labels for shorts');
const shortP={id:'sp',title:'Short',format:'short',scenes:[{id:'a',time:'00:00–00:03',chapter:'Hook',voice:'Vì sao [calm] cọc gỗ thắng thuyền chiến?',image:'Ảnh',video:'Clip',approvals:{script:true,audio:true,image:true,video:true},assets:{audio:[{selected:true,path:'/hook.mp3',text:'Vì sao [calm] cọc gỗ thắng thuyền chiến?'}],image:[{selected:true,path:'/a.png'}],video:[{selected:true,path:'/a.mp4'}]}}],references:[],guide:{sourceMode:'script',sourceScript:'x',brief:{duration:1,audience:'Test'},steps:{storyboard:{approved:true}}}};
const longP={id:'lp',title:'Bạch Đằng',scenes:[],references:[],guide:{brief:{duration:10,audience:'Test'},steps:{}}};
state.projects=[shortP,longP];selected='sp';
const ctx=aiContext(shortP,'storyboard');if(ctx.format!=='short'||ctx.aspectRatio!=='9:16'||ctx.durationSeconds!==60)throw Error('AI context carries the short format');
if(aiContext(longP,'storyboard').aspectRatio!=='16:9')throw Error('long projects stay 16:9');
if(!visualPromptBrief(shortP).includes('9:16')||visualPromptBrief(longP).includes('9:16'))throw Error('default prompt brief follows the format');
plenxImagePending=null;sent=[];plenxImageRequest('generate',{projectId:'sp',sceneId:'a',prompt:'x',model:'m'});if(sent[0].body.aspectRatio!=='9:16')throw Error('image requests ask for 9:16');
plenxImagePending=null;sent=[];plenxImageRequest('models');if('aspectRatio' in sent[0].body)throw Error('model list request has no aspect');
plenxImagePending=null;sent=[];requestVideo('generate',{projectId:'sp',sceneId:'a'});if(sent[0].body.aspectRatio!=='9:16')throw Error('video requests ask for 9:16');plenxImagePending=null;
plenxVideoModels=[{id:'wide',modes:['i2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video']},{id:'tall',modes:['i2v'],aspect_ratios:['16:9','9:16'],endpoints:['/developer/generate/video']}];
if(videoCatalog(shortP).map(m=>m.id).join()!=='tall'||videoCatalog(longP).length!==2)throw Error('video models filtered by aspect');
sent=[];timelineRequest('export');const exp=sent.find(x=>x.action==='timeline').body;
if(exp.format!=='short'||exp.fill!=='blur'||exp.captions!==true||!exp.entries[0].captionText.includes('cọc gỗ'))throw Error('short export sends framing and captions');
setTimelineFrame('captions',false);sent=[];timelineRequest('export');const plain=sent.find(x=>x.action==='timeline').body;if(plain.captions!==false||'captionText' in plain.entries[0])throw Error('captions can be turned off');
if(!timelineView(shortP).includes('dọc 1080×1920'))throw Error('timeline shows vertical export');
// Cut shorts from a long video.
const longScene=(n,extra={})=>({id:'L'+n,time:'00:'+String((n-1)*20).padStart(2,'0')+'–00:'+String(n*20).padStart(2,'0'),chapter:'Chương '+n,voice:'Lời cảnh '+n,image:'Ảnh '+n,video:'Clip '+n,approvals:{script:true,audio:true,image:true,video:true},assets:{audio:[{selected:true,path:'/v'+n+'.mp3',text:'Lời cảnh '+n}],image:[{selected:true,path:'/i'+n+'.png'}],video:[{selected:true,path:'/c'+n+'.mp4'}]},...extra});
const source={id:'long',title:'Trận Bạch Đằng',scenes:[1,2,3,4].map(n=>longScene(n)),references:[],visualBible:{approved:true,characters:[]},timelineEntries:[{id:'t1',sceneId:'L1',duration:18},{id:'t2',sceneId:'L2',duration:21,trimStart:1},{id:'t2c',coverOf:'L2',path:'/cover.mp4',duration:5,narrationGroup:'t2'},{id:'t3',sceneId:'L3',duration:20},{id:'t4',sceneId:'L4',duration:19}],guide:{brief:{duration:1.5,audience:'Người yêu lịch sử'},steps:{storyboard:{approved:true}}}};
state.projects=[source];selected='long';
if(!shortCutPanel(source).includes('Cắt short từ video này'))throw Error('long project offers short cuts');if(shortCutPanel(shortP)!=='')throw Error('shorts do not offer cutting');
sent=[];suggestShorts();const ask=sent.find(x=>x.action==='assistantGenerate');if(!ask||ask.body.stage!=='short_cut'||ask.body.context.scenes.length!==4||ask.body.context.scenes[1].seconds!==26)throw Error('short cut request sends scenes with measured seconds');
window.nativeAssistant({requestId:ask.body.requestId,projectId:'long',stage:'short_cut',status:'completed',result:{options:[{id:'clip-1',title:'Cọc gỗ',description:'Bất ngờ'},{id:'clip-2',title:'Lỗi',description:''}],scenes:[{chapter:'L2|L3',voice:'Vì sao cọc gỗ thắng?',notes:'Theo dõi để xem tiếp.',image:'Dọc',video:'Chuyển động',time:'50 giây'},{chapter:'L9|L3',voice:'x',notes:'y',image:'',video:'',time:''}]}});
const cut=shortCut(source);if(cut.job.status!=='completed'||cut.candidates.length!==1||cut.candidates[0].from!==1||cut.candidates[0].to!==2)throw Error('valid ranges kept, unknown ids dropped');
openAssistant=function(pid){selected=pid};
const madeId=createShortProject(cut.candidates[0].id),made=state.projects.find(p=>p.id===madeId);
if(!made)throw Error('no short '+state.projects.map(p=>p.id).join()+' '+typeof createShortProject);if(made.format!=='short'||made.title!=='Cọc gỗ'||made.scenes.length!==4)throw Error('short project has hook, two scenes and closing line '+made.title+' '+made.scenes.length);
if(made.scenes[0].chapter!=='Hook'||made.scenes[0].voice!=='Vì sao cọc gỗ thắng?'||made.scenes[3].voice!=='Theo dõi để xem tiếp.')throw Error('hook and closing scenes');
if(made.scenes[1].assets.audio[0].path!=='/v2.mp3'||made.scenes[1].id==='L2'||!made.scenes[1].approvals.video)throw Error('range reuses narration and clips with new ids');
if(made.scenes[0].assets.video[0].path!=='/c3.mp4'&&made.scenes[0].assets.video[0].path!=='/c2.mp4'||made.scenes[0].approvals.audio)throw Error('hook borrows an approved clip and still needs narration');
const te=made.timelineEntries;if(te.length!==5||te[0].sceneId!==made.scenes[0].id||te[1].trimStart!==1||te[2].coverOf!==made.scenes[1].id||te[4].sceneId!==made.scenes[3].id)throw Error('timeline edits carried over with remapped scenes');
if(storyboardIssue(made,made.guide.steps.storyboard.approvedResult))throw Error('generated storyboard times match the brief: '+storyboardIssue(made,made.guide.steps.storyboard.approvedResult));
if(!storyboardApproved(made)||aiCurrent(made)!=='tts')throw Error('short opens on narration for the new lines');
if(source.scenes.length!==4||source.scenes[1].id!=='L2'||state.projects.length!==2)throw Error('long video untouched');
selected='long';if(createShortProject(cut.candidates[0].id)!==made.id||state.projects.length!==2)throw Error('creating twice opens the same short');
selected='long';cut.mode='series';cut.parts=2;sent=[];suggestShorts();const ask2=sent.find(x=>x.action==='assistantGenerate');if(ask2.body.context.mode!=='series'||ask2.body.context.parts!==2)throw Error('series request');
window.nativeAssistant({requestId:ask2.body.requestId,projectId:'long',stage:'short_cut',status:'completed',result:{options:[{id:'a',title:'P1',description:''},{id:'b',title:'P2',description:''}],scenes:[{chapter:'L1|L2',voice:'Hook 1',notes:'Phần sau',image:'',video:'',time:''},{chapter:'L3|L4',voice:'Hook 2',notes:'Theo dõi',image:'',video:'',time:''}]}});
createAllShortParts();const parts=state.projects.filter(p=>p.shortSource?.parts===2);if(parts.length!==2||!parts.some(p=>p.title==='Trận Bạch Đằng — Phần 1/2'))throw Error('series creates every part');
""")
c.evaluateScript("""
let backupSeq=0;crypto.randomUUID=function(){return 'bk-'+(++backupSeq)};confirm=function(){return true};save=function(){};render=function(){};let toasts=[];toast=function(m){toasts.push(m)};
const fakeDialog={open:false,innerHTML:'',showModal(){this.open=true},close(){this.open=false},addEventListener(){}};
const realGet=document.getElementById;document.getElementById=function(k){return k==='restoreDialog'&&fakeDialog.created?fakeDialog:null};document.createElement=function(){fakeDialog.created=true;return fakeDialog};document.body={appendChild(){}};
// Changelog
if(!versionAtMost('0.14.8','0.14.9')||versionAtMost('0.14.10','0.14.9')||!versionAtMost('0.14.9','0.14.9'))throw Error('version compare');
if(changelogHistoryView('0.14.8').includes('0.14.9')||!changelogHistoryView('0.14.8').includes('Short dọc 9:16'))throw Error('history lists only installed versions');
if(appChangelog.some(e=>!e.version||!e.items?.length))throw Error('every changelog entry has items');
updateState={...updateState,current:'0.14.8',status:'available',version:'0.14.9',notes:['Sao lưu <b>dự án</b>'],notesTitle:'Sao lưu'};
const upd=updaterView();if(!upd.includes('Có gì mới trong bản 0.14.9')||!upd.includes('Sao lưu &lt;b&gt;dự án&lt;/b&gt;'))throw Error('available update shows escaped notes');
state.projects=[{id:'keep',title:'Giữ',scenes:[]}];state.seenVersion='0.14.7';if(!whatsNewNotice().includes('Đã cập nhật lên Sử Studio 0.14.8'))throw Error('notice after update');
dismissWhatsNew();if(state.seenVersion!=='0.14.8'||whatsNewNotice()!=='')throw Error('notice dismissed once');
state.projects=[];delete state.seenVersion;if(whatsNewNotice()!==''||state.seenVersion!=='0.14.8')throw Error('fresh install shows no notice');
// Backup
state.projects=[{id:'keep',title:'Giữ',scenes:[]},{id:'clash',title:'Bản đang có',scenes:[{id:'s'}]}];
sent=[];backupProjects();if(sent[0].action!=='backupCreate'||sent[0].body.state.projects.length!==2||sent[0].body.name!==undefined)throw Error('backup all');
sent=[];backupProjects('clash');if(sent[0].body.state.projects.length!==1||sent[0].body.name!=='Ban-dang-co')throw Error('backup one project with ascii file name');
if(!backupPanel().includes('Sao lưu tất cả dự án')||!studioDashboard().includes('Khôi phục'))throw Error('backup entry points');
const backed={token:'T1',status:'preview',name:'b.zip',manifest:{version:'0.14.9',created:'2026-11-05T08:00:00Z'},files:3,bytes:2500000,projects:[{id:'clash',title:'Bản sao lưu',scenes:[]},{id:'new',title:'Dự án mới <x>',format:'short',scenes:[{},{}],guide:{steps:{storyboard:{status:'running'}}}},{title:'broken'}]};
window.nativeBackup(backed);if(!fakeDialog.open||!fakeDialog.innerHTML.includes('Khôi phục 2 dự án')||!fakeDialog.innerHTML.includes('Dự án mới &lt;x&gt;')||!fakeDialog.innerHTML.includes('1 dự án đang có trong app'))throw Error('restore preview lists valid projects and conflicts');
sent=[];confirmRestore();if(sent[0].action!=='backupApply'||sent[0].body.token!=='T1')throw Error('apply sends token');
if(state.projects.length!==2)throw Error('nothing merged before media is copied');
window.nativeBackup({status:'applied',token:'WRONG',copied:3});if(state.projects.length!==2)throw Error('wrong token ignored');
window.nativeBackup({status:'applied',token:'T1',copied:3});
if(state.projects.length!==4||state.projects.find(p=>p.id==='clash').title!=='Bản đang có'||!state.projects.some(p=>p.title==='Bản sao lưu (bản khôi phục)'&&p.id!=='clash'))throw Error('keep both adds a copy');
if(state.projects.find(p=>p.id==='new').guide.steps.storyboard.status==='running')throw Error('restored running steps are reset');
window.nativeBackup(backed);toggleRestoreProject('new',false);setRestoreMode('replace');sent=[];confirmRestore();window.nativeBackup({status:'applied',token:'T1',copied:0});
if(state.projects.length!==4||state.projects.find(p=>p.id==='clash').title!=='Bản sao lưu')throw Error('replace swaps the project in place');
window.nativeBackup(backed);sent=[];cancelRestore();if(sent[0].action!=='backupDiscard'||fakeDialog.open)throw Error('cancel discards staged backup');
document.getElementById=realGet;
""")
c.evaluateScript("""
let blSeq=0;crypto.randomUUID=function(){return 'bl-'+(++blSeq)};confirm=function(){return true};save=function(){};render=function(){};let blToasts=[];toast=function(m){blToasts.push(m)};
// A short project with no approved storyboard: the Blender stage must still be usable.
const blP={id:'blp',title:'Bạch Đằng',format:'short',scenes:[{id:'S1',time:'00:00–00:05',chapter:'Bãi cọc',voice:'Lời',image:'Ảnh bãi cọc',video:'Thuyền trôi',approvals:{},assets:{video:[{id:'old',path:'/old.mp4',selected:true,provider:'plenx'}]}}],references:[],guide:{brief:{duration:1,audience:'x'},steps:{}}};
state.projects=[blP];selected='blp';page='assistant';
const flow=aiStagesFor(blP);if(flow.indexOf('blender')!==flow.indexOf('production')-1)throw Error('blender stage sits before production');
if(aiCurrent(blP)==='blender')throw Error('optional stage is never the next step');
if(storyboardApproved(blP)||!aiReady(blP,'blender'))throw Error('blender stage open without a storyboard');
if(!workflowNavigation(blP,'ideas').includes('Dựng 3D · Blender'))throw Error('listed in navigation');
aiViewedStage='blender';if(!assistantView().includes('Chưa có clip 3D nào'))throw Error('empty state');
newBlenderClip();newBlenderClip();const [c2,c1]=blP.blenderClips;if(c1.title!=='Clip 3D 1'||c2.title!=='Clip 3D 2'||c1.mode!=='image'||!assistantView().includes('Từ ảnh · đẹp nhất'))throw Error('clips are created newest first, from images');
c1.mode='script';c2.mode='script';c1.autoContext=false;c2.autoContext=false;if(!assistantView().includes('Mô tả cảnh muốn dựng'))throw Error('script mode view');
sent=[];generateBlenderScript(c1.id);if(sent.length||!blToasts.at(-1).includes('mô tả'))throw Error('needs a prompt first');
setBlender(c1.id,'prompt','Bãi cọc gỗ dưới sông lúc chiều');setBlender(c1.id,'camera','dolly');setBlender(c1.id,'duration','99');if(c1.duration!==30)throw Error('duration clamped');setBlender(c1.id,'duration','6');
sent=[];generateBlenderScript(c1.id);const g=sent.find(x=>x.action==='assistantGenerate');if(!g||g.body.stage!=='blender_script'||g.body.context.prompt!=='Bãi cọc gỗ dưới sông lúc chiều'||g.body.context.aspectRatio!=='9:16'||g.body.context.camera!=='dolly'||'scene' in g.body.context)throw Error('AI request uses the clip prompt, not a scene');
sent=[];setBlender(c2.id,'prompt','x');generateBlenderScript(c2.id);if(sent.length||!blToasts.at(-1).includes('AI đang xử lý'))throw Error('one AI request at a time');
window.nativeAssistant({requestId:g.body.requestId,projectId:'blp',stage:'blender_script',status:'completed',result:{document:'```python\\nground()\\nbox("Thuyen")\\n```',title:'Bãi cọc',message:'Đã dựng.'}});
if(c1.script!=='ground()\\nbox("Thuyen")'||c1.ai.status!=='completed'||!blenderReady(c1))throw Error('script stored without fences');
blenderPromptFromScene(c2.id,'S1');if(!c2.prompt.includes('Ảnh bãi cọc')||c2.title!=='Bãi cọc')throw Error('optional prompt from a scene');
blenderInfo={status:'missing'};sent=[];renderBlender(c1.id);if(sent.length)throw Error('no render without Blender');
blenderInfo={status:'found',version:'4.2.3',path:'/Applications/Blender.app'};
sent=[];renderBlender(c1.id);const rq=sent.find(x=>x.action==='blenderRender').body;
if(rq.clipId!==c1.id||rq.mode!=='script'||rq.aspectRatio!=='9:16'||rq.camera!=='dolly'||rq.duration!==6||rq.script!=='ground()\\nbox("Thuyen")')throw Error('render request');
sent=[];renderBlender(c2.id);if(sent.length)throw Error('one render at a time');
window.nativeBlender({requestId:rq.requestId,projectId:'blp',clipId:c1.id,status:'running',progress:0.5,message:'Đang render khung 90/180…'});if(blenderJob.progress!==0.5)throw Error('progress kept');
window.nativeBlender({requestId:'other',projectId:'blp',clipId:c1.id,status:'completed',path:'/x.mp4'});if(!blenderJob)throw Error('foreign reply ignored');
window.nativeBlender({requestId:rq.requestId,projectId:'blp',clipId:c1.id,status:'completed',path:'/blender.mp4',name:'blender.mp4',duration:6,message:'Đã render 6.0 giây.'});
const video=blP.extraVideos.find(a=>a.provider==='blender');if(blenderJob||!video||video.path!=='/blender.mp4'||c1.renders.length!==1||selectedSceneAsset(blP.scenes[0],'video').id!=='old')throw Error('render lands in the project video library, scenes untouched');
if(!timelineLibrary(blP).some(i=>i.label.startsWith('Clip 3D Blender')))throw Error('render offered in the timeline + library');
const before=timelineEntries(blP).length;insertBlenderRender(c1.id,video.id);const last=timelineEntries(blP).at(-1);if(timelineEntries(blP).length!==before+1||last.path!=='/blender.mp4'||last.duration!==6||c1.renders[0].inserted!==1)throw Error('insert at the end of the timeline');
attachBlenderRender(c1.id,video.id,'S1');const sel=selectedSceneAsset(blP.scenes[0],'video');if(sel.path!=='/blender.mp4'||sel.provider!=='blender'||blP.scenes[0].approvals.video||c1.renders[0].attachedTo!=='S1')throw Error('attach to a scene on request');
// Model clips and the queue.
window.nativeBlender({status:'model',projectId:'blp',clipId:c2.id,path:'/assets/a-thuyen.glb',name:'thuyen.glb'});if(c2.mode!=='model'||!blenderReady(c2)||c2.title!=='Bãi cọc')throw Error('model picked, custom title kept');
newBlenderClip();const c3=blP.blenderClips[0];c3.mode='script';c3.script='box()';
sent=[];renderAllBlender();const q1=sent.find(x=>x.action==='blenderRender').body;if(q1.clipId!==c3.id||blenderQueue.length!==1)throw Error('queue skips the already rendered clip');
sent=[];window.nativeBlender({requestId:q1.requestId,projectId:'blp',clipId:c3.id,status:'completed',path:'/c3.mp4',name:'c3.mp4',duration:6,message:'ok'});const q2=sent.find(x=>x.action==='blenderRender')?.body;if(q2?.clipId!==c2.id||q2.mode!=='model'||q2.modelPath!=='/assets/a-thuyen.glb')throw Error('queue continues with the model clip');
sent=[];window.nativeBlender({requestId:q2.requestId,projectId:'blp',clipId:c2.id,status:'error',message:'Blender báo lỗi'});if(blenderJob||blenderQueue.length||c2.message!=='Blender báo lỗi')throw Error('error stops the queue');
// Script check: problems block rendering; a stale check result is not applied to a newer script.
newBlenderClip();const c4=blP.blenderClips[0];c4.mode='script';c4.autoContext=false;c4.script='Chưa tạo script Python: phiên này được giới hạn';blenderChecking[c4.id]=c4.script;
window.nativeBlender({status:'checked',projectId:'blp',clipId:c4.id,problems:['Lỗi cú pháp dòng 1: invalid syntax']});
if(blenderReady(c4)||!blenderCanRender(c4).includes('Script có lỗi')||!blenderClipView(blP,c4).includes('App chưa cho chạy script này'))throw Error('problems block rendering');
sent=[];fixBlenderProblems(c4.id);const fix=sent.find(x=>x.action==='assistantGenerate');if(!fix||!fix.body.context.feedback.includes('invalid syntax')||!fix.body.context.previousScript.includes('Chưa tạo'))throw Error('AI asked to fix the listed problems');
c4.ai.status='completed';c4.script='box()';blenderChecking[c4.id]='old script';window.nativeBlender({status:'checked',projectId:'blp',clipId:c4.id,problems:['x']});if(c4.check?.script==='box()')throw Error('stale check ignored');
blenderChecking[c4.id]='box()';window.nativeBlender({status:'checked',projectId:'blp',clipId:c4.id,problems:[]});if(!blenderReady(c4)||!blenderClipView(blP,c4).includes('Script hợp lệ'))throw Error('clean script ready');
// Effects and the 4-frame preview.
blenderJob=null;setBlenderEffect(c4.id,'fog','thick');setBlenderEffect(c4.id,'shake',false);sent=[];previewBlender(c4.id);const pv=sent.find(x=>x.action==='blenderRender').body;
if(!pv.preview||pv.quality!=='draft'||pv.effects.fog!==0.009||pv.effects.shake!==false||pv.effects.bloom!==true||pv.fps!==24)throw Error('preview request carries effects');
window.nativeBlender({requestId:pv.requestId,projectId:'blp',clipId:c4.id,status:'preview',paths:['/a/p1.jpg','/a/p2.jpg'],frames:[1,120],fps:24,message:'Đã render 2 khung xem trước.'});
if(blenderJob||c4.preview.paths.length!==2||!blenderClipView(blP,c4).includes('studio-image://asset/p1.jpg')||c4.renders?.length)throw Error('preview shown, not stored as a render');
setBlenderEffect(c4.id,'bloom',false);if(!blenderClipView(blP,c4).includes('thiết lập đã đổi'))throw Error('stale preview flagged');
// Duration follows the shot list, model library, AI library context, film look.
blenderJob=null;setBlender(c4.id,'duration','4');setBlender(c4.id,'prompt','0–2 giây: cận cảnh. 8–10 giây: slow motion');if(c4.duration!==10||promptSeconds('quay 12.5 giây')!==13||promptSeconds('không có mốc')!==0)throw Error('duration from the prompt beats');
state.modelLibrary=[];window.nativeBlender({status:'model',library:true,path:'/assets/x-Huey UH-1.glb',name:'Huey UH-1.glb'});const lib=state.modelLibrary[0];
if(!lib||lib.name!=='huey_uh_1'||lib.status!=='reading'||sent.at(-1).action!=='blenderInspect')throw Error('model added and sent for inspection');
window.nativeBlender({status:'inspected',modelId:lib.id,size:[17.4,3,4.4],parts:['Body','Rotor_Main'],animated:false});if(lib.status!=='ready'||lib.size[0]!==17.4)throw Error('inspection stored');
window.nativeBlender({status:'model',library:true,path:'/assets/y-huey.glb',name:'Huey UH 1.glb'});if(state.modelLibrary[0].name!=='huey_uh_1_2')throw Error('names stay unique');
window.nativeBlender({status:'inspectFailed',modelId:state.modelLibrary[0].id,message:'Blender không đọc được model.'});
editLibraryModel(lib.id,'name','Trực thăng Huey!');if(lib.name!=='truc_thang_huey')throw Error('names are slugged');editLibraryModel(lib.id,'description','UH-1 thời chiến tranh');
if(Object.keys(libraryModelPaths()).join()!=='truc_thang_huey')throw Error('only ready models are sent');
blenderLibrary={status:'ready',packs:[{key:'base',title:'Bầu trời',count:22,installed:22}],items:[{kind:'hdri',key:'overcast',title:'Trời u ám'},{kind:'model',key:'fern',title:'Dương xỉ'}]};
const ctxLib=aiLibraryContext();if(ctxLib.skies[0].name!=='overcast'||ctxLib.models[0].name!=='truc_thang_huey'||!ctxLib.models[0].parts.includes('Rotor_Main')||!ctxLib.models.some(m=>m.name==='fern'))throw Error('AI sees the library');
setBlenderEffect(c4.id,'film','film35');sent=[];previewBlender(c4.id);const lr=sent.find(x=>x.action==='blenderRender').body;if(lr.effects.film!=='film35'||lr.models.truc_thang_huey!=='/assets/x-Huey UH-1.glb')throw Error('render carries film look and models');
window.nativeBlender({requestId:lr.requestId,projectId:'blp',clipId:c4.id,status:'preview',paths:['/a/p.jpg'],frames:[1],fps:24,secondsPerFrame:2,message:'ok'});if(!c4.message.includes('ước tính'))throw Error('estimate shown');
if(!blenderView().includes('Kho model của bạn')&&blenderInfo.status==='found')throw Error('library panels');
sent=[];backupProjects();if(sent[0].body.state.modelLibrary.length!==2)throw Error('backups carry the model library');
// From images: shots from the project, imported files and PlenX, overlays, request shape.
newBlenderClip();const ci=blP.blenderClips[0];ci.autoContext=false;blenderJob=null;if(blenderReady(ci)||!blenderCanRender(ci).includes('ảnh'))throw Error('image clip needs a picture');
blP.scenes[0].assets.image=[{id:'im',path:'/assets/a-canh1.png',selected:true,name:'canh1.png'}];
if(!projectImages(blP).some(i=>i.path==='/assets/a-canh1.png'))throw Error('project pictures offered');
addBlenderShot(ci.id,'/assets/a-canh1.png','Cảnh 1');sent=[];importBlenderShot(ci.id);if(sent[0].action!=='asset'||sent[0].body.request.blenderClipId!==ci.id)throw Error('import from disk');
window.nativeAsset({request:{project:'blp',blenderClipId:ci.id,kind:'image'},path:'/assets/b-chatgpt.png',name:'chatgpt.png'});if(ci.shots.length!==2||ci.shots[1].path!=='/assets/b-chatgpt.png')throw Error('imported picture becomes a shot');
editBlenderShot(ci.id,ci.shots[0].id,'seconds','4.5');editBlenderShot(ci.id,ci.shots[1].id,'flashes','1.2, 2');moveBlenderShot(ci.id,ci.shots[1].id,-1);if(ci.shots[0].path!=='/assets/b-chatgpt.png'||blenderImageSeconds(ci)!==7.5)throw Error('shots edit and reorder');
setBlenderOverlay(ci.id,'smoke','0.65');setBlenderOverlay(ci.id,'embers','1');
sent=[];renderBlender(ci.id);const ir=sent.find(x=>x.action==='blenderRender').body;
if(ir.mode!=='image'||ir.shots.length!==2||ir.shots[0].flashes.join()!=='1.2,2'||ir.shots[1].seconds!==4.5||ir.overlays.smoke!==0.65||ir.shots[0].parallax!==true)throw Error('image render request');
blenderJob=null;ci.prompt="Chiến sĩ chạy trên đường bùn";blP.plenxImageModel='img';plenxImageModels=[{id:'img',name:'Ảnh',resolutions:['1k']}];plenxImagePending=null;sent=[];generateBlenderShotImage(ci.id);
const gi=sent.find(x=>x.action==='plenxImage');if(!gi||gi.body.kind!=='generate'||!gi.body.prompt.includes('đường bùn')||gi.body.aspectRatio!=='9:16')throw Error('PlenX image from the clip description');
window.nativePlenxImage({requestId:plenxImagePending.requestId,status:'completed',path:'/assets/c-plenx.png',name:'plenx.png',taskId:'t'});if(ci.shots.length!==3||ci.shots[2].provider!=='plenx'||plenxImagePending)throw Error('PlenX picture added as a shot');
// Free models from the internet: index, starter packs, download into the library with credits, AI suggestions.
window.nativeBlender({status:'modelIndex',ready:false});if(!modelFinderView().includes('Tải bảng tra cứu model'))throw Error('index needed first');
sent=[];openModelPack('quan_su');if(sent.length)throw Error('no search before the index');
window.nativeBlender({status:'modelIndex',ready:true});sent=[];openModelPack('quan_su');const packSearches=sent.filter(x=>x.action==='modelSearch');
if(packSearches.length!==modelPacks[0].items.length||!packSearches.some(x=>x.body.query==='UH-1 Huey'))throw Error('starter pack searches every item');
const hueyItem=modelList('quan_su').items.find(i=>i.name==='huey');const hueyToken=packSearches.find(x=>x.body.query==='UH-1 Huey').body.itemKey;
window.nativeBlender({status:'modelResults',itemKey:hueyToken,items:[{uid:'u1',name:'Bell UH-1 Iroquois',author:'helijah',authorUrl:'https://sketchfab.com/helijah',license:'Free Standard',faces:98000,animations:0,likes:246,thumbnail:'https://media.sketchfab.com/a.jpg',url:'https://sketchfab.com/3d-models/u1'}]});
if(hueyItem.status!=='done'||!modelFinderView().includes('Bell UH-1 Iroquois'))throw Error('results shown with pictures');
state.modelLibrary=[];sent=[];downloadFoundModel('quan_su',hueyItem.key,'u1');const dl=sent.find(x=>x.action==='modelDownload');if(!dl||dl.body.uid!=='u1')throw Error('download requested');
window.nativeBlender({status:'modelDownloaded',uid:'u1',itemKey:hueyToken,path:'/assets/z-u1.glb',bytes:5});const got=state.modelLibrary[0];
if(!got||got.name!=='huey'||got.credit.author!=='helijah'||got.credit.license!=='Free Standard'||sent.at(-1).action!=='blenderInspect')throw Error('downloaded model enters the library with credits');
sent=[];downloadFoundModel('quan_su',hueyItem.key,'u1');if(sent.length)throw Error('no duplicate download');
sent=[];copyModelCredits();if(!sent[0]||!sent[0].body.text.includes('helijah')||!sent[0].body.text.includes('sketchfab.com/3d-models/u1'))throw Error('credits copied');
newBlenderClip();const ca=blP.blenderClips[0];ca.mode='script';ca.autoContext=false;ca.prompt='Trực thăng bay qua rừng dừa';sent=[];suggestModelsForClip(ca.id);const sg=sent.find(x=>x.action==='assistantGenerate');
if(!sg||sg.body.stage!=='blender_assets'||!sg.body.context.existing.some(e=>e.startsWith('huey')))throw Error('AI suggestion request knows the library');
sent=[];window.nativeAssistant({requestId:sg.body.requestId,projectId:'blp',stage:'blender_assets',status:'completed',result:{scenes:[{chapter:'Xe Tăng T54',voice:'T-54 tank',notes:'Xe tăng tiến vào',time:'1'}]}});
const clipList=modelList('clip-'+ca.id);
const ctxNames=aiLibraryContext();if(ctxNames.skies.some(x=>typeof x!=='object'||x.name.includes('(')))throw Error('library names are sent apart from their labels');ca.assetAI={requestId:'again',status:'running'};window.nativeAssistant({requestId:'again',projectId:'blp',stage:'blender_assets',status:'completed',result:{scenes:[{chapter:'',voice:'',notes:'',time:'0'},{chapter:'jeep',voice:'Willys jeep',notes:'',time:'0'}]}});if(!modelList('clip-'+ca.id).items.some(i=>i.name==='jeep'))throw Error('broken items skipped, good ones kept');
ca.assetAI={requestId:'none',status:'running'};window.nativeAssistant({requestId:'none',projectId:'blp',stage:'blender_assets',status:'completed',result:{scenes:[]}});if(!ca.assetAI.message.includes('đã đủ')||!ca.assetAI.message.includes('huey')||!blToasts.at(-1).includes('đã đủ'))throw Error('empty suggestion explained in a toast, naming the models it will use');
if(!clipList||clipList.items[0].name!=='xe_tang_t54'||!clipList.items[0].essential||!sent.some(x=>x.action==='modelSearch'&&x.body.query==='T-54 tank'))throw Error('AI suggestions become searches');
// Context first: the AI researches the scene on the web, then writes the script with that background.
newBlenderClip();const cx=blP.blenderClips[0];cx.mode='script';cx.prompt='Xe tăng húc đổ cổng Dinh Độc Lập';blenderJob=null;
sent=[];generateBlenderScript(cx.id);const rs=sent.find(x=>x.action==='assistantGenerate');if(!rs||rs.body.stage!=='blender_context'||rs.body.context.prompt!==cx.prompt)throw Error('script waits for context research');
if(!blenderClipView(blP,cx).includes('AI đang tra cứu'))throw Error('research progress shown');
sent=[];window.nativeAssistant({requestId:rs.body.requestId,projectId:'blp',stage:'blender_context',status:'completed',result:{title:'30/4/1975',document:'Sự kiện: trưa 30/4/1975 xe tăng T-54 số 843 và Type 59 số 390 húc cổng Dinh Độc Lập.',sources:[{title:'Bảo tàng',url:'https://example.org/a'},{title:'bad',url:'javascript:x'}]}});
if(!cx.context.text.includes('843')||cx.context.sources.length!==1||needsContext(cx))throw Error('context stored with safe sources');
const sc=sent.find(x=>x.action==='assistantGenerate');if(!sc||sc.body.stage!=='blender_script'||!sc.body.context.background.includes('Type 59'))throw Error('script continues with the researched background');
window.nativeAssistant({requestId:sc.body.requestId,projectId:'blp',stage:'blender_script',status:'error',message:'x'});
cx.prompt='Xe tăng T-54 húc cổng Dinh';if(!needsContext(cx)||!blenderClipView(blP,cx).includes('nên tìm hiểu lại'))throw Error('changed description marks context stale');
editBlenderContext(cx.id,'Đã sửa tay: xe tăng 843');if(needsContext(cx))throw Error('edited context counts as current');
sent=[];modelIndex={status:'ready'};suggestModelsForClip(cx.id);const sa=sent.find(x=>x.action==='assistantGenerate');if(sa?.body.stage!=='blender_assets'||!sa.body.context.background.includes('Đã sửa tay'))throw Error('model suggestions use the background');
window.nativeAssistant({requestId:sa.body.requestId,projectId:'blp',stage:'blender_assets',status:'completed',result:{scenes:[]}});
cx.prompt='Mô tả mới';blP.plenxImageModel='img';plenxImagePending=null;sent=[];generateBlenderShotImage(cx.id);const ri=sent.find(x=>x.action==='assistantGenerate');if(ri?.body.stage!=='blender_context')throw Error('PlenX image researches first');
sent=[];window.nativeAssistant({requestId:ri.body.requestId,projectId:'blp',stage:'blender_context',status:'completed',result:{document:'Bối cảnh mới: cổng sắt màu trắng'}});const pi=sent.find(x=>x.action==='plenxImage');if(!pi||!pi.body.prompt.includes('cổng sắt màu trắng'))throw Error('PlenX prompt carries the background');
removeBlenderClip(c3.id);if(blP.blenderClips.some(c=>c.id===c3.id)||!blP.extraVideos.some(a=>a.path==='/c3.mp4'))throw Error('removing a clip keeps its rendered video');
""")
c.evaluateScript("""
let wakeSeq=0;crypto.randomUUID=function(){return 'wake-'+(++wakeSeq)};let wakeTimers=[];setTimeout=function(fn,ms){wakeTimers.push(fn)};confirm=function(){return true};save=function(){};render=function(){};let wakeToasts=[];toast=function(m){wakeToasts.push(m)};
// A task stuck in "error" because the Mac slept while polling: waking up checks it again; nothing new is created.
const wakeScene=(n,job)=>({id:'W'+n,time:'00:00–00:05',chapter:'C'+n,voice:'v',image:'i',video:'Clip',approvals:{script:true,image:true},assets:{image:[{id:'img'+n,path:'/i.png',selected:true}]},videoJob:job});
const wakeP={id:'wp',title:'Ngủ',scenes:[wakeScene(1,{status:'error',taskId:'task-9',prompt:'Clip',imageId:'img1',message:'Chưa đọc được tác vụ (HTTP 0)'}),wakeScene(2,null)],references:[],videoSettings:{model:'m',duration:5,quality:'720p'},guide:{brief:{duration:1,audience:'x'},steps:{}}};
state.projects=[wakeP];selected='wp';plenxVideoModels=[{id:'m',name:'M',modes:['i2v'],aspect_ratios:['16:9'],endpoints:['/developer/generate/video']}];
plenxImagePending={requestId:'hung',kind:'status',startedAt:Date.now()-10*60*1000};sent=[];window.nativeSystemWake();
if(plenxImagePending&&plenxImagePending.requestId==='hung')throw Error('a request hung over sleep is released');
if(wakeP.scenes[0].videoJob.status!=='queued'||!wakeToasts.at(-1).includes('kiểm tra lại 1'))throw Error('wake re-checks the stuck task');
wakeTimers.splice(0).forEach(f=>f());const st=sent.find(x=>x.action==='plenxVideo');if(!st||st.body.kind!=='status'||st.body.taskId!=='task-9')throw Error('status check sent for the stuck task, no new generation');
// Network still down: stays queued and keeps checking, slower.
window.nativePlenxImage({requestId:st.body.requestId,status:'queued',taskId:'task-9',transient:true,message:'Mất kết nối mạng'});if(wakeP.scenes[0].videoJob.status!=='queued'||!wakeTimers.length)throw Error('transient loss keeps polling');
wakeTimers.splice(0);
// "Create all missing clips" re-checks unsettled tasks instead of refusing.
wakeP.scenes[0].videoJob.status='error';plenxImagePending=null;sent=[];startVideoBatch();if(wakeP.videoBatch||!wakeToasts.at(-1).includes('Đang kiểm tra lại 1 tác vụ'))throw Error('batch start re-checks unsettled tasks');
wakeP.scenes[0].videoJob={status:'submitting',prompt:'Clip'};startVideoBatch();if(!wakeToasts.at(-1).includes('Cảnh 1')||!wakeToasts.at(-1).includes('Cho phép tạo mới'))throw Error('unknown submissions name the scene to check');
""")
print("UI scripts parse; sleep/wake recovery, Blender stage, changelog, backup and restore, Short format, framing, captions, short cuts and series, dashboard, overview, TTS, references, settings, escaping and workflow gate passed")
