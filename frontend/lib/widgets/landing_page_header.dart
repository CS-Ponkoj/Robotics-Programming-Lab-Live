import 'package:flutter/material.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/my_account_page.dart';
import 'package:iuse_demo/screens/instructor_assignment_admin.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

class LandingPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const LandingPageHeader({
    super.key,
    required this.user,
    required this.onLogout,
    this.onHome,
  });

  final AuthenticatedUser user;
  final Future<void> Function() onLogout;
  final VoidCallback? onHome;

  @override
  Size get preferredSize => const Size.fromHeight(116);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: compact ? 8 : 24,
      leadingWidth: compact ? 40 : null,
      leading: onHome == null ? null : BackButton(onPressed: onHome),
      elevation: 0,
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.brandDark,
              AppColors.brand,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            width: compact ? 36 : 52,
            height: compact ? 36 : 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: const Icon(
              Icons.memory_rounded,
              size: 28,
              semanticLabel: 'Robotics lab',
            ),
          ),
          SizedBox(width: compact ? 8 : 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Robotics Programming Lab',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 16 : null,
                    letterSpacing: -0.3,
                  ),
                ),
                if (!compact) const SizedBox(height: 4),
                if (!compact)
                  Text(
                    user.isDemo
                        ? 'Demo mode: all work resets when you refresh'
                        : 'Practice autonomous navigation through hands-on coding challenges',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (onHome != null)
          IconButton(
            key: const Key('course-home-button'),
            tooltip: 'Home',
            onPressed: onHome,
            icon: const Icon(Icons.home_rounded),
          ),
        if (user.isInstructor)
          IconButton(
            tooltip: 'Instructor Studio',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(
                      arguments: FeedbackPage('Instructor Studio')),
                  builder: (_) => const InstructorAssignmentAdmin(),
                ),
              );
            },
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
        Padding(
          padding: EdgeInsets.only(right: compact ? 4 : AppSpacing.md),
          child: PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) async {
              if (value == 'my-account' && context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(
                        arguments: FeedbackPage('My account')),
                    builder: (_) =>
                        MyAccountPage(user: user, onSignedOut: onLogout),
                  ),
                );
              }
              if (value == 'study-data' && context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(
                        arguments: FeedbackPage('Study data')),
                    builder: (_) => user.isInstructor
                        ? const InstructorResearchDashboard()
                        : const StudentResearchPage(),
                  ),
                );
              }
              if (value == 'logout') {
                await Future<void>.delayed(Duration.zero);
                await onLogout();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  user.isDemo
                      ? 'Demo student (temporary)'
                      : '${user.loginId} (${user.role})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const PopupMenuDivider(),
              if (!user.isDemo)
                const PopupMenuItem<String>(
                  key: Key('my-account-menu-item'),
                  value: 'my-account',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.manage_accounts_outlined),
                    title: Text('My account'),
                  ),
                ),
              if (!user.isDemo)
                PopupMenuItem<String>(
                  value: 'study-data',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insights_rounded),
                    title: Text(
                      user.isInstructor
                          ? 'Research dashboard'
                          : 'My study progress',
                    ),
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle_outlined),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 72 : 120),
                    child: Text(
                      user.isDemo ? 'Demo' : user.loginId,
                      key: const Key('account-name-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
