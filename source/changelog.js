// Release notes shown in Cài đặt → Cập nhật Sử Studio. publish-release.sh reads the entry for the
// version being released (GitHub release notes and latest.json), so keep this a plain JSON array.
// Newest first; the date is filled when the version is released.
const appChangelog=
[
 {"version":"0.14.9","date":"","title":"Sao lưu, khôi phục dự án và nhật ký thay đổi","items":[
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
