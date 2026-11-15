// Credit estimates from the PlenX model catalogue (server pricing per generation or per second),
// shown before batch image/video generation so nobody is surprised by the bill.
function plenxPrice(model, quality, seconds) {
    const server = (model?.servers || []).find(s => s.is_default) || model?.servers?.[0];
    const q = String(quality || '').toLowerCase();
    const prices = (server?.pricing || []).filter(x => String(x.quality || '').toLowerCase() === q);
    // The app never asks PlenX for generated audio, so prefer the silent price.
    const price = prices.find(x => !x.include_audio) || prices[0];
    const cost = Number(price?.credit_cost);
    if (!price || !isFinite(cost)) return null;
    return price.cost_type === 'per_second' ? cost * Math.max(1, Number(seconds) || 0) : cost;
}

function creditText(count, each) {
    if (!count) return '';
    if (each == null) return 'Chưa đọc được giá của model này; xem bảng giá PlenX trước khi chạy.';
    const total = Math.round(count * each * 10) / 10;
    return 'Ước tính khoảng ' + total + ' credit PlenX (' + count + ' × ' + Math.round(each * 10) / 10 + ').';
}

function imageBatchCost(p) {
    const model = (typeof plenxImageModels !== 'undefined' ? plenxImageModels : []).find(m => m.id === p.plenxImageModel);
    const count = missingImages(p).length;
    return {count, each: model ? plenxPrice(model, model.resolutions?.[0], 0) : null, model};
}

function videoBatchCost(p) {
    const v = videoSettings(p), model = videoCatalog(p).find(m => m.id === v.model);
    const count = p.scenes.filter(s => !selectedSceneAsset(s, 'video')).length;
    return {count, each: model ? plenxPrice(model, v.quality, v.duration) : null, model};
}

function imageCostHint(p) {
    const c = imageBatchCost(p);
    return c.count && c.model ? `<p class="hint">${esc(creditText(c.count, c.each))}</p>` : '';
}

function videoCostHint(p) {
    const c = videoBatchCost(p);
    return c.count && c.model ? `<p class="hint">${esc(creditText(c.count, c.each))} Ảnh động dựng trên máy: 0 credit.</p>` : '';
}
