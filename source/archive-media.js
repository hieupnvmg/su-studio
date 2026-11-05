let archiveResults = {};
const archiveRequests = new Map();
let archiveCatalogOnly = false;
let archiveIncludeWeb = true;

function useSceneArchivePrompt(sid) {
    const scene = referenceScene(sid);
    scene.archiveQuery = (scene.image || scene.chapter || project().title).slice(0, 300);
    document.getElementById('archive-query-' + sid).value = scene.archiveQuery;
    save();
}

function archiveRequest(sid, kind, index, local = false) {
    const p = project(), s = p.scenes.find(scene => scene.id === sid);
    if (!s) return;
    const key = p.id + ':' + sid;
    const item = archiveResults[key]?.items?.[index];
    if (index !== undefined && (!item || item.busy || (!local && (!item.url || (!item.web && !item.license))))) return;
    if (item && s.archiveAssets?.some(a => archiveAssetKey(a) === archiveAssetKey(item))) return;
    const query = document.getElementById('archive-query-' + sid).value.trim();
    if (!item && (archiveResults[key]?.busy || archiveResults[key]?.webBusy)) return;
    if (!item && !query) return toast('Nhập prompt tìm tư liệu.');
    const requestId = id();
    if (item) item.busy = true;
    else {
        s.archiveQuery = query;
        save();
        const previousSearch = archiveResults[key];
        if (previousSearch) archiveRequests.delete(previousSearch.requestId);
        archiveResults[key] = {requestId, busy:true, webBusy:archiveIncludeWeb, items:[], warnings:[]};
    }
    archiveRequests.set(requestId, {pid:p.id, sid, key, item, kind});
    render();
    send(local ? 'archiveImport' : item ? 'archiveDownload' : 'archiveSearch', {
        requestId, query, kind:item?.kind || kind, url:item?.url, projectId:p.id,
        includeWeb:!item && archiveIncludeWeb, web:!!item?.web, referer:item?.web ? item.source : undefined
    });
}

window.nativeArchiveMedia = function(result) {
    const pending = archiveRequests.get(result.requestId);
    if (!pending) return;
    if (pending.item) archiveRequests.delete(result.requestId);
    const p = state.projects.find(project => project.id === pending.pid);
    const s = p?.scenes.find(scene => scene.id === pending.sid);
    if (!s) {
        archiveRequests.delete(result.requestId);
        return;
    }
    if (pending.item) {
        const {busy, thumbnail, ...metadata} = pending.item;
        pending.item.busy = false;
        if (result.error) toast(result.error);
        else if (!result.cancelled) {
            s.archiveAssets ??= [];
            s.archiveAssets.push({...metadata, id:id(), name:metadata.title, path:result.path,
                originalPath:result.originalPath, duration:result.duration});
            save();
        }
    } else if (archiveResults[pending.key]?.requestId === result.requestId) {
        const search = archiveResults[pending.key];
        search.items.push(...(result.items || []));
        search.busy = false;
        search.error = result.error;
        search.warnings.push(...(result.warnings || []));
        if (!search.webBusy) archiveRequests.delete(result.requestId);
    }
    if (project()?.id === p.id) render();
};

window.nativeArchiveWeb = function(update) {
    const pending = archiveRequests.get(update.requestId);
    const search = pending && archiveResults[pending.key];
    if (!search || search.requestId !== update.requestId) return;
    if (update.status === 'running') return;
    search.webBusy = false;
    if (update.status === 'completed') {
        const httpsURL = value => {
            try {
                const url = new URL(value);
                return url.protocol === 'https:' && !url.username && !url.password ? url : null;
            } catch { return null; }
        };
        const seen = new Set();
        for (const row of (update.result?.items || []).slice(0, 24)) {
            const url = httpsURL(row.source);
            if (!url || !row.title?.trim()) continue;
            url.hash = '';
            if (seen.has(url.href)) continue;
            seen.add(url.href);
            search.items.push({
                title:row.title, provider:row.provider || url.hostname, source:url.href,
                thumbnail:httpsURL(row.thumbnail)?.href || '', recordDate:row.recordDate,
                url:httpsURL(row.mediaURL)?.href || '',
                recordType:'Nguồn web · cần đối chiếu', note:row.note, kind:pending.kind,
                catalogued:false, web:true
            });
        }
    } else if (update.message) {
        search.warnings.push('Tìm web: ' + update.message);
    }
    if (!search.busy) archiveRequests.delete(update.requestId);
    if (project()?.id === pending.pid) render();
};

