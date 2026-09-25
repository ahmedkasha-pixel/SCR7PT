# SCR7PT

SCR7PT is a Phase 1 document scanner for Android and iOS. Dark Tech is the default theme (a light theme is in Settings). The wordmark stays left-to-right. One Flutter codebase captures pages, straightens them, files them in folders, and shares a PDF or JPEG through the system share sheet. Everything stays on the device. There is no account and no server.

The in-app name lives in `lib/core/app_config.dart` (`AppConfig.appName`). The launcher label is set separately in `android/app/src/main/AndroidManifest.xml` (`android:label`) and `ios/Runner/Info.plist` (`CFBundleDisplayName`).

## What Phase 1 does

- Camera capture with automatic page-edge detection, draggable corners, perspective correction, and four filters: original, grayscale, black & white, and brighten.
- Multi-page documents: add pages, reorder, delete. Import one or more images from the gallery.
- Folders: create, rename, delete. Documents: name (default `yyyy-MM-dd HH-mm`), rename, move, delete, search by name.
- Home shows folders, recent documents, and a scan button. Settings cover language and the default share format (PDF or JPG).
- Share uses the native share sheet (`share_plus`), so the file can go to WhatsApp, Telegram, mail, or any other installed app. PDFs are built on the device.

Arabic is the default language and the layout is right-to-left. English follows the device language, or an explicit choice in Settings.

## Architecture

```
lib/
  app.dart, main.dart          composition root
  app/                         AppScope, LibraryController, SettingsController
  core/                        name, theme, geometry, image processing, PDF
  data/                        sqflite schema, files, repositories
  features/home|folder|scan|document|settings|share
  features/upcoming/           phase 2 and 3 interfaces (not implemented)
  l10n/                        Arabic and English strings
```

`AppScope` is an `InheritedWidget` that hands screens the library, settings, repository, camera factory, gallery picker, and sharer. Screens do not construct plugins themselves, so tests replace the camera, gallery, and share sheet with fakes.

`LibraryController` loads folder and document metadata and filters search in memory after that load. `DocumentRepository` is the only writer of SQLite rows and page files. Page images live under the app documents directory (`docscan/documents/{id}/`). Metadata lives in `docscan.db`.

Scanning runs in `ScanSession`. Heavy work (`preparePage`, `renderRequest`) goes through `compute` so the UI isolate stays responsive. `document_processor.dart` is pure Dart (`package:image`): downscale, Sobel edges, convex hull, corner pick, homography warp, then the filter. The same code runs on Android, iOS, and in unit tests. Stored images are capped at 1800 px on the long edge (`AppConfig.maxImageEdge`). A document holds at most 40 pages.

## Packages and why

| Package | Role | Why this one |
| --- | --- | --- |
| `camera` 0.11 | Live preview and shutter | Official plugin. Android min SDK 24, iOS 13. |
| `image_picker` 1.2 | Gallery import | Official plugin. Uses the Android photo picker and iOS PHPicker, so the app does not request broad photo-library permission on Android 13+. |
| `image` 4.x | Decode, edges, warp, filters, JPEG | Pure Dart. Same results on both platforms and testable without OpenCV native binaries. |
| `sqflite` 2.4 | Metadata | Mature SQLite plugin on Android and iOS. Tests use `sqflite_common_ffi`. |
| `pdf` 3.x | Local PDF | Embeds each page JPEG on A4. No network. |
| `share_plus` 12 | System share sheet | Official share plugin. File sharing is a mobile feature (not supported on Linux desktop). |
| `shared_preferences` | Language and default share format | Small key-value settings. |
| `permission_handler` | Open system settings if camera permission was denied | The camera plugin itself requests the camera permission. See the iOS note below. |
| `path_provider` | App documents directory | Standard location for the database and images. |
| `intl` / `flutter_localizations` | Arabic and English, RTL | Generated from `lib/l10n`. |

Not used, on purpose:

