# PC POS Build and Release Guide

This document is intended for a new developer taking over the PC POS project. It describes the complete production release workflow for generating:

```text
Alliex_Setup_<version>.exe
app-release-<version>.apk
appcast-<version>.xml
production-<version>.zip
```

The current production configuration is:

```text
Website: https://posvms.sharepos.vn/
Display version: 1.3.0
Full version: 1.3.0+26
Build number: 26
Platforms: Windows x64 and Android
```

## 1. Project overview

PC POS is a Flutter application that embeds the production website in a WebView. It supports:

- Windows x64.
- Android.
- Dart code updates through Shorebird.
- Windows update metadata through an appcast XML file and WinSparkle.
- Windows installer packaging through Inno Setup.

Important files:

| File | Purpose |
| --- | --- |
| `lib/main.dart` | Main WebView URL and customer display API URL |
| `lib/services/app_update_service.dart` | Production update-check URL |
| `android/app/src/main/res/xml/network_security_config.xml` | Android network domain configuration |
| `pubspec.yaml` | Application version and build number |
| `shorebird.yaml` | Shorebird application ID and update settings |
| `pc_pos_setup.iss` | Inno Setup configuration |
| `dsa_priv.pem` | Private key used to sign the Windows installer |
| `dsa_pub.pem` | Public key used to verify the installer signature |

## 2. Required tools

Install the following tools on the build computer:

1. Git.
2. Flutter/FVM configured by the project.
3. Android Studio and Android SDK.
4. Visual Studio with **Desktop development with C++**.
5. Shorebird CLI.
6. Inno Setup.
7. OpenSSL.
8. PowerShell.

Example paths on the current build computer:

```text
Flutter: .fvm/flutter_sdk/bin/flutter.bat
Shorebird: C:\Users\<user>\.shorebird\bin\shorebird.ps1
Inno Setup: C:\Program Files\Inno Setup 7\ISCC.exe
OpenSSL: C:\Program Files\Git\usr\bin\openssl.exe
```

Verify the tools:

```powershell
git --version
.\.fvm\flutter_sdk\bin\flutter.bat --version
shorebird --version
Get-Command shorebird
```

Verify Inno Setup:

```powershell
Test-Path 'C:\Program Files\Inno Setup 7\ISCC.exe'
Test-Path 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
```

## 3. Prepare the source

Open PowerShell in the project directory:

```powershell
cd C:\Users\<user>\Documents\pc_pos
```

Inspect the source state:

```powershell
git status --short
git log -1 --oneline
git pull
```

Do not overwrite or delete changes that belong to another developer. Resolve any unexpected working-tree changes before starting a release.

## 4. Verify every production endpoint

Do not check only the main WebView URL. Search the entire source tree before every production release:

```powershell
rg -n -i "dev-posvms|test-posvms|103\.159\.59\.15" . `
  --glob "!build/**" `
  --glob "!Output/**" `
  --glob "!.dart_tool/**" `
  --glob "!.git/**"
```

The command must return no matches.

Verify the production URLs:

```powershell
rg -n "posvms\.sharepos\.vn" lib android `
  --glob "!build/**"
```

At minimum, verify these locations:

```dart
// lib/main.dart
const _customerDisplayDomain = 'https://posvms.sharepos.vn/api';
static const String baseUrl = 'https://posvms.sharepos.vn/';
```

```dart
// lib/services/app_update_service.dart
const _appcastUrl =
    'https://posvms.sharepos.vn/api/version/check-version-xml';
```

```xml
<!-- android/app/src/main/res/xml/network_security_config.xml -->
<domain includeSubdomains="true">posvms.sharepos.vn</domain>
```

## 5. Set the version

The version is declared in `pubspec.yaml`:

```yaml
version: 1.3.0+26
```

- `1.3.0` is the user-facing version.
- `26` is the internal build number.
- `1.3.0+26` is the complete Shorebird release version.

Every new Shorebird release must use a new build number. Never rebuild changed source under an already-published release number.

Update `pc_pos_setup.iss`:

```ini
AppVersion=1.3.0
OutputBaseFilename=Alliex_Setup_1.3.0
```

Verify all version fields:

```powershell
rg -n "^version:|AppVersion|OutputBaseFilename" `
  pubspec.yaml pc_pos_setup.iss
```

## 6. Validate the source

Format Dart files:

```powershell
dart format lib
```

