// Visual style presets chosen per project. The app appends the fixed drawing lock to every image and
// video prompt it sends to PlenX, so the AI writes only cast, setting and action for each scene.
//
// The stickman styles adapt the character anchors and negatives of Stickman Video Director
// (https://github.com/kaomei/stickman-video-director), MIT License,
// Copyright (c) 2026 Stickman Video Director contributors. Style 5 (Historical Cartoon) visual concept by
// Lawal Ridwan (@leksautomate).
const visualStylePresets = {
    stick_history: {
        label: 'Người que · Hoạt hình lịch sử',
        hint: 'Đầu tròn trắng có cổ ngắn, mặt biểu cảm, chân tay que đen, bàn tay đen gọn. Trang phục theo thời kỳ, bối cảnh vẽ màu kiểu cel. Hợp nhất với kênh lịch sử.',
        anchor: 'STYLE: stickman animated video, polished 2D cel-shaded historical cartoon, clean thick black outlines, softly shaded period clothing, sunlit full-color painterly landscapes and architecture.\n'
            + 'CHARACTERS: every person is a 2D cartoon stickman with a round white head and a short, sturdy white neck growing naturally from the clothed shoulders; head and neck form one continuous white filled silhouette that enters the garment neckline, with black outlines only along its sides, never a floating head. Balanced adult proportions, about four head-heights tall, head narrower than the clothed shoulders, not chibi. Thin black arms and legs, exactly two of each; every uncovered arm, wrist and shin is one slender solid black stroke.\n'
            + 'FACE: appealing expressive storybook-cartoon face, two solid black vertical oval eyes without iris or pupil, role-specific eyebrows, small nose curve and mouth, subtle cheek shading, no realistic skin. Hair and beards, when present, are a few clearly shaped locks with soft cel shading.\n'
            + 'HANDS: each wrist ends in one compact solid black rounded mitten-shaped palm with a subtle integrated thumb bump, about one fifth of the head diameter, no separate fingers, no white fill or gloves.\n'
            + 'Keep head fill, proportions, outline weight, costume and colors of each character identical in every shot; one current pose per limb.',
        negative: 'no visible text, letters, numbers, subtitles, logos or watermarks, no speech bubbles, no blood or gore, no photorealistic faces, no 3D CGI, no paper texture, no extra limbs, no fused or duplicate heads, no costume changes, no individual fingers, no white hands or gloves, no floating head, no gap between head and neckline',
        brief: 'Hoạt hình người que lịch sử 2D (stickman), khung 16:9. Nhân vật đầu tròn trắng có cổ ngắn, chân tay que đen, mặt biểu cảm hoạt hình; trang phục, kiểu tóc, mũ, đạo cụ và kiến trúc đúng thời kỳ của cảnh. Mỗi nhân vật lặp lại cùng một mô tả đầy đủ (vai trò, trang phục, tóc, phụ kiện nhận diện) ở mọi cảnh có mặt. Bối cảnh vẽ màu kiểu cel, ánh sáng rõ ràng. Prompt ảnh nêu bối cảnh, nhân vật và tư thế, cỡ cảnh, góc máy, bố cục, bảng màu 4–6 màu theo thời kỳ. Prompt video nêu hành động vật lý rõ theo mốc giây (cầm, đưa, chạy, chỉ…), không morph, máy quay lia/đẩy có chủ đích. Không chữ, không bong bóng thoại, không máu me.',
        shortBrief: 'Short hoạt hình người que lịch sử 2D, khung dọc 9:16: nhân vật chính giữa khung, đủ lớn trên điện thoại, chừa khoảng trống phía dưới cho phụ đề. Nhân vật đầu tròn trắng có cổ ngắn, chân tay que đen, mặt biểu cảm; trang phục, đạo cụ và kiến trúc đúng thời kỳ, lặp lại cùng mô tả nhân vật ở mọi cảnh. Prompt video 5–8 giây, một hoặc hai shot, hành động vật lý rõ ngay giây đầu. Không chữ, không bong bóng thoại, không máu me.',
        design: 'Hoạt hình người que lịch sử 2D: đầu tròn trắng nối cổ ngắn, mặt biểu cảm, chân tay que đen, bàn tay đen gọn; trang phục và bối cảnh vẽ màu kiểu cel theo thời kỳ. Không chữ, không watermark.'
    },
    stick_cozy: {
        label: 'Người que · Kể chuyện ấm áp',
        hint: 'Người que đầu và thân trắng, nét mặt đơn giản, đặt trong bối cảnh hoạt hình đủ màu. Mỗi đoạn một địa điểm. Hợp chuyện đời thường, bài học.',
        anchor: 'STYLE: stickman animated video, minimalist 2D cartoon characters inside full-color 2D cartoon environments, gentle atmospheric light, varied cinematic shots.\n'
            + 'CHARACTERS: each person has a white filled circular head, two small dark oval eyes, simple eyebrow strokes and a short curved mouth; the torso is a slim closed tapered shape with solid white fill inside its dark outline. Both arms and both legs are dark single-line strokes with constant medium weight; hands are small dark rounded shapes and feet short dark rounded strokes. Period or role clothing only when the scene needs it. Keep the same head-to-body proportions, white fill and outline weight in every shot. Exactly two arms and two legs; a moving limb replaces its previous pose. Expressions change only the simple facial marks.',
        negative: 'no visible text, letters, numbers, subtitles or watermarks, no speech bubbles, no photorealistic people, no 3D CGI, no extra limbs, no duplicate characters or props',
        brief: 'Hoạt hình người que kể chuyện ấm áp 2D, khung 16:9. Nhân vật đầu tròn trắng, thân trắng thon, chân tay nét đen, mặt đơn giản. Mỗi cảnh một địa điểm dễ nhận ra (chợ, nhà, đồng ruộng, cung điện…) theo thời kỳ của câu chuyện, chuyển cảnh có chủ đích. Prompt ảnh nêu địa điểm, nhân vật và hành động, cỡ cảnh, góc máy, ánh sáng. Prompt video nêu hành động vật lý theo mốc giây, không để nhân vật đứng yên. Không chữ, không bong bóng thoại.',
        shortBrief: 'Short hoạt hình người que kể chuyện ấm áp, khung dọc 9:16, nhân vật giữa khung, chừa khoảng trống phía dưới cho phụ đề. Nhân vật đầu tròn trắng, thân trắng thon, chân tay nét đen. Prompt video 5–8 giây, hành động rõ ngay giây đầu. Không chữ, không bong bóng thoại.',
        design: 'Hoạt hình người que 2D ấm áp: đầu và thân trắng, chân tay nét đen, mặt đơn giản; bối cảnh hoạt hình đủ màu, ánh sáng dịu. Không chữ, không watermark.'
    },
    stick_cave: {
        label: 'Người que · Tiền sử hài hước',
        hint: 'Người que đầu trắng mặt biểu cảm, mặc da thú, bối cảnh hang động và đất đá, ánh lửa ấm. Hợp chuyện thời tiền sử, chuyện ngụ ngôn, châm biếm.',
        anchor: 'STYLE: stickman animated video, hand-drawn 2D cartoon with earthy prehistoric environments, warm fire accents and subtle paper texture.\n'
            + 'CHARACTERS: each person has a white filled round head with an expressive cartoon face, black stick arms and legs, exactly two of each, and simple animal-hide clothing. Keep the same head fill, proportions, line weight and costume of each character in every shot; a moving limb replaces its previous pose.',
        negative: 'no visible text, letters, numbers, subtitles or watermarks, no speech bubbles, no photorealistic people, no 3D CGI, no extra limbs, no modern objects unless the story asks',
        brief: 'Hoạt hình người que thời tiền sử, hài hước đen, khung 16:9. Nhân vật đầu tròn trắng mặt biểu cảm, chân tay que đen, mặc da thú; hang động, đồi đá, lửa trại, bảng màu đất. Kể theo nhịp mở đầu → leo thang → cú twist. Đây là phong cách minh hoạ, không khẳng định chính xác khảo cổ. Prompt video nêu hành động vật lý rõ theo mốc giây. Không chữ, không bong bóng thoại.',
        shortBrief: 'Short hoạt hình người que tiền sử hài hước, khung dọc 9:16, nhân vật giữa khung, chừa khoảng trống phía dưới cho phụ đề. Đầu tròn trắng mặt biểu cảm, chân tay que đen, mặc da thú. Prompt video 5–8 giây, hành động rõ ngay giây đầu, kết bằng cú twist. Không chữ.',
        design: 'Hoạt hình người que tiền sử vẽ tay: đầu trắng mặt biểu cảm, chân tay que đen, áo da thú; hang động, đất đá, ánh lửa ấm. Không chữ, không watermark.'
    },
    stick_dark: {
        label: 'Người que · Tối giản nền đen',
        hint: 'Nét trắng trên nền đen phẳng, người que đầu rỗng, tối đa 3 màu nhấn cho đạo cụ. Hợp video giải thích nhanh, ý tưởng, mô hình tư duy.',
        anchor: 'STYLE: stickman animated video, minimalist two-dimensional white line animation on a flat, uniform, pitch-black canvas, high-contrast accent colors only on props and graphic effects, at most three saturated accent colors.\n'
            + 'CHARACTERS: the same consistent stick figure with a hollow circular head, occasional simple line expressions, no detailed facial features, no hair, no clothing, no filled body, stable proportions, connected line limbs and uniform medium line weight. Exactly two arms and two legs per figure; each limb appears only in its current pose. The figure stays white.',
        negative: 'no visible text, letters, numbers, subtitles or watermarks, no speech bubbles, no gradients, no 3D depth, no photorealism, no extra limbs, no motion-trail duplicate limbs',
        brief: 'Hoạt hình người que tối giản: nét trắng trên nền đen phẳng, khung 16:9, tối đa 3 màu nhấn (gọi bằng tên màu thường) chỉ dùng cho đạo cụ và hiệu ứng. Người que đầu tròn rỗng, không quần áo. Lịch sử thể hiện bằng đạo cụ và biểu tượng (vương miện, gươm, bản đồ, thuyền) chứ không vẽ trang phục chi tiết. Prompt video: hành động vật lý cụ thể theo mốc giây, mỗi 2–3 giây một thay đổi hình. Không chữ, không bong bóng thoại.',
        shortBrief: 'Short người que tối giản nét trắng trên nền đen, khung dọc 9:16, chừa khoảng trống phía dưới cho phụ đề, tối đa 3 màu nhấn cho đạo cụ. Prompt video 5–8 giây, hành động rõ ngay giây đầu. Không chữ.',
        design: 'Người que tối giản nét trắng trên nền đen phẳng, đầu tròn rỗng, không quần áo; tối đa 3 màu nhấn cho đạo cụ. Không chữ, không watermark.'
    },
    stick_light: {
        label: 'Người que · Tối giản nền trắng',
        hint: 'Nét đen trên nền trắng tinh, người que đầu rỗng, tối đa 3 màu nhấn cho đạo cụ. Hợp video giải thích, so sánh, sơ đồ hoá ý tưởng.',
        anchor: 'STYLE: stickman animated video, minimalist two-dimensional black line animation on a flat, uniform, digitally pure-white canvas with no texture, gradient, shadow or 3D depth; accent colors only on props and graphic effects, at most three saturated accent colors.\n'
            + 'CHARACTERS: the same consistent stick figure with a hollow circular head, occasional simple line expressions, no detailed facial features, no hair, no clothing, no filled body, stable proportions, connected line limbs and uniform medium line weight. Exactly two arms and two legs per figure; each limb appears only in its current pose. The figure stays black.',
        negative: 'no visible text, letters, numbers, subtitles or watermarks, no speech bubbles, no gray tint, no paper texture, no gradients, no 3D depth, no photorealism, no extra limbs',
        brief: 'Hoạt hình người que tối giản: nét đen trên nền trắng phẳng, khung 16:9, tối đa 3 màu nhấn (gọi bằng tên màu thường) chỉ cho đạo cụ và hiệu ứng. Người que đầu tròn rỗng, không quần áo. Lịch sử thể hiện bằng đạo cụ và biểu tượng thay cho trang phục chi tiết. Prompt video: hành động vật lý cụ thể theo mốc giây, mỗi 2–3 giây một thay đổi hình. Không chữ, không bong bóng thoại.',
        shortBrief: 'Short người que tối giản nét đen trên nền trắng, khung dọc 9:16, chừa khoảng trống phía dưới cho phụ đề, tối đa 3 màu nhấn cho đạo cụ. Prompt video 5–8 giây, hành động rõ ngay giây đầu. Không chữ.',
        design: 'Người que tối giản nét đen trên nền trắng phẳng, đầu tròn rỗng, không quần áo; tối đa 3 màu nhấn cho đạo cụ. Không chữ, không watermark.'
    }
};
const visualStyleCredit = 'Phong cách người que phỏng theo Stickman Video Director (mã nguồn mở MIT).';

