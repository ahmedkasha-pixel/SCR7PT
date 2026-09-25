import 'package:shared_preferences/shared_preferences.dart';

import '../models/records.dart';

class SettingsRepository {
  static const languageKey = 'language_code';
  static const shareFormatKey = 'share_format';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(languageKey);
    final share = prefs.getString(shareFormatKey);
    return AppSettings(
      languageCode: (language == null || language.isEmpty) ? null : language,
      shareFormat: share == ShareFormat.jpg.name
          ? ShareFormat.jpg
          : ShareFormat.pdf,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (settings.languageCode == null) {
      await prefs.remove(languageKey);
    } else {
      await prefs.setString(languageKey, settings.languageCode!);
    }
    await prefs.setString(shareFormatKey, settings.shareFormat.name);
  }
}
