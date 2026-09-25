import 'package:shared_preferences/shared_preferences.dart';

import '../models/records.dart';

class SettingsRepository {
  static const languageKey = 'language_code';
  static const shareFormatKey = 'share_format';
  static const appearanceKey = 'theme_mode';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(languageKey);
    final share = prefs.getString(shareFormatKey);
    final appearance = prefs.getString(appearanceKey);
    return AppSettings(
      languageCode: (language == null || language.isEmpty) ? null : language,
      shareFormat: share == ShareFormat.jpg.name
          ? ShareFormat.jpg
          : ShareFormat.pdf,
      appearance: appearance == AppAppearance.light.name
          ? AppAppearance.light
          : AppAppearance.dark,
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
    await prefs.setString(appearanceKey, settings.appearance.name);
  }
}
