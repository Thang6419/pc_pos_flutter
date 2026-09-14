# Hướng dẫn build và phát hành PC POS từ A đến Z

Tài liệu này dành cho developer mới tiếp quản project PC POS. Mục tiêu là hướng dẫn đầy đủ quy trình tạo một bộ phát hành gồm:

```text
Alliex_Setup_<version>.exe
app-release-<version>.apk
appcast-<version>.xml
production-<version>.zip
```

Quy trình áp dụng cho Flutter, Shorebird, Windows, Android và Inno Setup.

## 1. Tổng quan project

Project là ứng dụng Flutter nhúng website vào WebView và hiện hỗ trợ:

- Windows 64-bit.
- Android.
- Cập nhật code bằng Shorebird.
- Cập nhật Windows qua file appcast XML và WinSparkle.
- Đóng gói Windows bằng Inno Setup.

Các file cấu hình quan trọng:

| File | Công dụng |
| --- | --- |
| `lib/main.dart` | Chứa URL website được WebView mở |
| `pubspec.yaml` | Chứa version và build number của ứng dụng |
| `shorebird.yaml` | Chứa Shorebird app ID và cấu hình cập nhật |
| `pc_pos_setup.iss` | Cấu hình bộ cài Windows bằng Inno Setup |
| `dsa_priv.pem` | Private key dùng để ký bộ cài Windows; phải giữ bí mật |
| `dsa_pub.pem` | Public key dùng để kiểm tra chữ ký |

## 2. Cấu hình production

Tài liệu này chỉ áp dụng cho bản production sử dụng domain:

```text
https://posvms.sharepos.vn/
```

Trước khi build, bắt buộc kiểm tra URL trong `lib/main.dart`:

```dart
static const String baseUrl = 'https://posvms.sharepos.vn/';
```

Không phát hành nếu `baseUrl` khác URL production trên.

## 3. Cách đọc version

Version được khai báo trong `pubspec.yaml`:

```yaml
version: 1.3.0+26
```

Trong đó:

- `1.3.0` là version hiển thị cho người dùng.
- `26` là build number nội bộ.
- Chuỗi đầy đủ là `1.3.0+26`.

Mỗi lần tạo release mới:

1. Tăng version theo kế hoạch phát hành.
2. Build number phải lớn hơn build trước.
3. Không tái sử dụng cùng một version/build number cho hai bộ source khác nhau.

Ví dụ:

```text
Bản cũ: 1.2.12+24
Bản mới: 1.3.0+26
```

## 4. Công cụ cần cài

Máy build cần có:

1. Git.
2. Flutter/FVM theo cấu hình project.
3. Android Studio và Android SDK.
4. Visual Studio với workload **Desktop development with C++**.
5. Shorebird CLI.
6. Inno Setup.
7. OpenSSL.
8. PowerShell.

Các đường dẫn đã dùng trên máy build hiện tại:

```text
Flutter qua FVM: .fvm/flutter_sdk/bin/flutter.bat
Shorebird: C:\Users\<user>\.shorebird\bin\shorebird.ps1
Inno Setup: C:\Program Files\Inno Setup 7\ISCC.exe
OpenSSL: C:\Program Files\Git\usr\bin\openssl.exe
```

Đường dẫn trên máy khác có thể khác. Dùng các lệnh sau để kiểm tra:

```powershell
git --version
.\.fvm\flutter_sdk\bin\flutter.bat --version
shorebird --version
Get-Command shorebird
Get-Command openssl -ErrorAction SilentlyContinue
```

Kiểm tra Inno Setup:

```powershell
Test-Path 'C:\Program Files\Inno Setup 7\ISCC.exe'
Test-Path 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
```

## 5. Chuẩn bị source trước khi build

Mở PowerShell tại thư mục project:

```powershell
cd C:\Users\<user>\Documents\pc_pos
```

Kiểm tra trạng thái source và commit hiện tại:

```powershell
git status --short
git log -1 --oneline
```

Tải source mới nhất theo quy trình Git của đội:

```powershell
git pull
```

Không được tự ý xóa hoặc ghi đè thay đổi chưa commit của người khác. Nếu `git status --short` có file lạ, cần xác định chủ sở hữu thay đổi trước khi tiếp tục.

## 6. Chỉnh domain và version

### 6.1. Chỉnh domain

Mở `lib/main.dart`, tìm `baseUrl` và đặt đúng domain production:

