# Sử Studio

Sử Studio là app macOS làm video lịch sử. Người dùng nhập kịch bản hoặc storyboard, tạo và duyệt giọng đọc, chuẩn bị ảnh và tư liệu, rồi dựng video trên timeline. App dùng Swift/AppKit và WKWebView, hỗ trợ macOS 13 trở lên trên Intel và Apple Silicon. Giao diện dùng tiếng Việt.

## Tìm đúng chỗ trong code

| Phần | Điểm bắt đầu |
| --- | --- |
| Giao diện và cầu nối JS ↔ Swift | `source/index.html`, `source/ui.js`, `source/Main.swift` |
| Trợ lý, storyboard và nhập Excel | `source/assistant.js`, `source/AssistantPlan.swift`, `source/CodexConnection.swift`, `source/import_storyboard.py` |
| Giọng đọc và hội thoại | `source/tts.js`, `source/dialogue.js`, `source/ElevenLabsTTS.swift`, `source/NarrationPlayer.swift` |
| Ảnh tham chiếu và video PlenX | `source/reference-images.js`, `source/video-references.js`, `source/PlenXProbe.swift`, `source/Timeline.swift` |
| Tìm, tải và nhập tư liệu | `source/archive-media.js`, `source/ArchiveMedia.swift`. Bước `archive_web` nằm trong `AssistantPlan.swift` |
| Timeline, xuất phim và cập nhật | `source/media-studio.js`, `source/Timeline.swift`, `source/AppUpdater.swift`, `source/updater.js` |

## Khi sửa code

- Đọc `README.md` và xem `git status -sb` trước khi bắt đầu. Nếu nhiều agent cùng làm, chia phạm vi theo tính năng hoặc file. Dùng branch/worktree riêng khi cần sửa các phần có thể đụng nhau. Giữ lại thay đổi đang có của người dùng và các agent khác.
- Theo luồng thật từ nút trên UI qua `send(...)`, handler trong `Main.swift` và callback `native…`. Khi đổi payload, kiểm tra cả hai đầu. Với tác vụ bất đồng bộ, giữ đúng ID yêu cầu, dự án và cảnh để kết quả không ghi nhầm khi người dùng chuyển màn hình.
- Giữ tương thích với dữ liệu dự án cũ. Khi thêm trường, xử lý trường hợp dự án đã lưu chưa có trường đó. Ưu tiên dùng lại cách lưu, render và báo lỗi hiện có.
- Với tư liệu, giữ liên kết nguồn, chú thích và giấy phép nếu có. Phân biệt ảnh đại diện, tệp trực tiếp và trang phát. Kiểm tra loại tệp trước khi tải hoặc đưa lên timeline.
- Repo công khai. Giữ API key trong Keychain và thông tin đăng nhập trong cơ chế lưu của Codex. Dùng fixture giả khi thử nghiệm. Tránh đưa dữ liệu dự án, thông tin xác thực, log có bí mật và gói build vào commit.

## Kiểm tra

Chạy lệnh từ gốc repo trên macOS có Apple Command Line Tools. Đóng app trước khi build lại bằng `sh source/build.sh`.

```sh
swift tests/ui-smoke.swift
python3 -B tests/test_excel_import.py
git diff --check
```

Chọn thêm bài kiểm tra theo phần sửa trong `tests/run-*-tests.sh`. Nếu sửa tích hợp dịch vụ, ghi rõ phần nào đã chạy với dữ liệu giả và phần nào đã thử thực tế. Một số luồng tư liệu cần FFmpeg.

## Phát hành

Chỉ tăng phiên bản và chạy phát hành khi công việc bao gồm bản cập nhật. Đồng bộ phiên bản trong `source/Info.plist`, `source/updater.js` và `HUONG-DAN-TEAM-TEST.txt`. Lệnh `sh source/package-dmg.sh` tạo ZIP Universal và DMG. Script `sh source/publish-release.sh` yêu cầu cây làm việc sạch và GitHub CLI đã đăng nhập. Script đóng gói, tạo tag, push và công bố ZIP, DMG cùng `latest.json` cho OTA.