function visualStylePreset(p) {
    return visualStylePresets[p?.visualStyleKey] || null;
}

function visualLookLabel(p) {
    return visualStylePreset(p) ? 'Ảnh hoạt hình người que 2D' : 'Ảnh điện ảnh';
}

// Appended to every PlenX image/video prompt of a stickman project.
function visualStyleLock(p) {
    const s = visualStylePreset(p);
    if (!s) return '';
    return 'PHONG CÁCH HÌNH CỐ ĐỊNH (' + s.label + '). Giữ nguyên nét vẽ này, không đổi sang ảnh chụp, người thật hay 3D:\n' + s.anchor + '\nAVOID: ' + s.negative;
}

// Sent to the AI writer: which style the prompts must follow, without the long lock it never needs to copy.
function visualStyleContext(p) {
    const s = visualStylePreset(p);
    return s ? {key: p.visualStyleKey, name: s.label, description: s.hint} : null;
}

function visualStyleBrief(p, short) {
    const s = visualStylePreset(p);
    return s ? (short ? s.shortBrief : s.brief) : null;
}

function visualStyleOptions(selected) {
    return [['', 'Phim tài liệu điện ảnh (mặc định)'], ...Object.entries(visualStylePresets).map(([k, s]) => [k, s.label])]
        .map(([k, l]) => `<option value="${k}" ${k === (selected || '') ? 'selected' : ''}>${esc(l)}</option>`).join('');
}