```dart
static const String baseUrl = 'https://posvms.sharepos.vn/';
```

### 6.2. Chỉnh version Flutter

Mở `pubspec.yaml`:

```yaml
version: 1.3.0+26
```

### 6.3. Chỉnh Inno Setup

Mở `pc_pos_setup.iss` và sửa:

```ini
AppVersion=1.3.0
OutputBaseFilename=Alliex_Setup_1.3.0
```

Tên installer production sử dụng đúng mẫu `Alliex_Setup_<version>`.

### 6.4. Kiểm tra nhanh cấu hình

```powershell
rg -n "^version:|baseUrl|AppVersion|OutputBaseFilename" pubspec.yaml lib\main.dart pc_pos_setup.iss
```

Với production `1.3.0+26`, kết quả phải thể hiện:

```text
version: 1.3.0+26
https://posvms.sharepos.vn/
AppVersion=1.3.0
OutputBaseFilename=Alliex_Setup_1.3.0
```

## 7. Kiểm tra source trước khi release

Chạy format:

```powershell
dart format lib
```

Chạy analyze:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
```

Kiểm tra lỗi khoảng trắng của Git:

```powershell
git diff --check
```

Không tiếp tục release nếu có lỗi compile hoặc analyzer error. Warning cũ phải được xem xét, không mặc định bỏ qua nếu chưa biết nguyên nhân.

## 8. Đăng nhập Shorebird

Kiểm tra phiên đăng nhập:

```powershell
shorebird login
```

Nếu CLI báo đã đăng nhập nhưng không refresh được credentials:

```powershell
shorebird logout
shorebird login
```

CLI sẽ cung cấp URL đăng nhập. Mở đúng URL mới nhất trong trình duyệt và authorize. URL cũ có thể hết hạn nên không dùng lại callback cũ.

Không chia sẻ file credentials Shorebird hoặc tài khoản phát hành cho người không có trách nhiệm.

## 9. Tạo Shorebird release Android

Để Shorebird tạo cả dữ liệu release và file APK phân phối, chạy:

```powershell
shorebird release --platforms=android --artifact=apk
```

Shorebird sẽ:

1. Build Android App Bundle phục vụ release/patch.
2. Build APK để phân phối trực tiếp.
3. Upload artifact lên Shorebird.
4. Publish release theo version trong `pubspec.yaml`.

Khi thành công sẽ thấy dạng:

```text
Published Release 1.3.0+26!
```

APK được tạo tại:

```text
build\app\outputs\flutter-apk\app-release.apk
```

AAB được tạo tại:

```text
build\app\outputs\bundle\release\app-release.aab
```

Kiểm tra file:

```powershell
Get-Item build\app\outputs\flutter-apk\app-release.apk
Get-Item build\app\outputs\bundle\release\app-release.aab
```

Không chạy `flutter build apk` thay cho `shorebird release` nếu bản đó cần nhận Shorebird patch. Release gốc phải được tạo bằng Shorebird.

## 10. Tạo Shorebird release Windows

Sau khi Android release thành công, chạy:

```powershell
shorebird release --platforms=windows
```

Khi thành công sẽ thấy:

```text
Published Release 1.3.0+26!
```

Thư mục Windows được tạo tại:

```text
build\windows\x64\runner\Release\
```

File chạy chính:

```text
build\windows\x64\runner\Release\pc_pos.exe
```

Không chỉ gửi riêng `pc_pos.exe` cho khách hàng. Ứng dụng còn phụ thuộc DLL, thư mục `data` và runtime. Phải đóng gói toàn bộ thư mục Release bằng Inno Setup.

## 11. Build installer Windows bằng Inno Setup

Kiểm tra `pc_pos_setup.iss` đang đọc đúng thư mục:

```ini
Source: "C:\Users\<user>\Documents\pc_pos\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs
```

Nếu project nằm ở đường dẫn khác, sửa đường dẫn `Source` trước khi compile.

Chạy Inno Setup 7:

```powershell
& 'C:\Program Files\Inno Setup 7\ISCC.exe' pc_pos_setup.iss
```

Nếu dùng Inno Setup 6:

```powershell
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' pc_pos_setup.iss
```

Kết quả production `1.3.0`:

```text
Output\Alliex_Setup_1.3.0.exe
```

Phải chạy Inno sau Shorebird Windows release để installer lấy đúng binary Shorebird mới nhất.

## 12. Tạo thư mục phát hành

Ví dụ cho production `1.3.0`:

```powershell
$releaseDir = 'C:\Users\<user>\Documents\pc_pos\Output\production-1.3.0'
New-Item -ItemType Directory -Path $releaseDir -Force
```

Copy installer:

```powershell
Copy-Item `
  -LiteralPath 'Output\Alliex_Setup_1.3.0.exe' `
  -Destination "$releaseDir\Alliex_Setup_1.3.0.exe" `
  -Force
```

