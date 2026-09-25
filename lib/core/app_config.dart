/// Single place for the product name shown inside the app.
///
/// The launcher name is also set in:
/// - android/app/src/main/AndroidManifest.xml (`android:label`)
/// - ios/Runner/Info.plist (`CFBundleDisplayName`)
class AppConfig {
  static const String appName = 'SCR7PT';

  /// Safety cap for a still. A 12 MP frame (4000×3000) is kept; only larger
  /// sensors are reduced, and never below a readable page.
  static const int maxImageEdge = 4096;

  /// JPEG quality for the filtered page embedded in PDF and JPG export.
  static const int jpegQuality = 88;

  static const int maxPagesPerDocument = 40;

  static const String databaseFileName = 'docscan.db';
}
