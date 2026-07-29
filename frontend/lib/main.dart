import 'package:flutter/material.dart';
import 'package:iuse_demo/screens/assignment_list.dart';
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robotics Programming Lab',
      theme: buildAppTheme(),
      home: const AssignmentListPage(),
    );
  }
}
