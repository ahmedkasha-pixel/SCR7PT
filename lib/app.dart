import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_scope.dart';
import 'app/library_controller.dart';
import 'app/settings_controller.dart';
import 'core/app_config.dart';
import 'core/theme/app_theme.dart';
import 'data/models/records.dart';
import 'data/repositories/document_repository.dart';
import 'features/document/document_screen.dart';
import 'features/folder/folder_screen.dart';
import 'features/home/home_screen.dart';
import 'features/scan/gallery_picker.dart';
import 'features/scan/scan_camera.dart';
import 'features/scan/scan_flow.dart';
import 'features/settings/settings_screen.dart';
import 'features/share/document_sharer.dart';
import 'features/upcoming/upcoming_services.dart';
import 'l10n/app_localizations.dart';

class AppRoute<T> extends MaterialPageRoute<T> {
  AppRoute({required super.builder});

  @override
  Duration get transitionDuration => AppMotion.standard;

  @override
  Duration get reverseTransitionDuration => AppMotion.fast;
}

Route<void> _route(WidgetBuilder builder) => AppRoute<void>(builder: builder);

class DocScanApp extends StatelessWidget {
  const DocScanApp({
    super.key,
    required this.library,
    required this.settings,
    required this.documents,
    required this.sharer,
    required this.gallery,
    required this.createCamera,
    this.upcoming = const UpcomingServices(),
  });

  final LibraryController library;
  final SettingsController settings;
  final DocumentRepository documents;
  final DocumentSharer sharer;
  final GalleryPicker gallery;
  final ScanCamera Function() createCamera;
  final UpcomingServices upcoming;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      library: library,
      settings: settings,
      documents: documents,
      gallery: gallery,
      createCamera: createCamera,
      sharer: sharer,
      upcoming: upcoming,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            locale: settings.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback: (locale, supported) {
              if (locale != null) {
                for (final item in supported) {
                  if (item.languageCode == locale.languageCode) return item;
                }
              }
              return const Locale('ar');
            },
            home: const HomeScreen(),
            onGenerateRoute: (route) {
              switch (route.name) {
                case '/settings':
                  return _route((_) => const SettingsScreen());
                case '/folder':
                  return _route(
                    (_) =>
                        FolderScreen(folder: route.arguments! as FolderRecord),
                  );
                case '/scan':
                  return _route(
                    (_) => ScanFlow(folderId: route.arguments as String?),
                  );
                case '/document':
                  return _route(
                    (_) => DocumentScreen(
                      document: route.arguments! as DocumentRecord,
                    ),
                  );
              }
              return null;
            },
          );
        },
      ),
    );
  }
}