Copy và đổi tên APK:

```powershell
Copy-Item `
  -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
  -Destination "$releaseDir\app-release-1.3.0.apk" `
  -Force
```

Quy ước thư mục đề xuất:

```text
Output/
  production-1.3.0/
    Alliex_Setup_1.3.0.exe
    app-release-1.3.0.apk
    appcast-1.3.0.xml
```

## 13. Lấy `length` của installer

`length` trong XML là kích thước chính xác của EXE theo byte, không phải KB hoặc MB.

```powershell
$exe = 'Output\production-1.3.0\Alliex_Setup_1.3.0.exe'
(Get-Item -LiteralPath $exe).Length
```

Ví dụ của bản `1.3.0`:

```text
239027650
```

Mỗi lần build lại installer phải lấy lại `length`, kể cả version không đổi.

## 14. Tạo DSA signature cho installer

### 14.1. Lưu ý bảo mật

- `dsa_priv.pem` là private key, tuyệt đối không đưa lên server download.
- Không cho private key vào ZIP phát hành.
- Không commit private key vào repository public.
- Chỉ người phụ trách release được quyền truy cập private key.

### 14.2. Ký file EXE

Chạy OpenSSL bằng đường dẫn thực tế trên máy:

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' dgst `
  -sha1 `
  -sign dsa_priv.pem `
  -out Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe
```

### 14.3. Verify chữ ký

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' dgst `
  -sha1 `
  -verify dsa_pub.pem `
  -signature Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe
```

Kết quả bắt buộc:

```text
Verified OK
```

Nếu không có `Verified OK`, không được phát hành XML hoặc installer.

### 14.4. Chuyển signature sang Base64

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' base64 `
  -A `
  -in Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig
```

Copy toàn bộ chuỗi kết quả vào `sparkle:dsaSignature` của XML.

Không dùng PowerShell pipeline trực tiếp để truyền binary kiểu:

```powershell
openssl dgst ... | openssl base64 ...
```

PowerShell có thể chuyển binary thành text và làm hỏng signature. Cách an toàn là ghi signature ra file `.sig`, verify, rồi Base64 từ chính file đó như hướng dẫn trên.

Chữ ký DSA có thể khác nhau giữa hai lần ký cùng một file. Điều quan trọng là chữ ký được verify bằng đúng public key.

## 15. Tạo file appcast XML

Tên file đề xuất:

```text
appcast-1.3.0.xml
```

Mẫu production:

```xml
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>PC POS 1.3.0</title>
      <enclosure url="https://posvms.sharepos.vn/api/version/download/Alliex_Setup_1.3.0.exe" sparkle:version="1.3.0+26" length="THAY_LENGTH_MOI_VAO_DAY" sparkle:dsaSignature="THAY_CHU_KY_BASE64_MOI_VAO_DAY" type="application/octet-stream"/>
      <version>1.3.0</version>
      <buildNumber>26</buildNumber>
      <url>https://posvms.sharepos.vn/api/version/download/app-release-1.3.0.apk</url>
    </item>
  </channel>
</rss>
```

Ý nghĩa:

| Trường | Giá trị |
| --- | --- |
| `title` | Tên phiên bản hiển thị |
| `enclosure url` | URL tải installer Windows |
| `sparkle:version` | Version đầy đủ, gồm build number |
| `length` | Dung lượng EXE chính xác theo byte |
| `sparkle:dsaSignature` | Chữ ký Base64 vừa tạo |
| `version` | Version hiển thị |
| `buildNumber` | Build number nội bộ |
| `url` | URL tải APK Android |

URL production:

```text
https://posvms.sharepos.vn/api/version/download/...
```

Tên file trong URL phải giống chính xác tên file được upload lên server, kể cả dấu chấm, dấu gạch và chữ hoa/thường.

## 16. Tính SHA-256 cho các artifact

SHA-256 không thay thế DSA signature trong XML, nhưng dùng để kiểm tra file khi bàn giao.

```powershell
Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe

Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\app-release-1.3.0.apk

Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\appcast-1.3.0.xml
```

