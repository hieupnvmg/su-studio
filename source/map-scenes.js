// Map scenes rendered with Remotion: install check in Settings, and per scene an AI map plan (editable JSON),
// a preview frame and the rendered clip. Rendering and installation live in RemotionMaps.swift.
let remotionState = {status: null, requested: false, busy: false, message: ''};
let mapPending = null;

function remotionReady() {
    return !!remotionState.status?.ready;
}

function ensureRemotionStatus() {
    // Outside the macOS app there is nothing to ask.
    if (!remotionState.requested && (typeof native === 'undefined' || native)) {
        remotionState.requested = true;
        send('remotionStatus');
    }
}

function installRemotion(kind) {
    if (remotionState.busy || mapPending) return toast('Remotion đang cài hoặc dựng. Đợi xong trước.');
    const node = kind === 'node';
    if (!confirm(node
        ? 'Tải Node.js ' + 'v24 (khoảng 50 MB) từ nodejs.org vào thư mục của Sử Studio? Không cần quyền quản trị, không ảnh hưởng phần mềm khác.'
        : 'Tải các gói Remotion (khoảng 300 MB từ npm) và trình duyệt render (khoảng 150 MB) vào thư mục của Sử Studio? Có thể mất vài phút.')) return;
    remotionState.busy = true;
    remotionState.message = node ? 'Đang tải Node.js…' : 'Đang tải các gói Remotion…';
    refreshRemotionPanel();
    send(node ? 'remotionInstallNode' : 'remotionInstall');
}

function cancelRemotion() {
    send('remotionCancel');
}

function remotionRow(ok, label, detail) {
    return `<div class="row remotion-row"><span class="badge ${ok ? '' : 'amber'}">${ok ? '✓' : '✗'}</span><b>${esc(label)}</b><span class="hint">${esc(detail)}</span></div>`;
}

function remotionPanel() {
    ensureRemotionStatus();
    const st = remotionState.status, busy = remotionState.busy || !!mapPending;
    const node = st?.node || {}, packages = st?.packages || {}, browser = st?.browser || {};
    return `<section class="panel" id="remotion-panel"><h2>Remotion · cảnh bản đồ</h2><p class="hint">Dựng cảnh bản đồ động (mũi tên hành quân, địa danh, trận đánh) bằng Remotion ngay trên máy. Mọi thứ được cài vào thư mục riêng của Sử Studio, không cần quyền quản trị. Khi dựng cần mạng để tải nền bản đồ OpenFreeMap.</p>
${st ? remotionRow(node.ok, 'Node.js', node.ok ? node.version + (node.portable ? ' · cài riêng cho Sử Studio' : ' · có sẵn trên máy') : 'Chưa có (cần bản 18 trở lên)')
    + remotionRow(packages.ok, 'Gói Remotion', packages.ok ? 'Remotion ' + packages.version : 'Chưa cài')
    + remotionRow(browser.ok, 'Trình duyệt render', browser.ok ? 'Chrome Headless Shell đã tải' : 'Chưa tải') : '<p class="hint">Đang kiểm tra…</p>'}
<div class="row">${st && !node.ok ? `<button class="primary" ${busy ? 'disabled' : ''} onclick="installRemotion('node')">Cài Node.js</button>` : ''}${st && node.ok && !st.ready ? `<button class="primary" ${busy ? 'disabled' : ''} onclick="installRemotion('packages')">Cài Remotion</button>` : ''}${remotionState.busy ? '<button class="danger" onclick="cancelRemotion()">Dừng</button>' : `<button ${busy ? 'disabled' : ''} onclick="remotionState.requested=false;ensureRemotionStatus()">Kiểm tra lại</button>`}</div>
<p class="hint" role="status" id="remotion-status">${esc(remotionState.message || (st?.ready ? 'Đã sẵn sàng dựng cảnh bản đồ.' : ''))}</p>
<p class="hint">Giấy phép Remotion: miễn phí cho cá nhân và công ty tối đa 3 người. Công ty lớn hơn cần mua giấy phép công ty tại remotion.dev trước khi dùng. Nền bản đồ: OpenFreeMap © OpenMapTiles, dữ liệu © OpenStreetMap (app tự ghi nguồn trong video).</p></section>`;
}

function refreshRemotionPanel() {
    const el = document.getElementById?.('remotion-panel');
    if (el) el.outerHTML = remotionPanel();
}

// MARK: Per-scene map plans

function sceneMap(s) {
    return s.mapPlan ??= {json: '', feedback: ''};
}

function parseMapPlan(text) {
    try {
        const plan = JSON.parse(String(text || '').replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, ''));
        return plan && typeof plan === 'object' && !Array.isArray(plan) && Array.isArray(plan.start?.center) ? plan : null;
    } catch {
        return null;
    }
}

// A plan with no arrows and no battles renders as a bare map with a few dots.
function mapPlanEmpty(plan) {
    return !!plan && !(plan.moves || []).some(m => (m.path || []).length >= 2) && !(plan.clashes || []).length;
}

