// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'SCR7PT';

  @override
  String get tagline => 'امسح. رتّب. شارك.';

  @override
  String get homeTitle => 'المستندات';

  @override
  String get folders => 'المجلدات';

  @override
  String get recent => 'الأحدث';

  @override
  String get searchHint => 'ابحث في المستندات';

  @override
  String get searchResults => 'نتائج البحث';

  @override
  String get noSearchResults => 'لا توجد مستندات مطابقة';

  @override
  String get searchInPages => 'داخل الصفحات';

  @override
  String searchPage(int page) {
    return 'صفحة $page';
  }

  @override
  String get searchIndexing => 'يجري تحديث البحث داخل الصفحات';

  @override
  String get emptyHomeTitle => 'لا توجد مستندات بعد';

  @override
  String get emptyHomeBody =>
      'امسح ورقة أو استورد صورة. الملفات تبقى على هذا الجهاز.';

  @override
  String get emptyFolderTitle => 'هذا المجلد فارغ';

  @override
  String get emptyFolderBody =>
      'امسح مستنداً داخل هذا المجلد، أو انقل مستنداً إليه.';

  @override
  String get scan => 'مسح';

  @override
  String get newFolder => 'مجلد جديد';

  @override
  String get folderName => 'اسم المجلد';

  @override
  String get create => 'إنشاء';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get delete => 'حذف';

  @override
  String get move => 'نقل';

  @override
  String get share => 'مشاركة';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get deleteFolderTitle => 'حذف هذا المجلد؟';

  @override
  String get deleteFolderBody =>
      'سيُحذف المجلد والمستندات داخله من هذا الجهاز.';

  @override
  String get deleteDocumentTitle => 'حذف هذا المستند؟';

  @override
  String get deleteDocumentBody => 'سيُحذف المستند وصفحاته من هذا الجهاز.';

  @override
  String get renameFolder => 'إعادة تسمية المجلد';

  @override
  String get renameDocument => 'إعادة تسمية المستند';

  @override
  String get documentName => 'اسم المستند';

  @override
  String get nameRequired => 'أدخل اسماً';

  @override
  String get moveDocument => 'النقل إلى مجلد';

  @override
  String get noFolder => 'بدون مجلد';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صفحة',
      many: '$count صفحة',
      few: '$count صفحات',
      two: 'صفحتان',
      one: 'صفحة واحدة',
      zero: 'لا صفحات',
    );
    return '$_temp0';
  }

  @override
  String documentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مستند',
      many: '$count مستنداً',
      few: '$count مستندات',
      two: 'مستندان',
      one: 'مستند واحد',
      zero: 'فارغ',
    );
    return '$_temp0';
  }

  @override
  String get cameraTitle => 'مسح';

  @override
  String get gallery => 'المعرض';

  @override
  String get flash => 'الفلاش';

  @override
  String get scanHint => 'ضع الورقة داخل الإطار ثم التقط الصورة.';

  @override
  String get cameraUnavailableTitle => 'الكاميرا غير متاحة';

  @override
  String get cameraPermissionBody =>
      'يحتاج SCR7PT إلى الكاميرا للمسح. يمكنك مع ذلك استيراد صورة من المعرض.';

  @override
  String get autoMode => 'تلقائي';

  @override
  String get manualMode => 'يدوي';

  @override
  String get theme => 'المظهر';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get startingCamera => 'جارٍ تشغيل الكاميرا…';

  @override
  String pagePosition(int current, int total) {
    return 'صفحة $current من $total';
  }

  @override
  String get filterAutoEnhance => 'تحسين تلقائي';

  @override
  String get filterOriginal => 'الأصل';

  @override
  String get filterGrayscale => 'رمادي';

  @override
  String get filterBlackAndWhite => 'أبيض وأسود';

  @override
  String get filterBrighten => 'تفتيح';

  @override
  String get adjustCrop => 'تعديل الزوايا';

  @override
  String get preview => 'معاينة';

  @override
  String get addPage => 'إضافة صفحة';

  @override
  String get deletePage => 'حذف الصفحة';

  @override
  String get reorderPages => 'ترتيب';

  @override
  String get done => 'تم';

  @override
  String get processing => 'جارٍ تحسين الصفحة…';

  @override
  String get resetCorners => 'إعادة ضبط الزوايا';

  @override
  String get cornersHint => 'اسحب الزوايا حتى تطابق حواف الورقة.';

  @override
  String get saveDocument => 'حفظ المستند';

  @override
  String get chooseFolder => 'المجلد';

  @override
  String get settings => 'الإعدادات';

  @override
  String get language => 'اللغة';

  @override
  String get languageSystem => 'لغة الجهاز';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'الإنجليزية';

  @override
  String get defaultShareFormat => 'صيغة المشاركة الافتراضية';

  @override
  String get sharePdf => 'PDF';

  @override
  String get shareJpg => 'صور JPG';

  @override
  String get shareAs => 'المشاركة بصيغة';

  @override
  String get preparingShare => 'جارٍ تجهيز الملف…';

  @override
  String get shareFailed => 'تعذرت مشاركة هذا المستند';

  @override
  String get nothingToShare => 'هذا المستند بلا صفحات';

  @override
  String get upcoming => 'القادم';

  @override
  String phaseLabel(int phase) {
    return 'المرحلة $phase';
  }

  @override
  String get compressionTitle => 'ضغط الملفات';

  @override
  String get compressionBody =>
      'جودة عالية ومتوسطة ومنخفضة، مع حجم الملف قبل المشاركة.';

  @override
  String get signatureTitle => 'التوقيعات';

  @override
  String get signatureBody =>
      'صوّر توقيعاً، أزل الورق، وضعه على الصفحة. يمكنك أيضاً رسمه بإصبعك.';

  @override
  String get cloudTitle => 'Google Drive';

  @override
  String get cloudBody =>
      'تسجيل الدخول بحساب Google وحفظ المستندات في Drive. يمكن إضافة سحابات أخرى لاحقاً.';

  @override
  String get storageNote =>
      'تُحفظ المستندات على هذا الجهاز فقط إلى أن تشاركها.';

  @override
  String get storageNoteCloud =>
      'تبقى نسخة على هذا الجهاز، ويمكنك حفظها في Drive متى شئت.';

  @override
  String get storageNoteCloudAuto =>
      'تبقى نسخة على هذا الجهاز، وتُرفع المستندات الجديدة تلقائياً إلى Drive.';

  @override
  String get loadError => 'تعذر تحميل المستندات';

  @override
  String get discardScanTitle => 'تجاهل هذا المسح؟';

  @override
  String get discardScanBody => 'لن تُحفظ الصفحات التي التقطتها.';

  @override
  String get discard => 'تجاهل';

  @override
  String get keepEditing => 'متابعة التحرير';

  @override
  String get removeOnlyPageTitle => 'حذف الصفحة الوحيدة؟';

  @override
  String get removeOnlyPageBody => 'سيصبح المسح فارغاً وستعود إلى الكاميرا.';

  @override
  String get importFailed => 'تعذر استيراد هذه الصورة';

  @override
  String get captureFailed => 'تعذر التقاط الصورة';

  @override
  String get couldNotSave => 'تعذر حفظ المستند';

  @override
  String get editPage => 'تحرير الصفحة';

  @override
  String get comingSoon => 'تصل هذه الميزة في مرحلة لاحقة';

  @override
  String pageLimit(int count) {
    return 'يمكن إضافة $count صفحة كحد أقصى في المستند الواحد';
  }

  @override
  String get moreActions => 'المزيد';

  @override
  String get pageSize => 'حجم الصفحة';

  @override
  String get pageSizeAuto => 'تلقائي';

  @override
  String get pageSizeA4 => 'A4';

  @override
  String get pageSizeLetter => 'Letter';

  @override
  String get pageSizeOriginal => 'الأصلي';

  @override
  String get quality => 'الجودة';

  @override
  String get qualityHigh => 'عالية';

  @override
  String get qualityMedium => 'متوسطة';

  @override
  String get qualityLow => 'منخفضة';

  @override
  String get originalSize => 'الأصلي';

  @override
  String get signatures => 'التوقيعات';

  @override
  String get addSignature => 'إضافة توقيع';

  @override
  String get fromCamera => 'الكاميرا';

  @override
  String get fromGallery => 'المعرض';

  @override
  String get drawSignature => 'رسم';

  @override
  String get signatureEmptyTitle => 'لا توجد توقيعات';

  @override
  String get signatureEmptyBody => 'صوّر توقيعاً على ورقة، أو ارسمه بإصبعك.';

  @override
  String get cleanliness => 'الوضوح';

  @override
  String get inkColor => 'لون الحبر';

  @override
  String get inkOriginal => 'الأصلي';

  @override
  String get inkBlack => 'أسود';

  @override
  String get inkBlue => 'أزرق داكن';

  @override
  String get signatureName => 'اسم التوقيع';

  @override
  String get deleteSignatureTitle => 'حذف هذا التوقيع؟';

  @override
  String get deleteSignatureBody => 'سيختفي أيضاً من كل صفحة يستخدمها.';

  @override
  String get placeSignature => 'وضع التوقيع';

  @override
  String get confirmPlace => 'تثبيت على الصفحة';

  @override
  String get saveCompressedCopy => 'حفظ نسخة أصغر';

  @override
  String get compressedCopySaved => 'حُفظت نسخة أصغر';

  @override
  String smallerCopyName(String name) {
    return '$name (أصغر)';
  }

  @override
  String get cropDone => 'استخدام هذا القص';

  @override
  String get removeBackground => 'إزالة الخلفية';

  @override
  String get driveNotSetUpTitle => 'Google Drive غير مُعد بعد';

  @override
  String get driveNotSetUpBody =>
      'الحفظ في Drive غير مفعّل في هذه النسخة بعد. تبقى مستنداتك على هذا الجهاز ويمكنك مشاركتها كالمعتاد.';

  @override
  String get driveNotSetUpDebug =>
      'للمطوّر: أضف معرّف عميل الويب في lib/core/google_config.dart ثم أعد بناء التطبيق.';

  @override
  String get driveSignIn => 'تسجيل الدخول بحساب Google';

  @override
  String get driveSignOut => 'تسجيل الخروج';

  @override
  String get driveSignedOut => 'سجّل الدخول لحفظ المستندات في Drive.';

  @override
  String get driveSignInFailed => 'لم يكتمل تسجيل الدخول إلى Google';

  @override
  String get driveSignInDeveloperError =>
      'فشل تسجيل الدخول بخطأ المطوّر 10 (DEVELOPER_ERROR). اسم الحزمة أو بصمة SHA-1 لمفتاح الإصدار لا يطابق عميل Android، أو أن معرّف الويب ليس عميل تطبيق ويب.';

  @override
  String get driveSignInWrongClient =>
      'فشل تسجيل الدخول لأن معرّف العميل ليس عميل تطبيق ويب. لا يمكن استخدام معرّف عميل Android هنا.';

  @override
  String get driveSignInTestUser =>
      'فشل تسجيل الدخول لأن حساب Google هذا ليس ضمن مستخدمي الاختبار. أضفه في شاشة موافقة OAuth (External، وضع Testing) ثم أعد المحاولة.';

  @override
  String driveSignInFailedDetail(String detail) {
    return 'لم يكتمل تسجيل الدخول إلى Google. أرسل هذه التفاصيل:\n$detail';
  }

  @override
  String get driveAutoUpload => 'رفع المستندات الجديدة تلقائياً';

  @override
  String get driveWifiOnly => 'الرفع عبر Wi-Fi فقط';

  @override
  String get driveFolderHint =>
      'تُحفظ الملفات في مجلد Drive باسم SCR7PT، وتصبح مجلدات التطبيق مجلدات فرعية.';

  @override
  String get driveSave => 'حفظ في Drive';

  @override
  String get driveStatusNone => 'غير مرفوع';

  @override
  String get driveStatusQueued => 'بانتظار الرفع';

  @override
  String get driveStatusUploading => 'جارٍ الرفع';

  @override
  String get driveStatusUploaded => 'تم الرفع';

  @override
  String get driveStatusFailed => 'فشل الرفع';

  @override
  String get driveRetry => 'إعادة المحاولة';

  @override
  String get driveQueued => 'أُضيف إلى قائمة الرفع';

  @override
  String get driveNeedsSignIn => 'سجّل الدخول من الإعدادات قبل الحفظ في Drive';
}
