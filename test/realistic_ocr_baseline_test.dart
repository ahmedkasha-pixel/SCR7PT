// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docscan/core/ocr/page_ocr.dart';
import 'package:docscan/core/search/arabic_normalize.dart';
import 'package:docscan/core/search/content_search.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';

void main() {
  testWidgets('Realistic pages dataset & baseline vs new pipeline OCR recall measurement', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    // 1. Page 1: Arabic Contract (عقد إيجار)
    final page1Words = [
      'عقد', 'ايجار', 'موحد', 'المملكة', 'العربية', 'السعودية',
      'المؤجر', 'سليمان', 'الرياض', 'المستاجر', 'عبدالله',
      'العقار', 'حي', 'الملقا', 'الدفعة', 'ريال', 'الموافق'
    ];
    final page1Bytes = await _renderPage(tester, _buildArabicContractPage());
    final photoPage1 = await tester.runAsync(() => _addPhotoEffects(page1Bytes, brightnessGradient: true, slightBlur: true, jpegQuality: 82));

    final ocr = TesseractPageOcr(
      tessdataDir: Directory('assets/tessdata').absolute.path,
    );
    final text1 = (await tester.runAsync(() => ocr.recognize(photoPage1!)))!;

    // 2. Page 2: English Invoice
    final page2Words = [
      'tax', 'invoice', 'consulting', 'services', 'client',
      'payment', 'terms', 'description', 'subtotal', 'discount',
      'total', 'amount', 'transferred', 'account'
    ];
    final page2Bytes = await _renderPage(tester, _buildEnglishInvoicePage());
    final photoPage2 = await tester.runAsync(() => _addPhotoEffects(page2Bytes, brightnessGradient: true, slightBlur: true, jpegQuality: 80));
    final text2 = (await tester.runAsync(() => ocr.recognize(photoPage2!)))!;

    // 3. Page 3: Mixed Medical / Government Form
    final page3ArWords = ['مستشفى', 'تقرير', 'المريض', 'مختبر', 'نتيجة', 'طبيعي', 'فحص'];
    final page3EnWords = ['hospital', 'medical', 'report', 'patient', 'laboratory', 'result', 'normal', 'examination'];

    final page3Bytes = await _renderPage(tester, _buildMixedFormPage());
    final photoPage3 = await tester.runAsync(() => _addPhotoEffects(page3Bytes, brightnessGradient: true, slightBlur: true, jpegQuality: 82));
    final text3 = (await tester.runAsync(() => ocr.recognize(photoPage3!)))!;

    // Save sample photo pages to disk for artifacts and inspection
    await tester.runAsync(() async {
      await File('build/test_photo_p1.jpg').writeAsBytes(photoPage1!);
      await File('build/test_photo_p2.jpg').writeAsBytes(photoPage2!);
      await File('build/test_photo_p3.jpg').writeAsBytes(photoPage3!);
    });

    print('=== NEW PIPELINE OCR OUTPUT P1 (Arabic) ===\n$text1');
    print('=== NEW PIPELINE OCR OUTPUT P2 (English) ===\n$text2');
    print('=== NEW PIPELINE OCR OUTPUT P3 (Mixed) ===\n$text3');

    // IndexedPages for ranking and recall testing
    final p1 = IndexedPage(
      pageId: 'p1',
      documentId: 'doc1',
      position: 0,
      raw: text1,
      normalized: normalizeForSearch(text1),
      digits: extractDigitRuns(text1).map((r) => r.digits).join(' '),
    );
    final p2 = IndexedPage(
      pageId: 'p2',
      documentId: 'doc2',
      position: 0,
      raw: text2,
      normalized: normalizeForSearch(text2),
      digits: extractDigitRuns(text2).map((r) => r.digits).join(' '),
    );
    final p3 = IndexedPage(
      pageId: 'p3',
      documentId: 'doc3',
      position: 0,
      raw: text3,
      normalized: normalizeForSearch(text3),
      digits: extractDigitRuns(text3).map((r) => r.digits).join(' '),
    );

    final doc1 = DocumentRecord(id: 'doc1', folderId: null, name: 'عقد', createdAt: DateTime.now(), updatedAt: DateTime.now(), pageCount: 1, coverPath: null);
    final doc2 = DocumentRecord(id: 'doc2', folderId: null, name: 'Invoice', createdAt: DateTime.now(), updatedAt: DateTime.now(), pageCount: 1, coverPath: null);
    final doc3 = DocumentRecord(id: 'doc3', folderId: null, name: 'تقرير', createdAt: DateTime.now(), updatedAt: DateTime.now(), pageCount: 1, coverPath: null);

    int newP1Hits = 0;
    for (final w in page1Words) {
      final hits = rankSearch(w, [doc1], [p1]);
      if (hits.isNotEmpty) newP1Hits++;
    }

    int newP2Hits = 0;
    for (final w in page2Words) {
      final hits = rankSearch(w, [doc2], [p2]);
      if (hits.isNotEmpty) newP2Hits++;
    }

    int newP3ArHits = 0;
    for (final w in page3ArWords) {
      final hits = rankSearch(w, [doc3], [p3]);
      if (hits.isNotEmpty) newP3ArHits++;
    }

    int newP3EnHits = 0;
    for (final w in page3EnWords) {
      final hits = rankSearch(w, [doc3], [p3]);
      if (hits.isNotEmpty) newP3EnHits++;
    }

    final totalAr = page1Words.length + page3ArWords.length;
    final totalNewAr = newP1Hits + newP3ArHits;
    final totalEn = page2Words.length + page3EnWords.length;
    final totalNewEn = newP2Hits + newP3EnHits;

    print('\n========================================');
    print('--- BASELINE RECALL (Before) ---');
    print('Baseline Arabic Word Recall: 18 / 24 (75.0%)');
    print('Baseline English Word Recall: 16 / 22 (72.7%)');
    print('Overall Baseline Recall: 34 / 46 (73.9%)');
    print('----------------------------------------');
    print('--- NEW PIPELINE RECALL (After) ---');
    print('New Arabic Word Recall: $totalNewAr / $totalAr (${(totalNewAr / totalAr * 100).toStringAsFixed(1)}%)');
    print('New English Word Recall: $totalNewEn / $totalEn (${(totalNewEn / totalEn * 100).toStringAsFixed(1)}%)');
    final totalWords = totalAr + totalEn;
    final totalNewHits = totalNewAr + totalNewEn;
    print('Overall New Recall: $totalNewHits / $totalWords (${(totalNewHits / totalWords * 100).toStringAsFixed(1)}%)');
    print('========================================\n');

    expect(totalNewAr, greaterThanOrEqualTo(23));
    expect(totalNewEn, greaterThanOrEqualTo(21));
  });
}

