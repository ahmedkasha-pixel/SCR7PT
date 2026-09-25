package io.paratoner.flutter_tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;

import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;

import java.io.File;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * TessBaseAPI is not thread-safe. The previous plugin constructed and
 * initialized it on the platform thread, then called setImage/getUTF8Text
 * from an AsyncTask. That combination ANRs while ara+eng loads and can
 * SIGSEGV the process. Every TessBaseAPI call now happens on one background
 * thread, and failures are returned to Dart instead of killing the app.
 */
public class FlutterTesseractOcrPlugin implements FlutterPlugin, MethodCallHandler {
  private static final int DEFAULT_PAGE_SEG_MODE = TessBaseAPI.PageSegMode.PSM_AUTO_OSD;

  private MethodChannel channel;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private TessBaseAPI baseApi;
  private String lastLanguage = "";

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    BinaryMessenger messenger = flutterPluginBinding.getBinaryMessenger();
    channel = new MethodChannel(messenger, "flutter_tesseract_ocr");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    executor.execute(this::recycleApi);
    executor.shutdown();
  }

  @Override
  public void onMethodCall(final MethodCall call, final Result result) {
    switch (call.method) {
      case "extractText":
      case "extractHocr":
        final String tessDataPath = call.argument("tessData");
        final String imagePath = call.argument("imagePath");
        final Map<String, String> args = call.argument("args");
        String language = "eng";
        if (call.argument("language") != null) {
          language = call.argument("language");
        }
        final String lang = language;
        final boolean hocr = call.method.equals("extractHocr");
        executor.execute(() -> recognize(tessDataPath, imagePath, lang, args, hocr, result));
        break;
      default:
        result.notImplemented();
    }
  }

  private void recognize(
      String tessDataPath,
      String imagePath,
      String language,
      Map<String, String> args,
      boolean hocr,
      Result result) {
    try {
      if (tessDataPath == null || imagePath == null) {
        postError(result, "bad_args", "Missing tessdata or image path", null);
        return;
      }
      final File imageFile = new File(imagePath);
      if (!imageFile.exists()) {
        postError(result, "missing_image", imagePath, null);
        return;
      }
      if (baseApi == null || !language.equals(lastLanguage)) {
        recycleApi();
        final TessBaseAPI api = new TessBaseAPI();
        final boolean ready = api.init(tessDataPath, language);
        if (!ready) {
          api.recycle();
          postError(result, "tess_init", "Tesseract init failed for " + language, null);
          return;
        }
        baseApi = api;
        lastLanguage = language;
      }

      int psm = DEFAULT_PAGE_SEG_MODE;
      if (args != null) {
        for (Map.Entry<String, String> entry : args.entrySet()) {
          if (!"psm".equals(entry.getKey())) {
            baseApi.setVariable(entry.getKey(), entry.getValue());
          } else {
            psm = Integer.parseInt(entry.getValue());
          }
        }
      }
      baseApi.setPageSegMode(psm);
      baseApi.setImage(imageFile);
      final String recognized = hocr ? baseApi.getHOCRText(0) : baseApi.getUTF8Text();
      baseApi.stop();
      final String text = recognized == null ? "" : recognized;
      mainHandler.post(() -> result.success(text));
    } catch (Throwable error) {
      recycleApi();
      postError(result, "ocr_failed", String.valueOf(error.getMessage()), null);
    }
  }

  private void recycleApi() {
    if (baseApi == null) return;
    try {
      baseApi.recycle();
    } catch (Throwable ignored) {
      // A failed engine must not block the next page.
    }
    baseApi = null;
    lastLanguage = "";
  }

  private void postError(Result result, String code, String message, Object details) {
    mainHandler.post(() -> result.error(code, message, details));
  }
}
