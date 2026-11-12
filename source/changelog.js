// Release notes shown in Cài đặt → Cập nhật Sử Studio. publish-release.sh reads the entry for the
// version being released (GitHub release notes and latest.json), so keep this a plain JSON array.
// Newest first; the date is filled when the version is released.
const appChangelog=
[
 {"version":"0.14.11","date":"2026-11-12","title":"Sửa lỗi máy ngủ khi tạo video, dựng 3D bằng Blender (thử nghiệm)","items":[
  "Sửa lỗi: máy ngủ hoặc mất mạng khi đang tạo video/ảnh PlenX làm tác vụ bị kẹt và không tạo tiếp được. Giờ app tự kiểm tra lại khi mạng có lại và khi máy thức dậy; nút Tạo tất cả clip còn thiếu tự kiểm tra các tác vụ chưa rõ kết quả.",
  "Bước riêng tuỳ chọn \"Dựng 3D · Blender\", dùng được bất cứ lúc nào, không cần storyboard: render clip 3D bằng Blender cài trên máy, không tốn credit.",
  "Nguồn \"Từ ảnh\" (đẹp nhất): biến ảnh tạo bằng PlenX hoặc ChatGPT thành clip có máy quay chuyển động chiều sâu 2.5D (tự tách chủ thể khỏi nền), phủ khói, sương, bụi, tàn lửa, mưa, chớp nổ; nhiều ảnh nối thành nhiều đoạn. Render nhanh, không tốn credit.",
  "Tạo ảnh PlenX ngay trong clip từ mô tả cảnh (rẻ hơn tạo video), hoặc nhập ảnh tải về từ ChatGPT.",
  "Mỗi dự án có danh sách clip 3D riêng; mỗi clip tự viết mô tả để AI viết script dựng cảnh low-poly, hoặc dùng model 3D (.glb, .blend, .fbx, .obj, .usdz, .stl).",
  "Xem, sửa script và góp ý để AI sửa lại; có thể lấy mô tả từ một cảnh có sẵn nếu muốn.",
  "Script chạy trong môi trường giới hạn: không mạng, không ghi file ra ngoài thư mục tạm; app chặn lệnh nguy hiểm trước khi chạy.",
  "Hiệu ứng điện ảnh: sương mù khí quyển, phát sáng (bloom), nhoè chuyển động, xoá phông, rung máy cầm tay, màu tương phản cao.",
  "AI có bộ dựng sẵn: toà nhà có cửa sổ sáng/tối và đổ nát, người mặc giáp biết chạy, robot khổng lồ, phi thuyền, khói, vụ nổ, tia năng lượng, tia lửa, lá chắn; máy quay nhiều đoạn theo mốc giây trong mô tả.",
  "Xem trước 4 khung hình trong vài giây trước khi render cả clip, kèm ước tính thời gian render.",
  "Bộ dựng cho cảnh lịch sử: người theo trang phục (bộ đội, lính Mỹ, nông dân nón lá, lính cổ…) và tư thế, cây dừa, tre, chuối, rừng nhiệt đới, đồng cỏ rạp theo gió, mô đất, bao cát, trực thăng, đất tung khi trúng đạn, slow motion.",
  "Thư viện miễn phí Poly Haven: bầu trời chụp thật, chất liệu thật (bùn, đất rừng, gạch, gỗ…), dương xỉ, khóm cỏ, đá, thùng quân dụng; tải một lần, dùng cho mọi dự án.",
  "Kho model của bạn: nhập model .glb/.blend (trực thăng, súng, người…), đặt tên và mô tả; AI tự đặt chúng vào cảnh, cho bộ phận như cánh quạt quay.",
  "AI hiểu bối cảnh trước khi dựng: tra cứu web như ChatGPT (sự kiện, thời điểm, loại xe và số hiệu, kiến trúc, trang phục, ánh sáng), bạn xem và sửa; đề xuất model, script và ảnh PlenX đều bám theo.",
  "Tìm model miễn phí trên mạng, không cần tài khoản: khoảng 800.000 model 3D (Sketchfab qua Objaverse), có ảnh xem trước, chỉ hiện model dùng thương mại được; tải thẳng vào kho kèm ghi nguồn tác giả.",
  "Bộ khởi đầu theo chủ đề: Quân sự 1945–1975 (Huey, Chinook, F-4, B-52, MiG-21, M48, T-54, AK-47, M16, M60, B40, bao cát…), Khói lửa đổ nát, Chiến tranh xưa, Thiên nhiên làng quê. AI đề xuất model cần tải theo mô tả từng clip.",
  "Màu phim: 35mm bạc nhiễu hạt, bạc màu chiến tranh, tương phản mạnh. Thời lượng clip tự theo mốc giây trong mô tả.",
  "Chọn máy quay (xoay quanh, tiến vào, lia, nâng máy), ánh sáng, thời lượng, chất lượng nháp hoặc đẹp; render lần lượt nhiều clip.",
  "Clip xong chèn vào cuối timeline, gán cho một cảnh, hoặc lấy lại sau từ ô ＋ trên timeline."
 ]},
 {"version":"0.14.10","date":"2026-11-11","title":"Prompt hình bám thời kỳ của cảnh","items":["Bỏ chỉ dẫn loại trừ yếu tố hiện đại trong prompt mặc định của storyboard và Shorts.","Gửi chủ đề và bối cảnh thời kỳ khi tạo ảnh, ảnh góc máy và video."]},
 {"version":"0.14.9","date":"2026-11-05","title":"Sao lưu, khôi phục dự án và nhật ký thay đổi","items":[
  "Sao lưu toàn bộ dự án hoặc từng dự án ra một file .zip, gồm cả giọng đọc, ảnh và video.",
  "Khôi phục từ file sao lưu: chọn dự án cần lấy lại, giữ cả hai bản hoặc thay thế bản đang có. Dùng được khi chuyển sang máy khác.",
  "Trước khi khôi phục, app tự lưu một bản dữ liệu hiện tại để quay lại nếu cần.",
  "Mục Cập nhật hiện rõ có gì mới trong bản sắp cài và lịch sử thay đổi các bản trước."
 ]},
 {"version":"0.14.8","date":"2026-11-05","title":"Short dọc 9:16","items":[
  "Tạo video mới chọn Video dài (16:9) hoặc Short (dọc 9:16), thời lượng 30–90 giây hoặc 3 phút.",
  "AI viết kịch bản kiểu short: câu hook 3 giây đầu, cảnh 3–8 giây, câu kết gợi tò mò; prompt ảnh và video cho khung dọc.",
  "Xuất MP4 1080×1920 với nền mờ phía sau, cắt giữa hoặc viền đen.",
  "In phụ đề từ lời kể thẳng vào video, chia theo độ dài giọng đọc thực tế.",
  "Cắt short từ video dài: AI chọn đoạn hay nhất hoặc chia series, viết câu hook và câu kết; dùng lại giọng đọc, ảnh và clip sẵn có.",
  "Gõ thẳng vào ô nhập; cửa sổ soạn tiếng Việt riêng thành tuỳ chọn trong Cài đặt."
 ]},
 {"version":"0.14.7","date":"2026-11-05","title":"Làm song song và timeline linh hoạt","items":[
  "Sau khi duyệt storyboard, làm giọng đọc và hình ảnh cùng lúc; tư liệu thật thành bước tuỳ chọn.",
  "Sửa cảnh chỉ bỏ duyệt đúng phần bị ảnh hưởng.",
  "Ô ＋ trên timeline: chèn nhiều video, ảnh hoặc tư liệu có sẵn vào đúng vị trí.",
  "Một cảnh dùng nhiều hình: lời kể chạy liền qua các hình phủ, không phải kéo chậm clip.",
  "Hướng dẫn sử dụng có ảnh minh hoạ."
 ]},
 {"version":"0.14.6","date":"2026-11-05","title":"Tải tư liệu thật và nút bấm rõ hơn","items":[
  "Ảnh tư liệu được dựng thành đoạn giữ hình ngay trên macOS, không cần FFmpeg.",
  "Tải được tư liệu từ nhiều báo, bảo tàng và kho lưu trữ hơn; báo rõ lý do khi không tải được.",
  "Nút bấm phân biệt rõ hành động chính, AI, quay lại và xoá."
 ]}
];
function versionParts(v){return String(v).replace(/^v/,'').split('.').map(Number)}
function versionAtMost(a,b){const x=versionParts(a),y=versionParts(b);for(let i=0;i<3;i++){if((x[i]||0)!==(y[i]||0))return (x[i]||0)<(y[i]||0)}return true}
function changelogFor(v){return appChangelog.find(e=>e.version===v)}
function changelogListView(items){return `<ul class="changelog-items">${(items||[]).map(t=>`<li>${esc(t)}</li>`).join('')}</ul>`}
function changelogHistoryView(current){const past=appChangelog.filter(e=>versionAtMost(e.version,current));return past.map(e=>`<div class="changelog-entry"><h4>${esc(e.version)}${e.title?' · '+esc(e.title):''}${e.date?` <span class="hint">${esc(e.date.split('-').reverse().join('/'))}</span>`:''}</h4>${changelogListView(e.items)}</div>`).join('')}
