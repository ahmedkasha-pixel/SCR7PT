import 'package:shared_preferences/shared_preferences.dart';

import '../models/records.dart';

class SettingsRepository {
  static const languageKey = 'language_code';
  static const shareFormatKey = 'share_format';
  static const appearanceKey = 'theme_mode';
  static const pageSizeKey = 'page_size_mode';
  static const compressionKey = 'compression_level';
  static const driveAutoUploadKey = 'drive_auto_upload';
  static const driveWifiOnlyKey = 'drive_wifi_only';
  static const autoTorchKey = 'auto_torch';
  static const ocrPipelineVersionKey = 'ocr_pipeline_version';
  static const currentOcrPipelineVersion = 2;

  Future<int> getOcrPipelineVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(ocrPipelineVersionKey) ?? 0;
  }

  Future<void> setOcrPipelineVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ocrPipelineVersionKey, version);
  }

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(languageKey);
    final share = prefs.getString(shareFormatKey);
    final appearance = prefs.getString(appearanceKey);
    final pageSize = prefs.getString(pageSizeKey);
    final compression = prefs.getString(compressionKey);
    return AppSettings(
      languageCode: (language == null || language.isEmpty) ? null : language,
      shareFormat: share == ShareFormat.jpg.name
          ? ShareFormat.jpg
          : ShareFormat.pdf,
      appearance: appearance == AppAppearance.light.name
          ? AppAppearance.light
          : AppAppearance.dark,
      pageSizeMode: PageSizeMode.values.asNameMap()[pageSize] ??
          PageSizeMode.auto,
      compression:
          CompressionLevel.values.asNameMap()[compression] ??
          CompressionLevel.medium,
      driveAutoUpload: prefs.getBool(driveAutoUploadKey) ?? false,
      driveWifiOnly: prefs.getBool(driveWifiOnlyKey) ?? false,
      autoTorch: prefs.getBool(autoTorchKey) ?? true,
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
    await prefs.setString(pageSizeKey, settings.pageSizeMode.name);
    await prefs.setString(compressionKey, settings.compression.name);
    await prefs.setBool(driveAutoUploadKey, settings.driveAutoUpload);
    await prefs.setBool(driveWifiOnlyKey, settings.driveWifiOnly);
    await prefs.setBool(autoTorchKey, settings.autoTorch);
  }
}