Run the analyzer:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
```

Check Git whitespace errors:

```powershell
git diff --check
```

Do not release when compilation or analyzer errors remain.

## 7. Sign in to Shorebird

```powershell
shorebird login
```

If Shorebird reports expired credentials:

```powershell
shorebird logout
shorebird login
```

Open the newest authentication URL printed by the CLI and authorize the release account. An older callback URL may already be expired.

## 8. Create the Android Shorebird release

Run:

```powershell
shorebird release --platforms=android --artifact=apk
```

This creates the Shorebird release, an Android App Bundle, and a distributable APK.

Expected success output:

```text
Published Release 1.3.0+26!
```

Generated files:

```text
build\app\outputs\bundle\release\app-release.aab
build\app\outputs\flutter-apk\app-release.apk
```

Do not replace this command with `flutter build apk` when the installed application must receive Shorebird patches. The base release must be built by Shorebird.

## 9. Create the Windows Shorebird release

Run:

```powershell
shorebird release --platforms=windows
```

Expected success output:

```text
Published Release 1.3.0+26!
```

The Windows application is generated in:

```text
build\windows\x64\runner\Release\
```

Do not distribute only `pc_pos.exe`. It requires the DLL files and the `data` directory. Package the complete Release directory with Inno Setup.

## 10. Build the Windows installer

Ensure the `Source` path in `pc_pos_setup.iss` points to the current project location:

```ini
Source: "C:\Users\<user>\Documents\pc_pos\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs
```

Compile with Inno Setup 7:

```powershell
& 'C:\Program Files\Inno Setup 7\ISCC.exe' pc_pos_setup.iss
```

Or with Inno Setup 6:

```powershell
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' pc_pos_setup.iss
```

Expected output:

```text
Output\Alliex_Setup_1.3.0.exe
```

Always run Inno Setup after the Windows Shorebird release so the installer contains the newest Shorebird binary.

## 11. Prepare the release directory

```powershell
$releaseDir = 'C:\Users\<user>\Documents\pc_pos\Output\production-1.3.0'
New-Item -ItemType Directory -Path $releaseDir -Force

Copy-Item `
  -LiteralPath 'Output\Alliex_Setup_1.3.0.exe' `
  -Destination "$releaseDir\Alliex_Setup_1.3.0.exe" `
  -Force

Copy-Item `
  -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
  -Destination "$releaseDir\app-release-1.3.0.apk" `
  -Force
```

## 12. Obtain the installer length

The appcast `length` value is the exact EXE size in bytes:

```powershell
$exe = 'Output\production-1.3.0\Alliex_Setup_1.3.0.exe'
(Get-Item -LiteralPath $exe).Length
```

For the current build, the value is:

```text
239027650
```

Recalculate this value whenever the installer is rebuilt.

## 13. Generate and verify the DSA signature

### Security rules

- Never upload `dsa_priv.pem` to the download server.
- Never include the private key in a release ZIP.
- Never share Shorebird credentials.
- Restrict the private key to authorized release developers.

Generate a binary signature file:

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' dgst `
  -sha1 `
  -sign dsa_priv.pem `
  -out Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe
```

Verify it with the public key:

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' dgst `
  -sha1 `
  -verify dsa_pub.pem `
  -signature Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe
```

Required result:

```text
Verified OK
```

Convert the verified signature to Base64:

```powershell
& 'C:\Program Files\Git\usr\bin\openssl.exe' base64 `
  -A `
  -in Output\production-1.3.0\Alliex_Setup_1.3.0.exe.sig
```

Do not pipe binary signature output directly through PowerShell. PowerShell may convert binary bytes into text. Always create the `.sig` file, verify it, and encode that file.

DSA signatures may differ between two signing operations for the same EXE. A signature is valid when it verifies successfully with the correct public key.

## 14. Create the appcast XML

Create `appcast-1.3.0.xml`:

```xml
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>PC POS 1.3.0</title>
      <enclosure url="https://posvms.sharepos.vn/api/version/download/Alliex_Setup_1.3.0.exe" sparkle:version="1.3.0+26" length="239027650" sparkle:dsaSignature="REPLACE_WITH_THE_NEW_BASE64_SIGNATURE" type="application/octet-stream"/>
      <version>1.3.0</version>
      <buildNumber>26</buildNumber>
      <url>https://posvms.sharepos.vn/api/version/download/app-release-1.3.0.apk</url>
    </item>
  </channel>
</rss>
```

Field meanings:

| Field | Meaning |
| --- | --- |
| `title` | User-facing release title |
| `enclosure url` | Windows installer download URL |
| `sparkle:version` | Full version including build number |
| `length` | Exact Windows installer size in bytes |
| `sparkle:dsaSignature` | Verified Base64 DSA signature |
| `version` | User-facing version |
| `buildNumber` | Internal build number |
| `url` | Android APK download URL |

The names in the URLs must exactly match the uploaded filenames.

## 15. Calculate SHA-256 hashes

```powershell
Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\Alliex_Setup_1.3.0.exe

Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\app-release-1.3.0.apk

Get-FileHash -Algorithm SHA256 `
  Output\production-1.3.0\appcast-1.3.0.xml
```

Record the filename, version, byte length, SHA-256, DSA signature, Git commit, build time, and release developer.

## 16. Create the release ZIP

Include only the EXE, APK, and XML:

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

Never include `dsa_priv.pem`, Shorebird credentials, customer logs, or unnecessary source files.

## 17. Upload order

Use this safe order:

1. Upload `Alliex_Setup_<version>.exe`.
2. Upload `app-release-<version>.apk`.
3. Open both download URLs and confirm they return the actual files.
4. Compare the downloaded file size or SHA-256.
5. Publish the appcast XML last.

