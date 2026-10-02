import 'package:web/web.dart' as web;

/// Opens an external page in a new tab without giving it access to this one.
bool openExternalLink(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
  return true;
}
