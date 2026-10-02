import 'package:flutter/material.dart';
import 'package:iuse_demo/feature_flags.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/services/external_link.dart';
import 'package:iuse_demo/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onAuthenticated,
  });

  final Future<void> Function(AuthenticatedUser) onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _working = false;
  bool _hidePassword = true;
  String? _error;
  bool _resetComplete = false;

  String? get _resetToken => Uri.base.queryParameters['password_token']?.trim();

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final session = await AuthApi.login(
        _loginIdController.text.trim(),
        _passwordController.text,
      );
      await widget.onAuthenticated(session.user);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _displayError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _startDemo() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final session = await AuthApi.demoLogin();
      await widget.onAuthenticated(session.user);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _displayError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await AuthApi.resetPassword(
        _resetToken!,
        _newPasswordController.text,
      );
      if (mounted) {
        setState(() => _resetComplete = true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _displayError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _showForgotPassword() async {
    final controller = TextEditingController(text: _loginIdController.text);
    bool sending = false;
    String? message;
    await showDialog<void>(
      context: context,
      barrierDismissible: !sending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset password'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter your login ID or email. If an email is connected '
                      'to the account, a one-time reset link will be sent.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      enabled: !sending,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Login ID or email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Text(message!),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      sending ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: sending || controller.text.trim().isEmpty
                      ? null
                      : () async {
                          setDialogState(() {
                            sending = true;
                            message = null;
                          });
                          try {
                            final result = await AuthApi.forgotPassword(
                              controller.text.trim(),
                            );
                            setDialogState(() => message = result);
                          } on Object catch (error) {
                            setDialogState(
                              () => message = _displayError(error),
                            );
                          } finally {
                            setDialogState(() => sending = false);
                          }
                        },
                  child: Text(sending ? 'Sending...' : 'Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resetMode = selfServicePasswordResetEnabled &&
        _resetToken != null &&
        _resetToken!.isNotEmpty &&
        !_resetComplete;
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final form = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFormCard(context, resetMode),
              const SizedBox(height: 24),
              const LoginCredits(),
            ],
          );
          if (constraints.maxWidth >= 960) {
            return Row(
              children: [
                const Expanded(child: _BrandPanel()),
                SizedBox(
                  width: constraints.maxWidth >= 1280 ? 600 : 520,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: form,
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                const _BrandPanel(compact: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Center(child: form),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, bool resetMode) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: appCardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  resetMode ? 'Choose a new password' : 'Sign in',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  resetMode
                      ? 'Your new password must contain at least 8 characters.'
                      : 'Sign in with the study account provided by your instructor.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_resetComplete) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Password updated. Sign in with your new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (resetMode) ...[
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _hidePassword = !_hidePassword,
                        ),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) < 8
                        ? 'Use at least 8 characters.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value != _newPasswordController.text
                        ? 'Passwords do not match.'
                        : null,
                    onFieldSubmitted: (_) => _resetPassword(),
                  ),
                ] else ...[
                  TextFormField(
                    key: const Key('login-id-field'),
                    controller: _loginIdController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Login ID',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Enter your login ID.'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('login-password-field'),
                    controller: _passwordController,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _hidePassword = !_hidePassword,
                        ),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Enter your password.'
                        : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('login-submit-button'),
                  onPressed: _working
                      ? null
                      : resetMode
                          ? _resetPassword
                          : _login,
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          resetMode
                              ? Icons.password_rounded
                              : Icons.login_rounded,
                        ),
                  label: Text(
                    _working
                        ? 'Please wait...'
                        : resetMode
                            ? 'Save new password'
                            : 'Sign in',
                  ),
                ),
                if (!resetMode) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    key: const Key('student-demo-button'),
                    onPressed: _working ? null : _startDemo,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Try the student demo'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Use every student learning tool without an account. '
                    'Demo work is temporary and resets when you refresh.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_working) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'The free demo server may take up to one minute to wake.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!resetMode && selfServicePasswordResetEnabled) ...[
                  TextButton(
                    onPressed: _working ? null : _showForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Project credits shown below the sign-in card.
class LoginCredits extends StatelessWidget {
  const LoginCredits({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget line(List<Widget> children) => Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: children,
        );
    return ConstrainedBox(
      key: const Key('login-credits'),
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        children: [
          line([
            Text('Developed by', style: muted),
            const _CreditLink(
              label: 'Ponkoj Shill',
              url: 'https://ponkoj.com',
              semanticsLabel: 'Ponkoj Shill, ponkoj.com',
            ),
            Text('· ponkoj.com', style: muted),
          ]),
          const SizedBox(height: 6),
          line([
            const _CreditLink(
              label: 'Robotics Research Lab',
              url: 'https://rrl.cse.unr.edu/en/',
              semanticsLabel: 'Robotics Research Lab, rrl.cse.unr.edu',
            ),
            Text('· rrl.cse.unr.edu', style: muted),
          ]),
          const SizedBox(height: 2),
          Text(
            'University of Nevada, Reno',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _CreditLink extends StatelessWidget {
  const _CreditLink({
    required this.label,
    required this.url,
    required this.semanticsLabel,
  });

  final String label;
  final String url;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A semantics href would also navigate the app's own tab away, ending the
    // session, so this is an explicitly labeled new-tab button instead.
    return Semantics(
      button: true,
      label: '$semanticsLabel, opens in a new tab',
      // excludeSemantics hides the InkWell, so assistive technology needs
      // the activation action here.
      onTap: () => openExternalLink(url),
      excludeSemantics: true,
      child: Tooltip(
        message: url,
        child: InkWell(
          onTap: () => openExternalLink(url),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.brandDark,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.brandDark.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoopStep {
  const _LoopStep(this.icon, this.title, this.detail);
  final IconData icon;
  final String title;
  final String detail;
}

const _learningLoop = [
  _LoopStep(Icons.menu_book_rounded, 'Learn',
      'Short lessons, diagrams, and quizzes for each robotics topic.'),
  _LoopStep(Icons.code_rounded, 'Code',
      'Write Python and ROS 2 solutions in a full code editor.'),
  _LoopStep(Icons.fact_check_rounded, 'Evaluate',
      'Run the tests and see exactly which checks pass.'),
  _LoopStep(Icons.auto_awesome_rounded, 'Improve',
      'Progressive hints, plus optional AI tutoring when enabled.'),
];

/// Explains what the lab offers beside the sign-in form.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBrand = Colors.white.withValues(alpha: 0.86);
    final logo = Container(
      width: compact ? 40 : 48,
      height: compact ? 40 : 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: const Icon(Icons.memory_rounded, color: Colors.white, size: 26),
    );
    return Container(
      width: double.infinity,
      constraints: compact ? null : const BoxConstraints.expand(),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandDeep, AppColors.brandDark, AppColors.brand],
        ),
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 28, 20, 24)
          : const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
      child: SafeArea(
        bottom: false,
        child: compact
            ? Row(
                children: [
                  logo,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Robotics Programming Lab',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Learn robotics by writing code that runs.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: onBrand),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            logo,
                            const SizedBox(width: 14),
                            Text(
                              'Robotics Programming Lab',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),
                        Text(
                          'Learn robotics by writing code that runs.',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Study each concept, solve versioned coding '
                          'assignments, and turn every test result into '
                          'your next step.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onBrand,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 40),
                        for (final (index, step) in _learningLoop.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(step.icon,
                                      color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${index + 1}. ${step.title}',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: Colors.white),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        step.detail,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: onBrand),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

String _displayError(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}
