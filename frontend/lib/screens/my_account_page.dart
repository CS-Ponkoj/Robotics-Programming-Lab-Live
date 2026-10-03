import 'package:flutter/material.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Lets a signed-in student or instructor review their account and change
/// their own password. Login ID and participant code are managed by
/// instructors, so they are shown read-only.
class MyAccountPage extends StatefulWidget {
  const MyAccountPage({
    super.key,
    required this.user,
    required this.onSignedOut,
  });

  final AuthenticatedUser user;

  /// Called after a password change, when the server has ended every session.
  final Future<void> Function() onSignedOut;

  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidePasswords = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthApi.changePassword(_current.text, _next.text);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;
    // The change is complete; stop the button spinner behind the dialog.
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('password-changed-dialog'),
        title: const Text('Password changed'),
        content: const Text(
          'For your security you have been signed out on every device. '
          'Sign in again with your new password.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sign in again'),
          ),
        ],
      ),
    );
    await widget.onSignedOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;
    final student = !user.isInstructor;

    Widget detail(String label, String value, {String? note}) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              // Plain text so screen readers announce the value on the web.
              Text(value, style: theme.textTheme.titleMedium),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        );

    InputDecoration passwordField(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _hidePasswords ? 'Show passwords' : 'Hide passwords',
            onPressed: () => setState(() => _hidePasswords = !_hidePasswords),
            icon: Icon(_hidePasswords
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('My account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              Text(
                'ACCOUNT',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.brand,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text('Your account', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 20),
              Card(
                key: const Key('account-details-card'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Details', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 16),
                      detail('Login ID', user.loginId,
                          note: 'Used to sign in. It cannot be changed.'),
                      detail('Role', student ? 'Student' : 'Instructor'),
                      if (student)
                        detail(
                          'Participant code',
                          (user.participantCode?.isNotEmpty ?? false)
                              ? user.participantCode!
                              : 'Not assigned',
                          note: 'Your anonymous study ID, assigned by your '
                              'instructor. Ask your instructor if it needs to '
                              'change.',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                key: const Key('change-password-card'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Change password',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Choose a password only you know. You will be '
                          'signed out everywhere and asked to sign in again.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('current-password-field'),
                          controller: _current,
                          enabled: !_saving,
                          obscureText: _hidePasswords,
                          decoration: passwordField('Current password'),
                          validator: (value) => (value ?? '').isEmpty
                              ? 'Enter your current password.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('new-password-field'),
                          controller: _next,
                          enabled: !_saving,
                          obscureText: _hidePasswords,
                          decoration: passwordField('New password'),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            if (password == _current.text) {
                              return 'Choose a password different from the current one.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('confirm-password-field'),
                          controller: _confirm,
                          enabled: !_saving,
                          obscureText: _hidePasswords,
                          decoration: passwordField('Confirm new password'),
                          validator: (value) => value != _next.text
                              ? 'Passwords do not match.'
                              : null,
                          onFieldSubmitted: (_) => _changePassword(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            key: const Key('change-password-error'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const Key('change-password-button'),
                            onPressed: _saving ? null : _changePassword,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_reset_rounded),
                            label:
                                Text(_saving ? 'Saving...' : 'Change password'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
