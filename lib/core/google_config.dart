/// The only place Google OAuth client IDs are read from.
///
/// The Web client ID below is the release default, so a plain build signs in
/// without `--dart-define`. Override it with:
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com`
/// `--dart-define=GOOGLE_IOS_CLIENT_ID=....apps.googleusercontent.com`
///
/// `webClientIdPlaceholder` still wins when it is non-empty.
///
/// The Android OAuth client is not pasted here. Google matches it from the
/// package name `com.docscan.docscan` and the release certificate SHA-1.
/// Until a real Web client ID is present, Drive stays in the "not set up" state.
class GoogleConfig {
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '759737423939-qpjr70baleq7rnksdr4essgkoogbi1ba.apps.googleusercontent.com',
  );

  /// Paste the Web application client ID here.
  /// Example: `1234567890-abcdef.apps.googleusercontent.com`
  static const String webClientIdPlaceholder = '';

  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// Paste the iOS client ID here when you create it.
  /// Example: `1234567890-ios.apps.googleusercontent.com`
  static const String iosClientIdPlaceholder = '';

  static const String driveScope = 'https://www.googleapis.com/auth/drive.file';

  static const String driveFolderName = 'SCR7PT';

  static String get resolvedWebClientId =>
      _pick(webClientIdPlaceholder, webClientId);

  static String get resolvedIosClientId =>
      _pick(iosClientIdPlaceholder, iosClientId);

  static bool get isConfigured {
    final id = resolvedWebClientId;
    return id.endsWith('.apps.googleusercontent.com') && !id.contains('YOUR_');
  }

  static String _pick(String pasted, String fromEnvironment) {
    final local = pasted.trim();
    if (local.isNotEmpty) return local;
    return fromEnvironment.trim();
  }
}
