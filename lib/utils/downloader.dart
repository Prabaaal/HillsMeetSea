import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class FileDownloader {
  /// Simple download via anchor tag.
  static void download(String url, String filename) {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
  }

  /// Blob-based download — works around cross-origin Safari issues.
  /// Falls back to [download] on error.
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
    } catch (_) {
      download(url, filename);
    }
  }

  /// Reads a URL (including blob: URLs produced by the audio recorder on web)
  /// into raw bytes.
  static Future<Uint8List> fetchBytes(String url) async {
    final response = await web.window.fetch(url.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}
