import 'package:iuse_demo/models/authenticated_user.dart';

/// The signed-in account and its sign-out action, for headers deep in the
/// navigation (such as the assignment workspace) that are not handed them.
class CurrentSession {
  const CurrentSession(this.user, this.onLogout);

  final AuthenticatedUser user;
  final Future<void> Function() onLogout;
}

/// Kept current by the app shell; null while signed out.
CurrentSession? currentSession;
