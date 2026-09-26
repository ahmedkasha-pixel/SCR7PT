import '../../core/geometry/quad.dart';

enum PageFilter { autoEnhance, original, grayscale, blackAndWhite, brighten }

enum ShareFormat { pdf, jpg }

/// How a cropped page is sized after perspective correction.
enum PageSizeMode { auto, a4, letter, original }

/// Export compression. Medium is the default.
enum CompressionLevel { high, medium, low }

/// Ink used when a paper signature is turned into a transparent mark.
enum SignatureInk { original, black, blue }

/// Dark is the product default. Light is an explicit settings choice.
enum AppAppearance { dark, light }

class FolderRecord {
  const FolderRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.documentCount,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int documentCount;
}

/// Opens a document on a specific page from a content search hit.
class DocumentOpenRequest {
  const DocumentOpenRequest({required this.document, this.initialPage = 0});

  final DocumentRecord document;
  final int initialPage;
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.folderId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.pageCount,
    required this.coverPath,
  });

  final String id;
  final String? folderId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int pageCount;
  final String? coverPath;
}

class PageRecord {
  const PageRecord({
    required this.id,
    required this.documentId,
    required this.position,
    required this.originalPath,
    required this.processedPath,
    required this.filter,
    required this.corners,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final int position;
  final String originalPath;
  final String processedPath;
  final PageFilter filter;
  final Quad corners;
  final DateTime createdAt;
}

class NewPage {
  const NewPage({
    required this.id,
    required this.originalJpeg,
    required this.processedJpeg,
    required this.filter,
    required this.corners,
  });

  final String id;
  final List<int> originalJpeg;
  final List<int> processedJpeg;
  final PageFilter filter;
  final Quad corners;
}

class AppSettings {
  const AppSettings({
    this.languageCode,
    this.shareFormat = ShareFormat.pdf,
    this.appearance = AppAppearance.dark,
    this.pageSizeMode = PageSizeMode.auto,
    this.compression = CompressionLevel.medium,
    this.driveAutoUpload = false,
    this.driveWifiOnly = false,
    this.autoTorch = true,
  });

  /// `null` follows the device language, falling back to Arabic.
  final String? languageCode;
  final ShareFormat shareFormat;
  final AppAppearance appearance;
  final PageSizeMode pageSizeMode;
  final CompressionLevel compression;
  final bool driveAutoUpload;
  final bool driveWifiOnly;
  final bool autoTorch;

  AppSettings copyWith({
    String? languageCode,
    bool clearLanguage = false,
    ShareFormat? shareFormat,
    AppAppearance? appearance,
    PageSizeMode? pageSizeMode,
    CompressionLevel? compression,
    bool? driveAutoUpload,
    bool? driveWifiOnly,
    bool? autoTorch,
  }) {
    return AppSettings(
      languageCode: clearLanguage ? null : (languageCode ?? this.languageCode),
      shareFormat: shareFormat ?? this.shareFormat,
      appearance: appearance ?? this.appearance,
      pageSizeMode: pageSizeMode ?? this.pageSizeMode,
      compression: compression ?? this.compression,
      driveAutoUpload: driveAutoUpload ?? this.driveAutoUpload,
      driveWifiOnly: driveWifiOnly ?? this.driveWifiOnly,
      autoTorch: autoTorch ?? this.autoTorch,
    );
  }
}

class SignatureRecord {
  const SignatureRecord({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String imagePath;
  final DateTime createdAt;
}

/// A signature placed on a page. Coordinates are fractions of the page.
class SignaturePlacement {
  const SignaturePlacement({
    required this.id,
    required this.pageId,
    required this.signatureId,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final String id;
  final String pageId;
  final String signatureId;
  final double centerX;
  final double centerY;
  final double width;
  final double height;

  /// Radians, clockwise in image space.
  final double rotation;
}
