// Background music for the timeline: imported or composed by ElevenLabs, looped under the video and
// lowered automatically while the narration plays (the mix itself happens in Timeline.swift).
let musicPending = null;

function projectMusic(p) {
    return p?.music?.path ? {volume: 0.25, duck: true, ...p.music} : null;
}

// What the export receives; nothing when the project has no music.
function musicExportOptions(p) {
    const m = projectMusic(p);
    return m ? {path: m.path, volume: Math.max(0, Math.min(1, Number(m.volume) || 0)), duck: m.duck !== false} : undefined;
}

function defaultMusicPrompt(p) {
    const style = visualStylePreset(p);
    return 'Nhạc nền không lời cho video lịch sử "' + (p.title || 'Sử Studio') + '". '
        + (style ? 'Không khí hoạt hình kể chuyện, nhẹ nhàng mà cuốn hút. ' : 'Không khí phim tài liệu điện ảnh, trầm, giàu cảm xúc. ')
        + 'Nhạc cụ hợp thời kỳ (trống, sáo trúc, đàn dây, dàn dây giao hưởng). Nhịp vừa phải, không lời hát, để lời kể nổi bật.';
}

function importMusic() {
    const p = project();
    if (!p || musicPending) return;
    send('asset', {request: {kind: 'music', project: p.id, music: true}});
}

function generateMusic(total) {
    const p = project();
    if (!p || musicPending) return toast('Đang tạo nhạc nền. Hãy đợi.');
    if (typeof ttsPending !== 'undefined' && ttsPending || typeof activeTTSBatch === 'function' && activeTTSBatch()) return toast('ElevenLabs đang tạo giọng đọc. Đợi xong rồi tạo nhạc.');
    const prompt = (document.getElementById('music-prompt')?.value || p.musicPrompt || defaultMusicPrompt(p)).trim();
    const seconds = Math.max(10, Math.min(180, Math.ceil(Number(total) || 60)));
    if (!prompt) return toast('Mô tả nhạc nền trước.');
    if (!confirm('Tạo ' + seconds + ' giây nhạc nền không lời bằng ElevenLabs Music? Dùng credit ElevenLabs; gói tài khoản cần hỗ trợ Music. Nhạc ngắn hơn video sẽ tự lặp.')) return;
    p.musicPrompt = prompt;
    musicPending = {requestId: id(), projectId: p.id, prompt, seconds, message: 'Đang gửi yêu cầu tạo nhạc…'};
    save();
    render();
    send('tts', {requestId: musicPending.requestId, kind: 'music', prompt, seconds});
}

function setMusic(key, value) {
    const p = project();
    if (!p?.music) return;
    p.music[key] = value;
    p.finalApproved = false;
    save();
    render();
}

function removeMusic() {
    const p = project();
    if (!p?.music || !confirm('Bỏ nhạc nền khỏi video? File nhạc vẫn nằm trong thư mục tài nguyên.')) return;
    delete p.music;
    p.finalApproved = false;
    save();
    render();
}

function musicPanel(p, total) {
    const m = projectMusic(p), busy = musicPending?.projectId === p.id;
    const prompt = p.musicPrompt || defaultMusicPrompt(p);
    return `<div class="music-panel"><div class="row"><b>Nhạc nền</b>${m ? `<span class="badge">${esc(m.name || 'Nhạc nền')}${m.duration ? ' · ' + audioClock(m.duration) : ''}</span>` : '<span class="hint">Chưa có</span>'}</div>
${m ? `<div class="row"><label>Âm lượng <input type="range" min="0" max="60" step="5" value="${Math.round(m.volume * 100)}" onchange="setMusic('volume',this.value/100)"> ${Math.round(m.volume * 100)}%</label><label><input type="checkbox" ${m.duck ? 'checked' : ''} onchange="setMusic('duck',this.checked)"> Tự hạ nhỏ khi có lời kể</label><button class="flat" onclick="send('openAsset',{path:${esc(JSON.stringify(m.path))}})">Nghe file</button><button class="flat destructive" onclick="removeMusic()">Bỏ nhạc</button></div>` : ''}
<div class="field"><label for="music-prompt">Mô tả nhạc để ElevenLabs soạn (không lời)</label><textarea id="music-prompt" ${busy ? 'disabled' : ''} onchange="project().musicPrompt=this.value;save()">${esc(prompt)}</textarea></div>
<div class="row"><button ${busy ? 'disabled' : ''} onclick="generateMusic(${Math.ceil(total || 0)})">${m ? 'Soạn lại bằng ElevenLabs' : 'Soạn nhạc bằng ElevenLabs'}</button><button ${busy ? 'disabled' : ''} onclick="importMusic()">Nhập file nhạc…</button></div>
<p class="hint" role="status">${busy ? esc(musicPending.message) : 'Nhạc tự lặp cho đủ video, mở và kết bằng fade; khi có lời kể nhạc giảm còn 30% âm lượng. Dùng nhạc bạn có quyền sử dụng; nhạc ElevenLabs soạn theo điều khoản tài khoản của bạn.'}</p></div>`;
}

const originalMusicAsset = window.nativeAsset;
window.nativeAsset = function (r) {
    if (!r.request?.music) return originalMusicAsset(r);
    const p = state.projects.find(p => p.id === r.request.project);
    if (!p || !r.path) return;
    p.music = {path: r.path, name: r.name || 'Nhạc nền', duration: r.duration, volume: p.music?.volume ?? 0.25, duck: p.music?.duck ?? true, source: 'import'};
    p.finalApproved = false;
    save();
    render();
    toast('Đã thêm nhạc nền. Xem liền mạch hoặc xuất MP4 để nghe cùng lời kể.');
};

const originalMusicTTS = window.nativeTTS;
window.nativeTTS = function (r) {
    const pending = musicPending;
    if (!pending || pending.requestId !== r.requestId) return originalMusicTTS(r);
    if (r.status === 'running') {
        pending.message = r.message || pending.message;
        render();
        return;
    }
    musicPending = null;
    const p = state.projects.find(p => p.id === pending.projectId);
    if (r.status === 'completed' && r.path && p) {
        p.music = {path: r.path, name: 'Nhạc ElevenLabs', duration: pending.seconds, volume: p.music?.volume ?? 0.25, duck: p.music?.duck ?? true, source: 'elevenlabs', prompt: pending.prompt};
        p.finalApproved = false;
        save();
        toast('Đã soạn nhạc nền. Xem liền mạch hoặc xuất MP4 để nghe cùng lời kể.');
    } else toast(r.message || 'Chưa tạo được nhạc nền.');
    render();
};
