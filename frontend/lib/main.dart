import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/navigation/browser_entry_stub.dart'
    if (dart.library.js_interop) 'package:iuse_demo/navigation/browser_entry_web.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/research_api.dart';
import 'package:iuse_demo/state/app_learning_progress.dart';
import 'package:iuse_demo/theme/app_theme.dart';

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
  AuthenticatedUser? _user;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
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
    }
    if (user != null && !user.isInstructor && !user.isDemo) {
      unawaited(researchTracker.startSafely());
    }
    if (mounted) {
      setState(() {
        _user = user;
        _restoringSession = false;
      });
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
          child: child ?? const SizedBox.shrink(),
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