Production URLs for `1.3.0`:

```text
https://posvms.sharepos.vn/api/version/download/Alliex_Setup_1.3.0.exe
https://posvms.sharepos.vn/api/version/download/app-release-1.3.0.apk
```

Publishing XML before the artifacts are available may offer users an update they cannot download.

## 18. Test the release

Android checklist:

- Install the APK on at least one Android device.
- Confirm the production website opens.
- Sign in and test the main business flows.
- Test receipt printing when a printer is available.
- Close and reopen the application.

Windows checklist:

- Install the Inno EXE on a clean verification computer.
- Confirm the shortcuts and WebView2 runtime work.
- Confirm the production website opens.
- Sign in and test the main business flows.
- Test printing and the customer display where available.
- Confirm the appcast downloads the correct installer.

## 19. Create a Shorebird patch

Android:

```powershell
shorebird patch --platforms=android --release-version=1.3.0+26
```

Windows:

```powershell
shorebird patch --platforms=windows --release-version=1.3.0+26
```

Only patch from the source and configuration used for the original production release.

Do not use a Shorebird patch for native changes such as:

- Android Manifest or Android permissions.
- Gradle or Kotlin configuration.
- Native Android code.
- Windows C++ runner changes.
- Native plugins or DLL files.
- Inno Setup changes.
- Update public-key changes.

Create a new release and rebuild all artifacts when native code changes.

## 20. Common problems

### Shorebird credentials expired

```powershell
shorebird logout
shorebird login
```

### Shorebird warns that `flutter pub get` failed after build

Run:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat pub get
git status --short
```

Do not commit an unintended `pubspec.lock` update.

### Gradle, Android Gradle Plugin, or Kotlin deprecation warning

The artifact may still be valid if the release finishes successfully. Create a separate maintenance task before a future Flutter upgrade turns the warning into an error.

### Inno Setup cannot find Windows files

Check:

```text
build\windows\x64\runner\Release\
```

Then update the absolute `Source` path in `pc_pos_setup.iss` for the current computer.

## 21. Git cleanup and commit

After building:

```powershell
git status --short
git diff
```

Separate intentional changes from generated changes. Do not use `git reset --hard` to clean the project because it can destroy uncommitted work.

After the release has been verified:

```powershell
git add lib android pubspec.yaml pc_pos_setup.iss docs
git commit -m "Release production <version>"
git push
```

## 22. Complete release checklist

- [ ] Production source is current.
- [ ] No unowned changes will be overwritten.
- [ ] The entire repository contains no old non-production endpoint.
- [ ] Main WebView URL is production.
- [ ] Customer display API URL is production.
- [ ] Update-check URL is production.
- [ ] Android network security domain is production.
- [ ] Version and build number are new and correct.
- [ ] Inno version and output filename are correct.
- [ ] Formatting and analysis complete without errors.
- [ ] Shorebird Android release succeeded.
- [ ] APK was generated.
- [ ] Shorebird Windows release succeeded.
- [ ] Inno Setup compile succeeded.
- [ ] EXE length was recalculated.
- [ ] A new DSA signature was created.
- [ ] DSA verification returned `Verified OK`.
- [ ] XML contains the correct URL, version, build number, length, and signature.
- [ ] SHA-256 hashes were calculated.
- [ ] ZIP contains only the required release artifacts.
- [ ] ZIP contains no private key.
- [ ] Android installation was tested.
- [ ] Windows installation was tested.
- [ ] EXE and APK were uploaded before XML was published.
- [ ] The exact release commit was recorded and pushed.

## 23. Release handoff template

```text
Domain:
Display version:
Full version:
Build number:
Git commit:
Release developer:
Build time:

Windows installer filename:
Windows installer byte length:
Windows installer SHA-256:
Windows installer DSA signature:
Windows installer URL:

Android APK filename:
Android APK byte length:
Android APK SHA-256:
Android APK URL:

Appcast XML SHA-256:
ZIP byte length:
ZIP SHA-256:

Shorebird Android release: Success/Failure
Shorebird Windows release: Success/Failure
Android verification: Passed/Failed
Windows verification: Passed/Failed
```

## 24. Quick reference

```text
1. Update the production source.
2. Search the entire repository for old endpoints.
3. Verify all production URLs.
4. Increase the version and build number.
5. Update the Inno version and filename.
6. Format and analyze.
7. Create the Android Shorebird release with APK.
8. Create the Windows Shorebird release.
9. Build the Inno installer from Shorebird Windows output.
10. Copy the APK and EXE into the release directory.
11. Recalculate the EXE length.
12. Generate the binary DSA signature file.
13. Verify the signature with the public key.
14. Convert the signature to Base64.
15. Create the appcast XML.
16. Calculate SHA-256 hashes.
17. Zip the EXE, APK, and XML.
18. Test Android and Windows.
19. Upload EXE and APK first, then publish XML.
20. Commit and push the exact release source.
```
