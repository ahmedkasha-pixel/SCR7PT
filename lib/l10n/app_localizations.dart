import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DocScan'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get homeTitle;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchHint;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResults;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No documents with that name'**
  String get noSearchResults;

  /// No description provided for @emptyHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get emptyHomeTitle;

  /// No description provided for @emptyHomeBody.
  ///
  /// In en, this message translates to:
  /// **'Scan a page or import a photo. Files stay on this device.'**
  String get emptyHomeBody;

  /// No description provided for @emptyFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get emptyFolderTitle;

  /// No description provided for @emptyFolderBody.
  ///
  /// In en, this message translates to:
  /// **'Scan a document into this folder, or move one here.'**
  String get emptyFolderBody;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @deleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this folder?'**
  String get deleteFolderTitle;

  /// No description provided for @deleteFolderBody.
  ///
  /// In en, this message translates to:
  /// **'The folder and the documents inside it will be removed from this device.'**
  String get deleteFolderBody;

  /// No description provided for @deleteDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this document?'**
  String get deleteDocumentTitle;

  /// No description provided for @deleteDocumentBody.
  ///
  /// In en, this message translates to:
  /// **'The document and its pages will be removed from this device.'**
  String get deleteDocumentBody;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolder;

  /// No description provided for @renameDocument.
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get renameDocument;

  /// No description provided for @documentName.
  ///
  /// In en, this message translates to:
  /// **'Document name'**
  String get documentName;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get nameRequired;

  /// No description provided for @moveDocument.
  ///
  /// In en, this message translates to:
  /// **'Move to a folder'**
  String get moveDocument;

  /// No description provided for @noFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get noFolder;

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pages} =1{1 page} other{{count} pages}}'**
  String pagesCount(int count);

  /// No description provided for @documentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Empty} =1{1 document} other{{count} documents}}'**
  String documentsCount(int count);

  /// No description provided for @cameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get cameraTitle;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @flash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get flash;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Place the page in the frame, then capture.'**
  String get scanHint;

  /// No description provided for @cameraUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get cameraUnavailableTitle;

  /// No description provided for @cameraPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'DocScan needs the camera to scan. You can still import a photo from the gallery.'**
  String get cameraPermissionBody;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @startingCamera.
  ///
  /// In en, this message translates to:
  /// **'Starting the camera…'**
  String get startingCamera;

  /// No description provided for @pagePosition.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String pagePosition(int current, int total);

  /// No description provided for @filterOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// No description provided for @filterGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// No description provided for @filterBlackAndWhite.
  ///
  /// In en, this message translates to:
  /// **'Black & white'**
  String get filterBlackAndWhite;

  /// No description provided for @filterBrighten.
  ///
  /// In en, this message translates to:
  /// **'Brighten'**
  String get filterBrighten;

  /// No description provided for @adjustCrop.
  ///
  /// In en, this message translates to:
  /// **'Adjust corners'**
  String get adjustCrop;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @addPage.
  ///
  /// In en, this message translates to:
  /// **'Add page'**
  String get addPage;

  /// No description provided for @deletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get deletePage;

  /// No description provided for @reorderPages.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorderPages;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing the page…'**
  String get processing;

  /// No description provided for @resetCorners.
  ///
  /// In en, this message translates to:
  /// **'Reset corners'**
  String get resetCorners;

  /// No description provided for @cornersHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners onto the edges of the page.'**
  String get cornersHint;

  /// No description provided for @saveDocument.
  ///
  /// In en, this message translates to:
  /// **'Save document'**
  String get saveDocument;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get chooseFolder;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get languageSystem;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @defaultShareFormat.
  ///
  /// In en, this message translates to:
  /// **'Default share format'**
  String get defaultShareFormat;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get sharePdf;

  /// No description provided for @shareJpg.
  ///
  /// In en, this message translates to:
  /// **'JPG images'**
  String get shareJpg;

  /// No description provided for @shareAs.
  ///
  /// In en, this message translates to:
  /// **'Share as'**
  String get shareAs;

  /// No description provided for @preparingShare.
  ///
  /// In en, this message translates to:
  /// **'Preparing the file…'**
  String get preparingShare;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share this document'**
  String get shareFailed;

  /// No description provided for @nothingToShare.
  ///
  /// In en, this message translates to:
  /// **'This document has no pages'**
  String get nothingToShare;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Coming next'**
  String get upcoming;

  /// No description provided for @phaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Phase {phase}'**
  String phaseLabel(int phase);

  /// No description provided for @compressionTitle.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get compressionTitle;

  /// No description provided for @compressionBody.
  ///
  /// In en, this message translates to:
  /// **'High, medium, and low quality, with the file size after compression.'**
  String get compressionBody;

  /// No description provided for @signatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Signatures'**
  String get signatureTitle;

  /// No description provided for @signatureBody.
  ///
  /// In en, this message translates to:
  /// **'Import a signature from the camera or gallery, remove the paper background, and place it on a page. Drawing with a finger is a later option.'**
  String get signatureBody;

  /// No description provided for @cloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Google Drive'**
  String get cloudTitle;

  /// No description provided for @cloudBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google and save documents to Drive. Other clouds can be added later.'**
  String get cloudBody;

  /// No description provided for @storageNote.
  ///
  /// In en, this message translates to:
  /// **'Documents are stored only on this device until you share them.'**
  String get storageNote;

  /// No description provided for @loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load documents'**
  String get loadError;

  /// No description provided for @discardScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this scan?'**
  String get discardScanTitle;

  /// No description provided for @discardScanBody.
  ///
  /// In en, this message translates to:
  /// **'The pages you captured will not be saved.'**
  String get discardScanBody;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @removeOnlyPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the only page?'**
  String get removeOnlyPageTitle;

  /// No description provided for @removeOnlyPageBody.
  ///
  /// In en, this message translates to:
  /// **'The scan will be empty and you will return to the camera.'**
  String get removeOnlyPageBody;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not import that image'**
  String get importFailed;

  /// No description provided for @captureFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not capture the photo'**
  String get captureFailed;

  /// No description provided for @couldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save the document'**
  String get couldNotSave;

  /// No description provided for @editPage.
  ///
  /// In en, this message translates to:
  /// **'Edit page'**
  String get editPage;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'This arrives in a later phase'**
  String get comingSoon;

  /// No description provided for @pageLimit.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {count} pages in one document'**
  String pageLimit(int count);

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
