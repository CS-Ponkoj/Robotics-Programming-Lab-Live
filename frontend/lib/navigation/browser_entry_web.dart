import 'package:iuse_demo/navigation/app_entry_policy.dart';
import 'package:web/web.dart' as web;

bool shouldStartWithFreshLogin(Uri location) {
  return !isAuthenticatedAppEntry(location);
}

void markAuthenticatedBrowserEntry() {
  web.window.history.replaceState(null, '', '/#/app');
}

void markLoggedOutBrowserEntry() {
  web.window.history.replaceState(null, '', '/');
}