function visualStyleHint(key) {
    const s = visualStylePresets[key];
    return s ? s.hint + ' ' + visualStyleCredit : 'Ảnh và video kiểu phim tài liệu, bối cảnh và trang phục theo thời kỳ của cảnh.';
}

// New-project dialog.
function newVisualStyleKey() {
    const v = document.getElementById?.('newVisualStyle')?.value || '';
    return visualStylePresets[v] ? v : '';
}

function updateNewVisualStyleHint() {
    const el = document.getElementById?.('newVisualStyleHint');
    if (el) el.textContent = visualStyleHint(newVisualStyleKey());
}

function applyNewVisualStyle(p, key = newVisualStyleKey()) {
    if (visualStylePresets[key]) p.visualStyleKey = key;
    return p;
}

function setupNewVisualStylePicker() {
    const el = document.getElementById?.('newVisualStyle');
    if (!el) return;
    el.innerHTML = visualStyleOptions('');
    updateNewVisualStyleHint();
}

function setProjectVisualStyle(key) {
    const p = project();
    if (!p) return;
    key = visualStylePresets[key] ? key : '';
    if ((p.visualStyleKey || '') === key) return;
    if (Object.values(guide(p).steps).some(s => s.status === 'running') || designBusy()) {
        render();
        return toast('Đợi AI hoặc PlenX hoàn tất trước khi đổi phong cách hình.');
    }
    const hasMedia = p.scenes.some(s => s.assets?.image?.length || s.assets?.video?.length);
    if (hasMedia && !confirm('Đổi phong cách hình? Ảnh và video đã tạo vẫn được giữ, nhưng cần tạo lại để đúng phong cách mới. Nhân vật chuẩn phải duyệt lại.')) {
        render();
        return;
    }
    const oldBrief = visualPromptBrief(p), oldDesign = p.visualBible ? effectiveVisualStyle(p.visualBible) : null;
    const oldDefaultBrief = visualStyleBrief(p, isShort(p)), oldDefaultDesign = visualStylePreset(p)?.design || defaultVisualStyle;
    const customBrief = p.visualPromptBrief != null && oldBrief !== oldDefaultBrief && ![legacyVisualPromptBrief, legacyShortVisualPromptBrief].includes(p.visualPromptBrief);
    if (key) p.visualStyleKey = key; else delete p.visualStyleKey;
    if (!customBrief || confirm('Thay định hướng prompt ảnh & video bạn đã sửa bằng mẫu của phong cách mới?')) delete p.visualPromptBrief;
    if (p.visualBible) {
        if (oldDesign === oldDefaultDesign) p.visualBible.style = visualStylePreset(p)?.design || defaultVisualStyle;
        p.visualBible.characters.forEach(c => c.approved = false);
        invalidateDesign(p);
    }
    save();
    render();
    toast('Đã chọn phong cách: ' + (visualStylePreset(p)?.label || 'Phim tài liệu điện ảnh') + '. Áp dụng cho các lần AI viết prompt và tạo ảnh/video tiếp theo.');
}

function visualStylePanel(p, busy) {
    const key = p.visualStyleKey || '';
    return `<div class="field"><label for="project-visual-style">Phong cách hình</label><select id="project-visual-style" ${busy ? 'disabled' : ''} onchange="setProjectVisualStyle(this.value)">${visualStyleOptions(key)}</select><p class="hint">${esc(visualStyleHint(key))}${key ? ' App tự thêm mô tả nét vẽ cố định vào mọi prompt ảnh/video gửi PlenX, giữ nhân vật đồng bộ giữa các cảnh.' : ''}</p></div>`;
}

setupNewVisualStylePicker();
