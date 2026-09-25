/// Single place for the product name shown inside the app.
///
/// The launcher name is also set in:
/// - android/app/src/main/AndroidManifest.xml (`android:label`)
/// - ios/Runner/Info.plist (`CFBundleDisplayName`)
class AppConfig {
  static const String appName = 'DocScan';

  /// Longest edge kept for stored page images. Enough for a readable page
  /// without holding multi-megapixel photos in memory.
  static const int maxImageEdge = 1800;

  static const int maxPagesPerDocument = 40;

  static const String databaseFileName = 'docscan.db';
}
