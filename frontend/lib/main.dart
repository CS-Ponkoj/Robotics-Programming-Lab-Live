import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/navigation/browser_entry_stub.dart'
    if (dart.library.js_interop) 'package:iuse_demo/navigation/browser_entry_web.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/services/assignment_api.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/widgets/feedback_button.dart';

export 'package:iuse_demo/screens/assignment_workspace.dart';
export 'package:iuse_demo/services/assignment_api.dart';
export 'package:iuse_demo/state/app_learning_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await learningProgress.load();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.forceFreshLoginOnStart,
  });

  final bool? forceFreshLoginOnStart;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AuthenticatedUser? _user;
  bool _restoringSession = true;

  // Also covers the sign-out that follows, whose own requests may fail.
  bool _expiryDialogOpen = false;

  @override
  void initState() {
    super.initState();
    AuthApi.sessionExpired.addListener(_onSessionExpired);
    final forceFreshLogin =
        widget.forceFreshLoginOnStart ?? shouldStartWithFreshLogin(Uri.base);
    if (forceFreshLogin) {
      _showFreshLogin();
    } else {
      _restoreSession();
    }
  }

  Future<void> _showFreshLogin() async {
    await AuthApi.clearLocalSession();
    if (mounted) {
      setState(() => _restoringSession = false);
    }
  }

  Future<void> _restoreSession() async {
    final user = await AuthApi.restore();
    if (user != null && !user.isDemo) {
      await learningProgress.loadForUser(
        user.id,
        migrateLegacy: user.loginId == 'student',
      );
      if (!user.isInstructor) {
        await learningProgress.syncFromServer(fetchMyAssignmentProgress);
      }
    }
    if (user != null && !user.isInstructor && !user.isDemo) {
      unawaited(researchTracker.startSafely());
    }
    if (mounted) {
      setState(() {
        _user = user;
        _restoringSession = false;
      });
      // A request rejected while restoring is handled once the app shows.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionExpired());
    }
  }

  Future<void> _logout() async {
    final wasDemo = _user?.isDemo ?? false;
    if (!wasDemo) {
      await researchTracker.stop();
    }
    await AuthApi.logout();
    learningProgress.startEphemeralSession();
    if (mounted) {
      markLoggedOutBrowserEntry();
      setState(() => _user = null);
    }
  }

  @override
  void dispose() {
    AuthApi.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  /// An expired sign-in is explained once, instead of leaving pages open
  /// whose every request fails. Code is already kept on this device and
  /// returns after signing in again.
  Future<void> _onSessionExpired() async {
    final navigatorContext = _navigatorKey.currentContext;
    if (!AuthApi.sessionExpired.value ||
        _user == null ||
        _expiryDialogOpen ||
        navigatorContext == null) {
      return;
    }
    _expiryDialogOpen = true;
    final demo = _user!.isDemo;
    await showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('session-expired-dialog'),
        title: const Text('Please sign in again'),
        content: Text(
          demo
              ? 'The demo session has ended. Start a new demo from the '
                  'sign-in page.'
              : 'Your sign-in has expired, so nothing more can be graded or '
                  'saved until you sign in again. Your latest code is kept on '
                  'this device and returns when you open the assignment again.',
        ),
        actions: [
          FilledButton(
            key: const Key('session-expired-sign-in'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sign in again'),
          ),
        ],
      ),
    );
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    try {
      await _logout();
    } finally {
      _expiryDialogOpen = false;
    }
  }

  Future<void> _onAuthenticated(AuthenticatedUser user) async {
    markAuthenticatedBrowserEntry();
    if (user.isDemo) {
      learningProgress.startEphemeralSession();
    } else {
      await learningProgress.loadForUser(
        user.id,
        migrateLegacy: user.loginId == 'student',
      );
      if (!user.isInstructor) {
        // History follows the student to any browser, device, or address.
        await learningProgress.syncFromServer(fetchMyAssignmentProgress);
        unawaited(researchTracker.startSafely());
      }
    }
    setState(() => _user = user);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robotics Programming Lab',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: _navigatorKey,
      navigatorObservers: [feedbackPages],
      builder: (context, child) => Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          researchTracker.recordUserInteraction();
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => researchTracker.recordUserInteraction(),
          onPointerMove: (_) => researchTracker.recordUserInteraction(),
          onPointerSignal: (_) => researchTracker.recordUserInteraction(),
          child: Stack(
            children: [
              Positioned.fill(child: child ?? const SizedBox.shrink()),
              if (_user != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: SafeArea(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: feedbackFormOpen,
                      builder: (context, open, _) => open
                          ? const SizedBox.shrink()
                          : FeedbackButton(navigatorKey: _navigatorKey),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      home: _restoringSession
          ? const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Connecting to the robotics lab...'),
                    SizedBox(height: 6),
                    Text(
                        'The free demo server may take up to one minute to wake.'),
                  ],
                ),
              ),
            )
          : _user == null
              ? LoginPage(
                  onAuthenticated: _onAuthenticated,
                )
              : AssignmentListPage(
                  user: _user!,
                  onLogout: _logout,
                ),
    );
  }
}
