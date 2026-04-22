import 'dart:js_interop';
import 'package:web/web.dart' as web;

class FileDownloader {
  /// Simple download via anchor tag
  static void download(String url, String filename) {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
  }

  /// Blob-based download for cross-origin Safari issues.
  /// Falls back to simple download on error.
  static Future<void> downloadBlob(String url, String filename) async {
    try {
      final response = await web.window.fetch(url.toJS).toDart;
      final blob = await response.blob().toDart;
      final objectUrl = web.URL.createObjectURL(blob);

      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = objectUrl;
      anchor.download = filename;
      anchor.click();

      web.URL.revokeObjectURL(objectUrl);
    } catch (e) {
      // Fallback to simple download
      download(url, filename);
    }
  }
}