- `cunning_document_scanner` (and similar VisionKit wrappers) replace the whole capture UI. That hides the crop and filter screen this app needs, and the iOS scanner does not expose the same filter controls.
- `opencv_dart` pulls large native libraries and an NDK build. The Dart detector is enough for a bright page on a darker background and stays identical in tests.

Edge detection is a heuristic, not a machine-learning model. A flat or low-contrast frame falls back to a slight inset quad the user can drag.

## Phase 2 and 3 (not built)

Settings lists these as upcoming. The types already exist so a later phase can implement them without moving navigation or storage.

Phase 2 — `lib/features/upcoming/compression_service.dart` and `signature_service.dart`

- Compression levels high / medium / low, showing the resulting file size before the user commits.
- Signatures. The main path is importing a signature photo from the camera or gallery, removing the white/paper background, saving a transparent PNG, and placing it on a page with move and resize. Drawing with a finger is the secondary path. The `signatures` table is created in schema version 1 and is unused.

Phase 3 — `lib/features/upcoming/cloud_storage.dart`

- `CloudStorage` plus `GoogleDriveStorage`, which throws `UnimplementedError`. Google sign-in and Drive upload are not linked. Another provider can implement the same interface later.

## Run on Android

Requirements: Flutter 3.47 or newer (Dart 3.13), Android SDK 36, build-tools 35+, NDK 28.2 (the Flutter default), and a device or emulator on API 24 or higher.

```bash
flutter pub get
flutter run
```

A debug APK:

```bash
flutter build apk --debug
```

The APK is `build/app/outputs/flutter-apk/app-debug.apk`. Install it with `adb install -r` that file. The debug build is signed with the debug keystore.

Camera permission is declared in the manifest. Gallery import uses the system photo picker and does not add `READ_MEDIA_IMAGES`. The manifest also queries `SEND` and `SEND_MULTIPLE` so the share sheet can see installed apps on Android 11+.

## Run on iOS

Requirements: a Mac with Xcode. This project cannot be compiled for iOS on Linux.

```bash
flutter pub get
cd ios && open Runner.xcworkspace   # or: flutter run
```

The iOS project uses Swift Package Manager (no Podfile), which is the Flutter 3.47 default.

Permission strings:

- `ios/Runner/Info.plist` — Arabic fallback for `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.
- `ios/Runner/en.lproj/InfoPlist.strings` — English.
- `ios/Runner/ar.lproj/InfoPlist.strings` — Arabic.
- `CFBundleDevelopmentRegion` is `ar`. `CFBundleLocalizations` is `ar` and `en`.

`permission_handler` on iOS with Swift Package Manager derives its permission macros from Info.plist. On some Flutter 3.44+ toolchains that lookup fails and the macros stay off, so `permission_handler` will not prompt. The camera plugin still requests camera permission on its own. If a build needs the macros forced, set `PERMISSION_CAMERA=1` and `PERMISSION_PHOTOS=1` (see `permission_handler_apple` and `PERMISSION_HANDLER_INFO_PLIST`).

## Tests

```bash
flutter analyze
flutter test
```

Covered: edge detection and filters, perspective crop, PDF generation, folder and document create/rename/move/search/delete, settings persistence, share-file preparation, and home/settings widgets (Arabic RTL, search, language, share format).

Widget tests that touch the disk or SQLite must run that work inside `WidgetTester.runAsync`. The widget binding uses a fake clock, and real file and database futures do not complete outside it.

Screenshots of the main screens (home, folder, camera, crop editor, document, settings), in Arabic:

```bash
flutter test test/screenshot_test.dart
```

PNGs are written to `build/screenshots/`. Those files are gitignored with the rest of `build/`.

## Project layout notes

- Application id: `com.docscan.docscan`.
- Localization: `l10n.yaml`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`. Regenerate with `flutter gen-l10n` (also runs on `flutter pub get` because `generate: true`).
- UI font: IBM Plex Sans Arabic (OFL), in `assets/fonts/`.
- Theme: Material 3, seed color `#0F6A64`, paper background `#F3F0E8`.
