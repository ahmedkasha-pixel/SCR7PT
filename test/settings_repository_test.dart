import 'package:docscan/data/models/records.dart';
import 'package:docscan/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language and share format persist', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository();
    expect((await repository.load()).languageCode, isNull);
    expect((await repository.load()).shareFormat, ShareFormat.pdf);

    await repository.save(
      const AppSettings(languageCode: 'en', shareFormat: ShareFormat.jpg),
    );
    final stored = await repository.load();
    expect(stored.languageCode, 'en');
    expect(stored.shareFormat, ShareFormat.jpg);

    await repository.save(const AppSettings());
    expect((await repository.load()).languageCode, isNull);
  });
}