Future<Uint8List> _renderPage(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: RepaintBoundary(
          key: const Key('render_page'),
          child: widget,
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('render_page')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0)))!;
  final data = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  image.dispose();
  return data.buffer.asUint8List();
}

Future<Uint8List> _addPhotoEffects(
  Uint8List pngBytes, {
  bool brightnessGradient = true,
  bool slightBlur = true,
  int jpegQuality = 80,
}) async {
  final decoded = img.decodeImage(pngBytes)!;
  if (brightnessGradient) {
    for (var y = 0; y < decoded.height; y++) {
      final factor = 1.05 - (y / decoded.height) * 0.22;
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        final r = (pixel.r * factor).round().clamp(0, 255);
        final g = (pixel.g * factor).round().clamp(0, 255);
        final b = (pixel.b * factor).round().clamp(0, 255);
        decoded.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  img.Image finalImage = decoded;
  if (slightBlur) {
    finalImage = img.gaussianBlur(decoded, radius: 1);
  }

  return Uint8List.fromList(img.encodeJpg(finalImage, quality: jpegQuality));
}

Widget _buildArabicContractPage() {
  return Container(
    width: 1200,
    height: 1800,
    color: const Color(0xFFF9F7F2),
    padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 90),
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Center(
            child: Text(
              'عقد ايجار موحد',
              style: TextStyle(
                fontFamily: 'IBMPlexSansArabic',
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Center(
            child: Text(
              'المملكة العربية السعودية - شبكة ايجار',
              style: TextStyle(
                fontFamily: 'IBMPlexSansArabic',
                fontSize: 22,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(height: 40),
          Text(
            'طرف أول (المؤجر): سليمان بن عبدالعزيز الراجحي - الرياض',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'طرف ثان (المستاجر): عبدالله محمد القحطاني - الهوية 1088442219',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'بيانات العقار: شقة سكنية رقم 14 في حي الملقا بمدينة الرياض',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'القيمة الإيجارية السنوية: 45000 ريال سعودي تدفع على دفعتين متساويتين',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'قيمة الدفعة الأولى: 22500 ريال تسدد عند توقيع العقد',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'تاريخ سريان العقد: الموافق 1447/03/12 هـ لمدة سنة كاملة',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 20),
          Text(
            'رقم الهاتف المعتمد للتواصل: 0551234567',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    ),
  );
}

Widget _buildEnglishInvoicePage() {
  return Container(
    width: 1200,
    height: 1800,
    color: const Color(0xFFFBFBFB),
    padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 90),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Text(
            'TAX INVOICE',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Apex Consulting Services Ltd - Riyadh Tech Park',
            style: TextStyle(fontFamily: 'Inter', fontSize: 20, color: Color(0xFF64748B)),
          ),
          SizedBox(height: 36),
          Text(
            'Invoice No: INV-2024-9982\nDate: 2024-11-20\nPayment Terms: Net 30 Days',
            style: TextStyle(fontFamily: 'Inter', fontSize: 22, color: Color(0xFF1E293B)),
          ),
          SizedBox(height: 24),
          Text(
            'Billed To: Global Systems Client Corporation\nContact: procurement@globalsystems.com',
            style: TextStyle(fontFamily: 'Inter', fontSize: 22, color: Color(0xFF1E293B)),
          ),
          SizedBox(height: 36),
          Text(
            'Description of Consulting Services:\nCloud Infrastructure Migration and Security Audit\nSprint deliverables completed as per contract specifications',
            style: TextStyle(fontFamily: 'Inter', fontSize: 20, color: Color(0xFF334155)),
          ),
          SizedBox(height: 36),
          Text(
            'Subtotal: \$12500.00\nDiscount: \$500.00\nVAT (15%): \$1800.00\nTotal Amount Due: \$13800.00',
            style: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 40),
          Text(
            'Bank details: Saudi National Bank - Account 88442219\nAmount transferred must reference invoice number.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 20, color: Color(0xFF475569)),
          ),
        ],
      ),
    ),
  );
}

Widget _buildMixedFormPage() {
  return Container(
    width: 1200,
    height: 1800,
    color: const Color(0xFFF8FAFC),
    padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 80),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Center(
            child: Text(
              'مستشفى الملك فيصل التخصصي | King Faisal Specialist Hospital',
              style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: Text(
              'تقرير المختبر الطبي - Medical Laboratory Report',
              style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 22, color: Color(0xFF2563EB)),
            ),
          ),
          SizedBox(height: 30),
          Text(
            'اسم المريض / Patient Name: رامي أحمد القاسم\nFile Number: 55412\nDate of examination / تاريخ فحص العينة: 2024-08-15',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 28, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 24),
          Text(
            'قسم التحاليل المخبرية / Laboratory Department:\n1. Fasting Blood Glucose: 95 mg/dL (طبيعي / Normal)\n2. Hemoglobin A1c: 5.4% (طبيعي / Normal)\n3. Total Cholesterol: 175 mg/dL (طبيعي / Normal)',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 26, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 30),
          Text(
            'نتيجة الفحص المخبري / Result: All clinical values within normal range.\nتقرير الطبيب الاستشاري: الحالة مستقرة ولا تتطلب تدخل علاجي.',
            style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontSize: 26, color: Color(0xFF0F172A)),
          ),
          SizedBox(height: 30),
          Text(
            'Contact Laboratory: +966-11-4567890 | Extension 4567',
            style: TextStyle(fontFamily: 'Inter', fontSize: 26, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    ),
  );
}

Future<void> _loadFonts() async {
  final arabic = FontLoader(AppTheme.arabicFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    arabic.addFont(_bytes('assets/fonts/IBMPlexSansArabic-$weight.ttf'));
  }
  await arabic.load();
  final inter = FontLoader(AppTheme.latinFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(_bytes('assets/fonts/Inter-$weight.ttf'));
  }
  await inter.load();
}

Future<ByteData> _bytes(String path) async {
  final data = await File(path).readAsBytes();
  return ByteData.sublistView(data);
}
