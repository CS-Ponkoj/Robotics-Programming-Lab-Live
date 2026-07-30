import 'package:flutter/material.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
import 'package:iuse_demo/screens/login_page.dart';
import 'package:iuse_demo/services/auth_api.dart';
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
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AuthenticatedUser? _user;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = await AuthApi.restore();
    if (mounted) {
      setState(() {
        _user = user;
        _restoringSession = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthApi.logout();
    if (mounted) {
      setState(() => _user = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robotics Programming Lab',
      theme: buildAppTheme(),
      home: _restoringSession
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _user == null
              ? LoginPage(
                  onAuthenticated: (user) => setState(() => _user = user),
                )
              : AssignmentListPage(
                  user: _user!,
                  onLogout: _logout,
                ),
    );
  }
}
