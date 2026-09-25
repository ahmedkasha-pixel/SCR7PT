import 'package:flutter/material.dart';

import '../data/models/records.dart';
import '../data/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;
  AppSettings settings = const AppSettings();

  Locale? get locale {
    final code = settings.languageCode;
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  ThemeMode get themeMode => settings.appearance == AppAppearance.light
      ? ThemeMode.light
      : ThemeMode.dark;

  Future<void> load() async {
    settings = await _repository.load();
    notifyListeners();
  }

  Future<void> setLanguage(String? code) async {
    settings = settings.copyWith(
      clearLanguage: code == null,
      languageCode: code,
    );
    await _repository.save(settings);
    notifyListeners();
  }

  Future<void> setShareFormat(ShareFormat format) async {
    settings = settings.copyWith(shareFormat: format);
    await _repository.save(settings);
    notifyListeners();
  }

  Future<void> setAppearance(AppAppearance appearance) async {
    settings = settings.copyWith(appearance: appearance);
    await _repository.save(settings);
    notifyListeners();
  }

  Future<void> setPageSizeMode(PageSizeMode mode) async {
    settings = settings.copyWith(pageSizeMode: mode);
    await _repository.save(settings);
    notifyListeners();
  }

  Future<void> setCompression(CompressionLevel level) async {
    settings = settings.copyWith(compression: level);
    await _repository.save(settings);
    notifyListeners();
  }
}