Lưu lại:

```text
Tên file
Version
Kích thước byte
SHA-256
DSA signature của EXE
Commit Git dùng để build
Thời gian build
Người build
```

## 17. Nén bộ phát hành

Không đưa các file sau vào ZIP gửi server hoặc khách hàng:

- `dsa_priv.pem`.
- Shorebird credentials.
- Source code không cần thiết.
- File log chứa thông tin khách hàng.

Nén đúng ba artifact:

```powershell
$releaseDir = 'C:\Users\<user>\Documents\pc_pos\Output\production-1.3.0'
$zipPath = 'C:\Users\<user>\Documents\pc_pos\Output\production-1.3.0.zip'

$items = @(
  "$releaseDir\Alliex_Setup_1.3.0.exe",
  "$releaseDir\app-release-1.3.0.apk",
  "$releaseDir\appcast-1.3.0.xml"
)

Compress-Archive `
  -LiteralPath $items `
  -DestinationPath $zipPath `
  -CompressionLevel Optimal `
  -Force
```

Kiểm tra ZIP:

```powershell
Get-Item Output\production-1.3.0.zip
Get-FileHash -Algorithm SHA256 Output\production-1.3.0.zip
```

Mở thử ZIP và xác nhận có đủ:

```text
Alliex_Setup_1.3.0.exe
app-release-1.3.0.apk
appcast-1.3.0.xml
```

## 18. Thứ tự upload lên server

Thứ tự an toàn:

1. Upload `Alliex_Setup_<version>.exe`.
2. Upload `app-release-<version>.apk`.
3. Mở trực tiếp URL EXE và APK để kiểm tra tải được.
4. So sánh kích thước hoặc SHA-256 file tải lại.
5. Cuối cùng mới cập nhật file XML trên server.

Ví dụ production:

```text
https://posvms.sharepos.vn/api/version/download/Alliex_Setup_1.3.0.exe
https://posvms.sharepos.vn/api/version/download/app-release-1.3.0.apk
```

Không cập nhật XML trước khi EXE/APK sẵn sàng. Nếu làm ngược, app có thể thông báo update nhưng người dùng không tải được file.

## 19. Kiểm tra bộ phát hành trước khi bàn giao

### Android

- Cài APK trên ít nhất một thiết bị Android.
- Kiểm tra app mở đúng domain.
- Đăng nhập được.
- Thử các chức năng chính.
- Kiểm tra in nếu thiết bị có máy in.
- Đóng và mở lại app.

### Windows

- Cài bằng file Inno EXE trên một máy sạch hoặc máy kiểm thử.
- Kiểm tra shortcut.
- Kiểm tra WebView2.
- Kiểm tra đúng domain.
- Đăng nhập và thử chức năng chính.
- Kiểm tra in và màn hình phụ nếu có.
- Kiểm tra appcast tải đúng installer.

### Artifact

- Tên file đúng version.
- XML đúng domain.
- XML đúng build number.
- `length` bằng chính xác kích thước EXE.
- DSA signature đã `Verified OK`.
- ZIP không chứa private key.
- Shorebird hiển thị release đúng version cho cả Android và Windows.

## 20. Tạo Shorebird patch sau release

Chỉ patch khi thay đổi nằm trong phần Dart mà Shorebird hỗ trợ.

Android:

```powershell
shorebird patch --platforms=android --release-version=1.3.0+26
```

Windows:

```powershell
shorebird patch --platforms=windows --release-version=1.3.0+26
```

Khi thành công, CLI hiển thị:

```text
Published Patch <number>!
```

Phải patch từ đúng source và cấu hình đã dùng để tạo release production gốc.

Không dùng patch cho thay đổi native như:

- Android Manifest hoặc quyền Android.
- Gradle/Kotlin.
- Native Android code.
- C++ runner Windows.
- DLL/plugin native.
- Inno Setup.
- Public key cập nhật.

Các thay đổi native cần tạo release mới và build lại APK/EXE.

## 21. Cảnh báo thường gặp khi chạy Shorebird

### Credentials hết hạn

Thông báo:

```text
Failed to refresh credentials
```

Cách xử lý:

```powershell
shorebird logout
shorebird login
```

### `flutter pub get` failed after build