function setMapPrompt(sid, value) {
    const s = project()?.scenes.find(s => s.id === sid);
    if (!s) return;
    sceneMap(s).prompt = value;
    save();
    render();
}

function setMapPlanText(sid, value) {
    const p = project(), s = p?.scenes.find(s => s.id === sid);
    if (!s) return;
    sceneMap(s).json = value;
    save();
    render();
}

function requestMapPlan(sid) {
    const p = project(), s = p?.scenes.find(s => s.id === sid);
    if (!s) return;
    if (typeof anyAIBusy === 'function' && anyAIBusy()) return toast('AI đang xử lý một yêu cầu khác.');
    const m = sceneMap(s), prompt = String(m.prompt || '').trim();
    if (!prompt && !String(s.voice || '').trim()) return toast('Viết mô tả bản đồ trước (hoặc cảnh cần có lời kể).');
    m.ai = {requestId: id(), status: 'running', message: prompt ? 'AI đang tra cứu địa danh, diễn biến và dựng bản đồ theo mô tả…' : 'AI đang đọc lời kể, kiểm tra địa danh và lập kịch bản bản đồ…'};
    save();
    render();
    send('assistantGenerate', {requestId: m.ai.requestId, projectId: p.id, stage: 'map_plan', context: {projectTitle: p.title, chapter: s.chapter || '', prompt, voice: s.voice || '', seconds: motionSeconds(p, s), aspectRatio: projectAspect(p), previousPlan: m.json || '', feedback: m.feedback || ''}});
}

const originalMapAssistant = window.nativeAssistant;
window.nativeAssistant = function (r) {
    if (r.stage !== 'map_plan') return originalMapAssistant(r);
    const p = state.projects.find(p => p.id === r.projectId), s = p?.scenes.find(s => s.mapPlan?.ai?.requestId === r.requestId);
    if (!s) return;
    const a = s.mapPlan.ai;
    a.message = r.message || a.message;
    if (r.status === 'running') {
        const el = document.getElementById?.('map-ai-' + s.id);
        if (el) el.textContent = a.message;
        return;
    }
    a.status = r.status;
    const plan = r.status === 'completed' ? parseMapPlan(r.result?.document) : null;
    if (plan) {
        s.mapPlan.json = JSON.stringify(plan, null, 2);
        a.message = (mapPlanEmpty(plan) ? 'Kịch bản chưa có mũi tên hay trận đánh nào. Ghi rõ trong mô tả ai đi từ đâu đến đâu, hoặc góp ý "vẽ mũi tên …" rồi dựng lại. ' : '') + (r.result?.message || 'Đã lập kịch bản bản đồ. Xem trước rồi dựng.');
    } else if (r.status === 'completed') a.message = 'AI trả về kịch bản chưa đọc được. Bấm lập lại.';
    save();
    render();
};

function renderMapScene(sid, still) {
    const p = project(), s = p?.scenes.find(s => s.id === sid);
    if (!s) return;
    if (!remotionReady()) return toast('Cài Remotion trong Cài đặt & kết nối trước.');
    if (mapPending || remotionState.busy) return toast('Remotion đang bận. Đợi xong hoặc dừng trước.');
    const plan = parseMapPlan(sceneMap(s).json);
    if (!plan) return toast('Kịch bản bản đồ chưa phải JSON hợp lệ (cần start.center và zoom).');
    const seconds = motionSeconds(p, s);
    mapPending = {requestId: id(), projectId: p.id, sceneId: s.id, still, seconds, message: still ? 'Đang dựng khung xem trước…' : 'Đang dựng cảnh bản đồ…'};
    render();
    send('remotionRender', {requestId: mapPending.requestId, plan, seconds, aspectRatio: projectAspect(p), still, frame: seconds * 0.75});
}

window.nativeRemotion = function (r) {
    if (r.status === 'status') {
        remotionState.status = r;
        remotionState.busy = !!r.busy && remotionState.busy;
        refreshRemotionPanel();
        return;
    }
    if (r.status === 'progress') {
        if (mapPending) {
            mapPending.message = r.message;
            const el = document.getElementById?.('map-status-' + mapPending.sceneId);
            if (el) el.textContent = r.message;
        } else {
            remotionState.message = r.message;
            const el = document.getElementById?.('remotion-status');
            if (el) el.textContent = r.message;
        }
        return;
    }
    if (r.requestId && mapPending?.requestId === r.requestId) {
        const pending = mapPending;
        mapPending = null;
        const p = state.projects.find(p => p.id === pending.projectId), s = p?.scenes.find(s => s.id === pending.sceneId);
        if (r.status === 'completed' && r.path && s) {
            if (pending.still) {
                sceneMap(s).preview = r.path;
                toast('Đã dựng khung xem trước.');
            } else {
                s.assets ??= {};
                s.assets.video ??= [];
                s.assets.video.forEach(a => a.selected = false);
                s.assets.video.push({id: id(), path: r.path, name: r.name, selected: true, duration: r.duration, provider: 'remotion-map', mapPlan: sceneMap(s).json, created: new Date().toISOString()});
                invalidate(p, s, 'video');
                toast('Đã dựng cảnh bản đồ. Xem thử trên timeline rồi duyệt clip.');
            }
            save();
        } else toast(r.message || 'Chưa dựng được cảnh bản đồ.');
        render();
        return;
    }
    // Install finished or failed.
    if (r.status === 'installed' || r.status === 'error') {
        remotionState.busy = false;
        remotionState.message = r.message || '';
        if (r.node) remotionState.status = {...r, status: 'status'};
        if (r.message) toast(r.message);
        refreshRemotionPanel();
        render();
    }
};

