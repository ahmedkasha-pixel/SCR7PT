// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SCR7PT';

  @override
  String get tagline => 'Scan. Organize. Share.';

  @override
  String get homeTitle => 'Documents';

  @override
  String get folders => 'Folders';

  @override
  String get recent => 'Recent';

  @override
  String get searchHint => 'Search documents';

  @override
  String get searchResults => 'Search results';

  @override
  String get noSearchResults => 'No matching documents';

  @override
  String get searchInPages => 'In the pages';

  @override
  String searchPage(int page) {
    return 'Page $page';
  }

  @override
  String get searchIndexing => 'Updating search inside pages';

  @override
  String searchIndexingProgress(int current, int total) {
    return 'Preparing in-document search $current/$total';
  }

  @override
  String get reindexSearch => 'Re-index in-document search';

  @override
  String get reindexSearchSubtitle =>
      'Re-process all documents with improved search accuracy';

  @override
  String get reindexingStarted => 'In-document indexing started';

  @override
  String get emptyHomeTitle => 'No documents yet';

  @override
  String get emptyHomeBody =>
      'Scan a page or import a photo. Files stay on this device.';

  @override
  String get emptyFolderTitle => 'This folder is empty';

  @override
  String get emptyFolderBody =>
      'Scan a document into this folder, or move one here.';

  @override
  String get scan => 'Scan';

  @override
  String get newFolder => 'New folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get create => 'Create';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get move => 'Move';

  @override
  String get share => 'Share';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Try again';

  @override
  String get deleteFolderTitle => 'Delete this folder?';

  @override
  String get deleteFolderBody =>
      'The folder and the documents inside it will be removed from this device.';

  @override
  String get deleteDocumentTitle => 'Delete this document?';

  @override
  String get deleteDocumentBody =>
      'The document and its pages will be removed from this device.';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get renameDocument => 'Rename document';

  @override
  String get documentName => 'Document name';

  @override
  String get nameRequired => 'Enter a name';

  @override
  String get moveDocument => 'Move to a folder';

  @override
  String get noFolder => 'No folder';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'No pages',
    );
    return '$_temp0';
  }

  @override
  String documentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents',
      one: '1 document',
      zero: 'Empty',
    );
    return '$_temp0';
  }

  @override
  String get cameraTitle => 'Scan';

  @override
  String get gallery => 'Gallery';

  @override
  String get flash => 'Flash';

  @override
  String get scanHint => 'Place the page in the frame, then capture.';

  @override
  String get cameraUnavailableTitle => 'Camera unavailable';

  @override
  String get cameraPermissionBody =>
      'SCR7PT needs the camera to scan. You can still import a photo from the gallery.';

  @override
  String get autoMode => 'Auto';

  @override
  String get manualMode => 'Manual';

  @override
  String get theme => 'Appearance';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get openSettings => 'Open settings';

  @override
  String get startingCamera => 'Starting the camera…';

  @override
  String pagePosition(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String get filterAutoEnhance => 'Auto enhance';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBlackAndWhite => 'Black & white';

  @override
  String get filterBrighten => 'Brighten';

  @override
  String get adjustCrop => 'Adjust corners';

  @override
  String get preview => 'Preview';

  @override
  String get addPage => 'Add page';

  @override
  String get deletePage => 'Delete page';

  @override
  String get reorderPages => 'Reorder';

  @override
  String get done => 'Done';

  @override
  String get processing => 'Enhancing the page…';

  @override
  String get resetCorners => 'Reset corners';

  @override
  String get cornersHint => 'Drag the corners onto the edges of the page.';

  @override
  String get saveDocument => 'Save document';

  @override
  String get chooseFolder => 'Folder';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Device language';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get languageEnglish => 'English';

  @override
  String get defaultShareFormat => 'Default share format';

  @override
  String get sharePdf => 'PDF';

  @override
  String get shareJpg => 'JPG images';

  @override
  String get shareAs => 'Share as';

  @override
  String get preparingShare => 'Preparing the file…';

  @override
  String get shareFailed => 'Could not share this document';

  @override
  String get nothingToShare => 'This document has no pages';

  @override
  String get upcoming => 'Coming next';

  @override
  String phaseLabel(int phase) {
    return 'Phase $phase';
  }

  @override
  String get compressionTitle => 'Compression';

  @override
  String get compressionBody =>
      'High, medium, and low quality, with the file size shown before you share.';

  @override
  String get signatureTitle => 'Signatures';

  @override
  String get signatureBody =>
      'Photograph a signature, remove the paper, and place it on a page. You can also draw one.';

  @override
  String get cloudTitle => 'Google Drive';

  @override
  String get cloudBody =>
      'Sign in with Google and save documents to Drive. Other clouds can be added later.';

  @override
  String get storageNote =>
      'Documents are stored only on this device until you share them.';

  @override
  String get storageNoteCloud =>
      'A copy stays on this device, and you can save it to Drive whenever you want.';

  @override
  String get storageNoteCloudAuto =>
      'A copy stays on this device, and new documents upload to Drive automatically.';

  @override
  String get loadError => 'Could not load documents';

  @override
  String get discardScanTitle => 'Discard this scan?';

  @override
  String get discardScanBody => 'The pages you captured will not be saved.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get removeOnlyPageTitle => 'Remove the only page?';

  @override
  String get removeOnlyPageBody =>
      'The scan will be empty and you will return to the camera.';

  @override
  String get importFailed => 'Could not import that image';

  @override
  String get captureFailed => 'Could not capture the photo';

  @override
  String get couldNotSave => 'Could not save the document';

  @override
  String get editPage => 'Edit page';

  @override
  String get comingSoon => 'This arrives in a later phase';

  @override
  String pageLimit(int count) {
    return 'You can add up to $count pages in one document';
  }

  @override
  String get moreActions => 'More';

  @override
  String get pageSize => 'Page size';

  @override
  String get pageSizeAuto => 'Auto';

  @override
  String get pageSizeA4 => 'A4';

  @override
  String get pageSizeLetter => 'Letter';

  @override
  String get pageSizeOriginal => 'Original';

  @override
  String get quality => 'Quality';

  @override
  String get qualityHigh => 'High';

  @override
  String get qualityMedium => 'Medium';

  @override
  String get qualityLow => 'Low';

  @override
  String get originalSize => 'Original';

  @override
  String get signatures => 'Signatures';

  @override
  String get addSignature => 'Add signature';

  @override
  String get fromCamera => 'Camera';

  @override
  String get fromGallery => 'Gallery';

  @override
  String get drawSignature => 'Draw';

  @override
  String get signatureEmptyTitle => 'No signatures yet';

  @override
  String get signatureEmptyBody =>
      'Photograph a signature on paper, or draw one with your finger.';

  @override
  String get cleanliness => 'Cleanliness';

  @override
  String get inkColor => 'Ink';

  @override
  String get inkOriginal => 'Original';

  @override
  String get inkBlack => 'Black';

  @override
  String get inkBlue => 'Dark blue';

  @override
  String get signatureName => 'Signature name';

  @override
  String get deleteSignatureTitle => 'Delete this signature?';

  @override
  String get deleteSignatureBody =>
      'It will also disappear from every page that uses it.';

  @override
  String get placeSignature => 'Place signature';

  @override
  String get confirmPlace => 'Place on page';

  @override
  String get saveCompressedCopy => 'Save a smaller copy';

  @override
  String get compressedCopySaved => 'Saved a smaller copy';

  @override
  String smallerCopyName(String name) {
    return '$name (smaller)';
  }

  @override
  String get cropDone => 'Use this crop';

  @override
  String get removeBackground => 'Remove background';

  @override
  String get driveNotSetUpTitle => 'Google Drive is not set up yet';

  @override
  String get driveNotSetUpBody =>
      'Drive saving is not turned on in this build yet. Your documents stay on this device and can still be shared.';

  @override
  String get driveNotSetUpDebug =>
      'Developer: paste the Web client ID in lib/core/google_config.dart, then rebuild.';

  @override
  String get driveSignIn => 'Sign in with Google';

  @override
  String get driveSignOut => 'Sign out';

  @override
  String get driveSignedOut => 'Sign in to save documents into your Drive.';

  @override
  String get driveSignInFailed => 'Google sign-in did not finish';

  @override
  String get driveSignInDeveloperError =>
      'Sign-in failed with developer error 10 (DEVELOPER_ERROR). The package name or the release SHA-1 does not match the Android OAuth client, or the Web client ID is not a Web application client.';

  @override
  String get driveSignInWrongClient =>
      'Sign-in failed because the client ID is not a Web application client. An Android client ID cannot be used here.';

  @override
  String get driveSignInTestUser =>
      'Sign-in failed because this Google account is not a test user. Add it on the OAuth consent screen (External, Testing), then try again.';

  @override
  String driveSignInFailedDetail(String detail) {
    return 'Google sign-in did not finish. Send this detail:\n$detail';
  }

  @override
  String get driveAutoUpload => 'Auto-upload new documents';

  @override
  String get driveWifiOnly => 'Upload over Wi-Fi only';

  @override
  String get driveFolderHint =>
      'Files are saved in a Drive folder named SCR7PT. App folders become subfolders.';

  @override
  String get driveSave => 'Save to Drive';

  @override
  String get driveStatusNone => 'Not uploaded';

  @override
  String get driveStatusQueued => 'Waiting to upload';

  @override
  String get driveStatusUploading => 'Uploading';

  @override
  String get driveStatusUploaded => 'Uploaded';

  @override
  String get driveStatusFailed => 'Upload failed';

  @override
  String get driveRetry => 'Retry';

  @override
  String get driveQueued => 'Added to the upload queue';

  @override
  String get driveNeedsSignIn => 'Sign in from Settings before saving to Drive';
}