Shorebird có thể build thành công nhưng cảnh báo không chạy lại được `flutter pub get`. Sau khi release xong, chạy:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat pub get
```

Sau đó kiểm tra `git status --short`. Không commit thay đổi `pubspec.lock` ngoài ý muốn nếu dependency không nằm trong phạm vi release.

### Gradle, Android Gradle Plugin hoặc Kotlin sắp hết hỗ trợ

Nếu chỉ là warning và build hoàn tất thì artifact vẫn được tạo. Tuy nhiên cần tạo task kỹ thuật riêng để nâng version trước khi Flutter mới biến warning thành lỗi.

### MaterialIcons warning

Kiểm tra `uses-material-design` và việc sử dụng `IconData`. Không mặc định bỏ qua nếu giao diện thực tế bị thiếu icon.

### Inno không tìm thấy file Windows

Kiểm tra:

```text
build\windows\x64\runner\Release\
```

Và đường dẫn `Source` trong `pc_pos_setup.iss`. Đường dẫn tuyệt đối của máy cũ sẽ không đúng trên máy developer mới.

## 22. Kiểm tra trạng thái Git sau build

Shorebird hoặc Flutter có thể làm thay đổi file sinh tự động. Chạy:

```powershell
git status --short
git diff
```

Phân biệt:

- Thay đổi chủ động: domain, version, Inno config.
- Thay đổi sinh tự động: `pubspec.lock`, build output, file ephemeral.
- Thay đổi của người khác đã tồn tại trước khi build.

Không dùng `git reset --hard` để dọn source. Lệnh này có thể xóa thay đổi chưa commit.

Sau khi xác nhận release hoạt động, tạo commit rõ ràng, ví dụ:

```powershell
git add lib\main.dart pubspec.yaml pc_pos_setup.iss
git commit -m "Release production 1.3.0"
git push
```

Chỉ push source sau khi đã kiểm tra commit theo quy trình của đội.

## 23. Checklist release đầy đủ

- [ ] Source đã cập nhật mới nhất.
- [ ] Không ghi đè thay đổi chưa commit của người khác.
- [ ] Domain đúng `https://posvms.sharepos.vn/`.
- [ ] Version đúng.
- [ ] Build number lớn hơn bản trước.
- [ ] `pc_pos_setup.iss` đúng version và tên file.
- [ ] Format thành công.
- [ ] Analyze không có error.
- [ ] Shorebird login đúng tài khoản.
- [ ] Shorebird Android release thành công.
- [ ] APK đã được tạo.
- [ ] Shorebird Windows release thành công.
- [ ] Inno Setup compile thành công.
- [ ] Đã lấy lại `length` của EXE.
- [ ] Đã ký DSA lại cho EXE.
- [ ] DSA verify trả về `Verified OK`.
- [ ] XML đúng URL, version, build number, length và signature.
- [ ] Đã tính SHA-256 các file.
- [ ] ZIP có đúng EXE, APK và XML.
- [ ] ZIP không chứa private key.
- [ ] Đã cài thử APK.
- [ ] Đã cài thử installer Windows.
- [ ] Upload EXE/APK thành công trước khi bật XML.
- [ ] Đã lưu lại commit dùng để build.

## 24. Mẫu thông tin bàn giao release

```text
Domain:
Version hiển thị:
Version đầy đủ:
Build number:
Commit:
Người build:
Thời gian build:

Windows installer:
Kích thước byte:
SHA-256:
DSA signature:
URL download:

Android APK:
Kích thước byte:
SHA-256:
URL download:

XML:
SHA-256:

ZIP:
Kích thước byte:
SHA-256:

Shorebird Android release: Thành công/Thất bại
Shorebird Windows release: Thành công/Thất bại
Đã kiểm thử Android: Có/Không
Đã kiểm thử Windows: Có/Không
```

## 25. Quy trình ngắn gọn để tra cứu nhanh

```text
1. Cập nhật source production mới nhất.
2. Kiểm tra domain production.
3. Nâng version + build number.
4. Sửa AppVersion và OutputBaseFilename trong Inno.
5. Format + analyze.
6. shorebird release --platforms=android --artifact=apk
7. shorebird release --platforms=windows
8. Build Inno từ output Windows của Shorebird.
9. Copy APK và EXE vào thư mục release.
10. Lấy length của EXE.
11. Ký DSA ra file .sig.
12. Verify bằng public key.
13. Base64 signature.
14. Tạo appcast XML.
15. Tính SHA-256.
16. Nén EXE + APK + XML.
17. Cài thử cả Android và Windows.
18. Upload EXE/APK trước, XML sau.
19. Commit và push theo quy trình Git của đội.
```