function mapSceneView(p, s) {
    const m = s.mapPlan || {}, ready = remotionReady(), mine = mapPending?.sceneId === s.id, busy = !!mapPending || remotionState.busy;
    const aiRunning = m.ai?.status === 'running', plan = parseMapPlan(m.json);
    ensureRemotionStatus();
    return `<details class="map-scene" ${m.json || m.prompt || mine ? 'open' : ''}><summary><b>Cảnh bản đồ · Remotion</b> <span class="hint">mũi tên hành quân, địa danh, trận đánh trên bản đồ</span></summary>
${!ready ? `<p class="hint">Chưa cài Remotion trên máy này. <button class="flat" onclick="go('settings')">Mở Cài đặt để cài</button></p>` : ''}
<div class="field"><label>Mô tả bản đồ muốn dựng</label><textarea class="map-prompt" ${aiRunning ? 'disabled' : ''} placeholder="Ví dụ: Trận Bạch Đằng năm 938. Mở đầu nhìn toàn vùng cửa sông Bạch Đằng, thuyền Nam Hán từ biển tiến vào khi nước lên, quân Ngô Quyền giả thua nhử vào bãi cọc, nước rút thì phục binh hai bên bờ đổ ra đánh. Kết thúc cận cảnh bãi cọc." onchange="setMapPrompt('${s.id}',this.value)">${esc(m.prompt || '')}</textarea><p class="hint">Viết tự do như kể cho người dựng: trận nào, ở đâu, các phe, diễn biến theo thứ tự, muốn mở đầu và kết thúc ở đâu. Để trống thì AI dựa vào lời kể của cảnh.</p></div>
<div class="row"><button class="primary" ${aiRunning ? 'disabled' : ''} onclick="requestMapPlan('${s.id}')">${m.json ? 'AI dựng lại bản đồ' : 'AI dựng bản đồ'}${m.prompt ? ' từ mô tả' : ' từ lời kể'}</button>${aiRunning ? `<span class="hint" id="map-ai-${s.id}">${esc(m.ai.message)}</span>` : m.ai?.message ? `<span class="hint">${esc(m.ai.message)}</span>` : ''}</div>
<div class="field"><label>Kịch bản bản đồ (JSON · toạ độ [kinh độ, vĩ độ], giây trong clip)</label><textarea class="map-json" spellcheck="false" ${aiRunning ? 'disabled' : ''} onchange="setMapPlanText('${s.id}',this.value)">${esc(m.json || '')}</textarea>${m.json && !plan ? '<p class="hint" style="color:#a04b32">JSON chưa hợp lệ hoặc thiếu start.center / zoom.</p>' : ''}${mapPlanEmpty(plan) ? '<p class="hint" style="color:#a04b32">Kịch bản chưa có mũi tên (moves) hay trận đánh (clashes): clip sẽ chỉ có nền bản đồ và vài địa danh. Bấm AI dựng lại kèm góp ý, hoặc thêm vào JSON.</p>' : ''}</div>
<div class="field"><label>Góp ý cho AI khi lập lại</label><input value="${esc(m.feedback || '')}" placeholder="Ví dụ: thêm mũi tên quân Pháp rút về Mường Thanh, zoom gần hơn" onchange="sceneMap(project().scenes.find(x=>x.id==='${s.id}')).feedback=this.value;save()"></div>
<div class="row">${mine ? `<span class="hint" id="map-status-${s.id}" role="status">${esc(mapPending.message)}</span>` : `<button ${!ready || !plan || busy ? 'disabled' : ''} onclick="renderMapScene('${s.id}',true)">Xem trước khung hình</button><button class="primary" ${!ready || !plan || busy ? 'disabled' : ''} onclick="renderMapScene('${s.id}',false)">Dựng cảnh bản đồ · ${motionSeconds(p, s)} giây</button>`}</div>
${m.preview ? `<img class="map-preview" src="${esc(referenceImageURL({path: m.preview}))}" alt="Khung xem trước cảnh bản đồ" onerror="this.hidden=true">` : ''}</details>`;
}