function finishArchive(next) {
    aiStep(project(), 'archive').approved = true;
    aiViewedStage = next;
    save();
    render();
    window.scrollTo(0, 0);
}

function archiveView() {
    const p = project();
    return `<div class="top"><div><button class="back" onclick="go('projects')">← Tất cả dự án</button><h1>Tư liệu thật</h1>
        <p class="hint">${esc(p.title)}</p></div></div>
        <div class="ai-layout">${workflowNavigation(p, 'archive')}<div>
        <section class="panel"><p>Tìm ảnh và phim từ kho tư liệu, báo chí, bảo tàng và đài truyền hình.</p>
        <label><input type="checkbox" ${archiveIncludeWeb ? 'checked' : ''} onchange="archiveIncludeWeb=this.checked"> Tìm thêm trên web bằng ChatGPT</label>
        <p class="hint">Tìm web dùng tài khoản ChatGPT đã kết nối. Kết quả có tệp trực tiếp sẽ hiện nút Tải vào cảnh. Kiểm tra quyền sử dụng tại trang nguồn trước khi xuất bản.</p>
        <label><input type="checkbox" ${archiveCatalogOnly ? 'checked' : ''} onchange="archiveCatalogOnly=this.checked;render()"> Chỉ hiện mục có hồ sơ lưu trữ và niên đại</label>
        <p class="hint">Bộ lọc dùng hồ sơ của bộ sưu tập. Mở trang nguồn để đối chiếu nội dung với cảnh và xem điều kiện sử dụng.</p>
        <p class="hint">Tư liệu đã tải xuất hiện trong danh sách nguồn hình của cảnh trên timeline. Ảnh được dựng thành đoạn giữ hình. Chỉ video WebM/OGV cần FFmpeg.</p>
        <div class="row"><button class="primary" onclick="finishArchive('tts')">Tiếp tục làm giọng đọc</button>
        <button onclick="finishArchive('production')">Mở timeline</button></div></section>
        ${p.scenes.length ? p.scenes.map((s, i) => archiveSceneView(p, s, i)).join('') : '<p class="note">Duyệt storyboard để có cảnh tìm tư liệu.</p>'}</div></div>`;
}

function archiveAssetKey(item) {
    return (item.url || item.source) + '|' + item.kind;
}

function archiveFileButton(item, assets, sid, index) {
    if (assets.some(asset => archiveAssetKey(asset) === archiveAssetKey(item))) return '<button disabled>Đã tải</button>';
    if (item.busy) return '<button disabled>Đang chuẩn bị…</button>';
    const direct = item.url && (item.web || item.license);
    if (direct || item.web) {
        const button = direct ? `<button class="primary" onclick="archiveRequest('${sid}',null,${index})">Tải vào cảnh</button>` : '';
        const importButton = item.web ? `<button onclick="archiveRequest('${sid}',null,${index},true)">Nhập tệp đã tải</button>` : '';
        const missing = direct ? '' : '<span class="hint">Chưa xác định được tệp tải trực tiếp (trang xem, luồng phát hoặc nguồn chặn tải). Mở trang nguồn để tải thủ công.</span>';
        return missing + button + importButton;
    }
    return `<span class="hint">${item.url ? 'Chưa rõ giấy phép nên không tải tự động.' : 'Bộ sưu tập không cung cấp tệp mở (ví dụ hiện vật chưa thuộc phạm vi công cộng).'} Xem tại trang nguồn.</span>`;
}

