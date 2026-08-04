import 'package:iuse_demo/navigation/app_entry_policy.dart';
import 'package:web/web.dart' as web;

bool shouldStartWithFreshLogin(Uri location) {
  final browserLocation = Uri.tryParse(web.window.location.href);
  return !isAuthenticatedAppEntry(browserLocation ?? location);
}

void markAuthenticatedBrowserEntry() {
  web.window.history.replaceState(null, '', '/#/app');
}

void markLoggedOutBrowserEntry() {
  web.window.history.replaceState(null, '', '/');
}
