import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool saveResearchDownload(Uint8List bytes, String filename, String mimeType) {
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
