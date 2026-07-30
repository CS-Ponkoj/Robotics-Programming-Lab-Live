import 'package:flutter/material.dart';
import 'package:iuse_demo/models/authenticated_user.dart';
import 'package:iuse_demo/services/auth_api.dart';
import 'package:iuse_demo/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onAuthenticated,
  });

  final ValueChanged<AuthenticatedUser> onAuthenticated;

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
      widget.onAuthenticated(session.user);
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
    final resetMode =
        _resetToken != null && _resetToken!.isNotEmpty && !_resetComplete;
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.memory_rounded,
                        size: 54,
                        color: AppColors.brand,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        resetMode
                            ? 'Choose a new password'
                            : 'Robotics Programming Lab',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        resetMode
                            ? 'Your new password must contain at least 8 characters.'
                            : 'Sign in with the study account provided by your instructor.',
                        textAlign: TextAlign.center,
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
                          validator: (value) =>
                              value != _newPasswordController.text
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
                        TextButton(
                          onPressed: _working ? null : _showForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                        const Divider(height: 28),
                        const Text(
                          'Prototype demo accounts\n'
                          'Student: student / student\n'
                          'Instructor: instructor / instructor',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
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