function archiveSceneView(p, s, index) {
    const search = archiveResults[p.id + ':' + s.id];
    const assets = s.archiveAssets || [];
    const catalogSources = new Set((search?.items || []).filter(item => !item.web).map(item => item.source));
    const matches = (search?.items || []).map((item, i) => ({item, i}))
        .filter(({item}) => !item.web || !catalogSources.has(item.source))
        .sort((a, b) => Number(!!a.item.web) - Number(!!b.item.web));
    const visible = matches.filter(({item}) => !archiveCatalogOnly || item.catalogued);
    const hidden = matches.length - visible.length;
    return `<details class="panel media-scene" id="archive-scene-${s.id}" ${index === 0 ? 'open' : ''}>
        <summary>Cảnh ${index + 1} · ${esc(s.chapter)} · ${assets.length} tệp đã tải</summary>
        <div class="media-scene-body"><label for="archive-query-${s.id}">Prompt tìm tư liệu</label>
        <textarea id="archive-query-${s.id}" maxlength="300" onchange="referenceScene('${s.id}').archiveQuery=this.value;save()">${esc(s.archiveQuery ?? s.chapter ?? p.title)}</textarea>
        <button onclick="useSceneArchivePrompt('${s.id}')">Dùng prompt hình của cảnh</button>
        <details><summary>Xem prompt hình của cảnh</summary><p style="white-space:pre-wrap">${esc(s.image || '')}</p></details>
        <p class="hint">Dùng tên nhân vật, địa danh, năm hoặc sự kiện trong prompt hình để tìm đúng tư liệu.</p>
        <div class="row"><button ${search?.busy || search?.webBusy ? 'disabled' : ''} onclick="archiveRequest('${s.id}','image')">Tìm ảnh</button>
        <button ${search?.busy || search?.webBusy ? 'disabled' : ''} onclick="archiveRequest('${s.id}','video')">Tìm video</button></div>
        ${search?.busy ? '<p role="status">Đang tìm trong các kho tư liệu…</p>' : ''}
        ${search?.webBusy ? `<p role="status">Đang tìm thêm nguồn trên web… <button class="danger" data-id="${esc(search.requestId)}" onclick="send('archiveWebCancel',{requestId:this.dataset.id})">Dừng tìm web</button></p>` : ''}
        ${search?.error ? `<p class="note">${esc(search.error)}</p>` : ''}
        ${search && !search.busy && !search.webBusy && !search.error && !search.items.length ? '<p class="hint">Chưa có kết quả. Thử tên khác của nhân vật, tên di tích hoặc địa danh gắn với sự kiện.</p>' : ''}
        ${(search?.warnings || []).map(warning => `<p class="hint">${esc(warning)}</p>`).join('')}
        ${hidden ? `<p class="hint">Đã ẩn ${hidden} mục thiếu hồ sơ lưu trữ và niên đại phù hợp.  <button onclick="archiveCatalogOnly=false;render()">Xem thêm kết quả cần đối chiếu</button></p>` : ''}
        <div class="reference-gallery">${visible.map(({item, i}) => `<article class="reference-image-card">
            ${item.thumbnail ? `<img src="${esc(item.thumbnail)}" alt="" loading="lazy" style="width:100%;max-height:160px;object-fit:contain">` : ''}
            <div class="reference-image-caption"><b>${esc(item.title)}</b>
            <span class="hint">${esc([item.provider, item.recordType, item.recordDate].filter(Boolean).join(" · "))}</span>
            ${item.note ? `<span class="hint">${esc(item.note)}</span>` : ''}
            <span class="hint">${esc(item.license || 'Xem giấy phép trên trang nguồn')} · ${esc(item.artist)}</span>
            <div class="row"><button class="link" data-url="${esc(item.source)}" onclick="send('openLink',{url:this.dataset.url})">Trang nguồn ↗</button>
            ${archiveFileButton(item, assets, s.id, i)}</div>
            </div></article>`).join('')}</div>
        ${assets.map(a => `<div class="row"><b class="grow">${a.kind === 'image' ? 'Ảnh' : 'Video'} · ${esc(a.title)}</b>
            <button class="link" data-url="${esc(a.source)}" onclick="send('openLink',{url:this.dataset.url})">Trang nguồn ↗</button>
            <button data-path="${esc(a.originalPath)}" onclick="send('openAsset',{path:this.dataset.path})">Xem tệp</button>
            <button onclick="insertArchive('${s.id}','${a.id}')">＋ Chèn vào timeline</button></div>`).join('')}
        </div></details>`;
}

function insertArchive(sid, aid) {
    const p = project(), s = p.scenes.find(scene => scene.id === sid);
    const asset = s?.archiveAssets?.find(a => a.id === aid);
    if (!asset) return;
    const entries = timelineEntries(p);
    let after = entries.length;
    entries.forEach((entry, i) => { if (entry.sceneId === sid) after = i + 1; });
    const entry = {id:id(), sceneId:sid, assetId:aid, duration:asset.kind === 'image' ? 5 : Math.min(5, asset.duration), muteNarration:true};
    entries.splice(after, 0, entry);
    timelineSelected = entry.id;
    p.finalApproved = false;
    finishArchive('production');
}

function copyArchiveCredits() {
    const credits = [...new Set(resolvedTimeline(project()).flatMap(e => {
        const a = e.archiveAsset;
        return a ? [[a.title, a.artist, a.license, a.licenseURL, a.source,
            'Điều chỉnh khung hình và thời lượng trong bản dựng.'].filter(Boolean).join(' · ')] : [];
    }))];
    if (!credits.length) return toast('Timeline chưa dùng tư liệu.');
    send('copyPrompt', {text:credits.join('\n\n')});
}
