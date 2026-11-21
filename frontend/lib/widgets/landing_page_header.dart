import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:iuse_demo/state/feedback_page_tracker.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/screens/my_account_page.dart';
import 'package:iuse_demo/screens/instructor_assignment_admin.dart';
import 'package:iuse_demo/screens/research_dashboard_page.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// The home header: a compact, floating, rounded brand card on the page.
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

  /// Height of the card itself; the margin around it is added on top.
  static const double barHeight = 60;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight + 18);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final side = compact ? 8.0 : 16.0;

    return ColoredBox(
      color: AppColors.pageBackground,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 10, side, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                const BoxShadow(
                  color: Color(0x1416222E),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.xl),
              child: _bar(context, compact),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    return AppBar(
      primary: false,
      toolbarHeight: barHeight,
      titleSpacing: compact ? 4 : 14,
      leadingWidth: compact ? 46 : 58,
      leading: onHome == null
          ? null
          : Center(
              child: HeaderIconButton(
                tooltip: 'Back',
                onPressed: onHome!,
                icon: LucideIcons.arrowLeft,
              ),
            ),
      elevation: 0,
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      title: Row(
        children: [
          if (!compact) ...[
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
            child: Icon(
              LucideIcons.cpu,
              size: compact ? 19 : 21,
              semanticLabel: 'Robotics lab',
            ),
          ),
          const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Robotics Programming Lab',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 15 : 17,
                    letterSpacing: -0.2,
                  ),
                ),
                if (!compact)
                  Text(
                    user.isDemo
                        ? 'Demo mode: all work resets when you refresh'
                        : 'Practice autonomous navigation through hands-on coding challenges',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (onHome != null)
          HeaderIconButton(
            key: const Key('course-home-button'),
            tooltip: 'Home',
            onPressed: onHome!,
            icon: LucideIcons.house,
          ),
        if (user.isInstructor)
          HeaderIconButton(
            tooltip: 'Instructor Studio',
            icon: LucideIcons.layoutDashboard,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(
                      arguments: FeedbackPage('Instructor Studio')),
                  builder: (_) => const InstructorAssignmentAdmin(),
                ),
              );
            },
          ),
        Padding(
          padding: EdgeInsets.only(left: 4, right: compact ? 8 : 12),
          child: PopupMenuButton<String>(
            tooltip: 'Account menu',
            position: PopupMenuPosition.under,
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
                    leading: Icon(LucideIcons.userRoundCog, size: 20),
                    title: Text('My account'),
                  ),
                ),
              if (!user.isDemo)
                PopupMenuItem<String>(
                  value: 'study-data',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.chartLine, size: 20),
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
                  leading: Icon(LucideIcons.logOut, size: 20),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: _AccountPill(user: user, compact: compact),
          ),
        ),
      ],
    );
  }
}

class _AccountPill extends StatelessWidget {
  const _AccountPill({required this.user, required this.compact});

  final AuthenticatedUser user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = user.isDemo ? 'Demo' : user.loginId;
    return Container(
      padding: EdgeInsets.fromLTRB(4, 4, compact ? 8 : 10, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.white,
            child: ExcludeSemantics(
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: AppColors.brandDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 64 : 120),
            child: Text(
              name,
              key: const Key('account-name-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronDown, size: 16, color: Colors.white),
          ],
        ],
      ),
    );
  }
}

/// A soft, rounded icon button for the brand header.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            hoverColor: Colors.white.withValues(alpha: 0.2),
            minimumSize: const Size(40, 40),
            fixedSize: const Size(40, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            ),
          ),
        ),
      );
}
