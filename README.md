# Sử Studio

App macOS làm video lịch sử: kịch bản → storyboard → ElevenLabs TTS → duyệt ảnh → video.

Swift/AppKit + WebKit; macOS 13+, Intel và Apple Silicon. Mỗi máy tự đăng nhập Codex và nhập key; dữ liệu lưu cục bộ, key trong Keychain.

## Build

Cần Apple Command Line Tools. Đóng app rồi chạy `sh source/build.sh`.
Build Universal, ZIP OTA và DMG: `sh source/package-dmg.sh`.

## OTA

Kết nối dịch vụ → Cập nhật Sử Studio → Kiểm tra → Tải → Cài và khởi động lại.
Repo công khai: không cần đăng nhập GitHub để cập nhật. Token Keychain chỉ dùng nếu sau này chuyển sang repo riêng tư.
Release ổn định `vX.Y.Z` cần asset `Su-Studio-X.Y.Z-Universal.zip`, có SHA-256 do GitHub cung cấp. App kiểm tra hash, bundle ID, phiên bản và chữ ký trước khi thay app; giữ bản cũ để rollback. Không thay dữ liệu dự án/Keychain.

Phát hành: tăng phiên bản trong `source/Info.plist`, build gói, push commit/tag, upload ZIP và DMG lên GitHub Releases. Bản test ký ad-hoc, chưa notarize.

Phát hành bản mới: commit thay đổi và tăng version, rồi chạy `sh source/publish-release.sh` (cần GitHub CLI đã đăng nhập).
