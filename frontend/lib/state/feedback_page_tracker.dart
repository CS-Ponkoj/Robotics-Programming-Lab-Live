import 'package:flutter/material.dart';

/// Page label carried in `RouteSettings.arguments`.
///
/// A route *name* would be reported to the browser as the page address, so
/// the label travels as an argument instead.
class FeedbackPage {
  const FeedbackPage(this.label);

  final String label;
}

/// Knows which page the user is looking at, so feedback names the page.
///
/// Pages pushed with `RouteSettings(arguments: FeedbackPage(...))` are
/// tracked automatically. The home screen switches sections in place, so it
/// sets [homeLabel].
class FeedbackPageTracker extends NavigatorObserver {
  final List<Route<dynamic>> _pages = [];
  String homeLabel = 'Home: Assignments';

  String get currentPage {
    for (final route in _pages.reversed) {
      final page = route.settings.arguments;
      if (page is FeedbackPage) {
        return page.label;
      }
    }
    return homeLabel;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.add(route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0 && newRoute is PageRoute) {
      _pages[index] = newRoute;
    } else if (oldRoute != null) {
      _pages.remove(oldRoute);
    }
  }
}

final feedbackPages = FeedbackPageTracker();
