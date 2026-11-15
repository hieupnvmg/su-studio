// "Ảnh động": turn a scene's chosen image into a moving clip on this Mac (camera move + overlay), no video credit.
// Rendering happens in MotionStill.swift; the result is saved as one of the scene's clips like a PlenX video.
let motionPending = null;

const motionMoves = [['auto', 'Tự chọn'], ['push', 'Đẩy vào'], ['pull', 'Kéo ra'], ['left', 'Lia sang trái'], ['right', 'Lia sang phải'], ['rise', 'Nâng máy']];
const motionOverlays = [['none', 'Không'], ['dust', 'Bụi lơ lửng'], ['embers', 'Tàn lửa'], ['smoke', 'Khói sương'], ['rain', 'Mưa']];

function motionChoice(p, s) {
    return {move: 'auto', overlay: 'none', ...p.motionSettings, ...s.motion};
}

function setSceneMotion(sid, key, value) {
    const p = project(), s = p?.scenes.find(s => s.id === sid);
    if (!s) return;
    s.motion = {...s.motion, [key]: value};
    p.motionSettings = {...p.motionSettings, [key]: value};
    save();
    render();
}

// Clip length: the timeline slot already fitted to the narration, else the scene's own time range.
function motionSeconds(p, s) {
    const entry = (p.timelineEntries || []).find(e => e.sceneId === s.id && !e.coverOf && Number(e.duration) > 0);
    const seconds = entry ? Number(entry.duration) : sceneSeconds(s);
    return Math.max(2, Math.min(60, Math.round(seconds * 10) / 10));
}

function motionSeed(s) {
    let h = 7;
    for (const c of s.id + (s.assets?.video?.length || 0)) h = (h * 31 + c.charCodeAt(0)) % 100000;
    return h;
}

function motionBusy() {
    return !!motionPending;
}

function generateMotionStill(sid, batch = false) {
    const p = project(), s = p?.scenes.find(s => s.id === sid);
    if (!s) return;
    if (motionPending) return toast('Đang tạo một ảnh động. Đợi xong hoặc dừng trước.');
    const image = selectedSceneAsset(s, 'image');
    if (!image?.path) return toast('Cảnh ' + (p.scenes.indexOf(s) + 1) + ' chưa có ảnh. Tạo hoặc chọn ảnh ở bước Ảnh tham chiếu trước.');
    const choice = motionChoice(p, s), seconds = motionSeconds(p, s);
    motionPending = {requestId: id(), projectId: p.id, sceneId: s.id, imageId: image.id, ...choice, seconds, batch, progress: 0, message: 'Đang dựng ảnh động…'};
    render();
    send('motionStill', {requestId: motionPending.requestId, imagePath: image.path, move: choice.move, overlay: choice.overlay, seconds, aspectRatio: projectAspect(p), seed: motionSeed(s)});
}

// Scenes that have an image but no clip yet.
function motionMissingScenes(p) {
    return p.scenes.filter(s => !selectedSceneAsset(s, 'video') && selectedSceneAsset(s, 'image')?.path);
}

function startMotionBatch() {
    const p = project();
    if (!p || motionPending) return;
    const list = motionMissingScenes(p);
    if (!list.length) return toast('Không còn cảnh nào có ảnh mà chưa có clip.');
    if (!confirm('Tạo ảnh động cho ' + list.length + ' cảnh chưa có clip? Dựng ngay trên máy, không dùng credit. Bạn vẫn có thể tạo clip PlenX cho cảnh nào cần chuyển động thật.')) return;
    p.motionBatch = {status: 'running', done: 0, total: list.length};
    save();
    generateMotionStill(list[0].id, true);
}

function stopMotion() {
    const p = motionPending && state.projects.find(p => p.id === motionPending.projectId);
    if (p?.motionBatch) p.motionBatch.status = 'stopping';
    send('motionStillCancel');
}

window.nativeMotionStill = function (r) {
    const pending = motionPending;
    if (!pending || pending.requestId !== r.requestId) return;
    const p = state.projects.find(p => p.id === pending.projectId), s = p?.scenes.find(s => s.id === pending.sceneId);
    if (r.status === 'running') {
        pending.progress = r.progress || 0;
        pending.message = r.message || pending.message;
        const el = document.getElementById?.('motion-status-' + pending.sceneId);
        if (el) el.textContent = pending.message; else render();
        return;
    }
    motionPending = null;
    const batch = p?.motionBatch;
    if (r.status === 'completed' && r.path && s) {
        s.assets ??= {};
        s.assets.video ??= [];
        s.assets.video.forEach(a => a.selected = false);
        s.assets.video.push({id: id(), path: r.path, name: r.name, selected: true, duration: r.duration, provider: 'motion', imageId: pending.imageId, motion: {move: pending.move, overlay: pending.overlay}, created: new Date().toISOString()});
        invalidate(p, s, 'video');
        if (pending.batch && batch?.status === 'running') {
            batch.done++;
            const next = motionMissingScenes(p)[0];
            save();
            if (next) { generateMotionStill(next.id, true); return; }
            delete p.motionBatch;
            toast('Đã tạo ảnh động cho ' + batch.done + ' cảnh. Xem thử trên timeline rồi duyệt clip.');
        } else toast(r.message || 'Đã tạo ảnh động.');
    } else {
        if (p?.motionBatch) delete p.motionBatch;
        toast(r.message || 'Chưa tạo được ảnh động.');
    }
    if (p?.motionBatch?.status === 'stopping') delete p.motionBatch;
    save();
    render();
};

function motionOptions(list, value) {
    return list.map(([v, l]) => `<option value="${v}" ${v === value ? 'selected' : ''}>${l}</option>`).join('');
}

function motionStillView(p, s) {
    const choice = motionChoice(p, s), mine = motionPending?.sceneId === s.id, busy = !!motionPending, image = selectedSceneAsset(s, 'image');
    return `<div class="motion-still"><div class="row"><b>Ảnh động · miễn phí</b><span class="hint">Dựng từ ảnh đang chọn của cảnh, máy quay chuyển động và lớp phủ, không dùng credit.</span></div>
<div class="row"><label>Máy quay <select ${busy ? 'disabled' : ''} onchange="setSceneMotion('${s.id}','move',this.value)">${motionOptions(motionMoves, choice.move)}</select></label><label>Lớp phủ <select ${busy ? 'disabled' : ''} onchange="setSceneMotion('${s.id}','overlay',this.value)">${motionOptions(motionOverlays, choice.overlay)}</select></label>
${mine ? `<button class="danger" onclick="stopMotion()">Dừng</button>` : `<button ${busy || !image ? 'disabled' : ''} onclick="generateMotionStill('${s.id}')">Tạo ảnh động · ${motionSeconds(p, s)} giây</button>`}</div>
${mine ? `<p class="hint" id="motion-status-${s.id}" role="status">${esc(motionPending.message)}</p>` : !image ? '<p class="hint">Cần chọn ảnh cho cảnh ở bước Ảnh tham chiếu trước.</p>' : ''}</div>`;
}

function motionBatchView(p) {
    const missing = motionMissingScenes(p).length, b = p.motionBatch;
    return `<div class="row"><button ${motionPending || !missing ? 'disabled' : ''} onclick="startMotionBatch()">Ảnh động cho ${missing} cảnh chưa có clip · miễn phí</button>${b && motionPending ? `<button class="danger" onclick="stopMotion()">Dừng ảnh động</button><span class="hint">Đã xong ${b.done}/${b.total} cảnh</span>` : ''}</div>`;
}
