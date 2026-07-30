import 'package:flutter/material.dart';
import 'package:iuse_demo/services/student_admin_api.dart';

class StudentAccountsPage extends StatefulWidget {
  const StudentAccountsPage({super.key});

  @override
  State<StudentAccountsPage> createState() => _StudentAccountsPageState();
}

class _StudentAccountsPageState extends State<StudentAccountsPage> {
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic> _emailStatus = const {'configured': false};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await fetchStudents();
      final emailStatus = await fetchEmailStatus();
      if (mounted) {
        setState(() {
          _students = students;
          _emailStatus = emailStatus;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _displayError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createStudent() async {
    final loginController = TextEditingController();
    final participantController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool sendEmail = false;
    final emailConfigured = _emailStatus['configured'] == true;
    bool saving = false;
    String? dialogError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              setDialogState(() {
                saving = true;
                dialogError = null;
              });
              try {
                final created = await createStudent(
                  loginId: loginController.text.trim(),
                  temporaryPassword: sendEmail ? null : passwordController.text,
                  email: emailController.text,
                  participantCode: participantController.text,
                  sendInvitationEmail: sendEmail,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(created);
                }
              } on Object catch (error) {
                setDialogState(() {
                  dialogError = _displayError(error);
                  saving = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Create student account'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: loginController,
                          autofocus: true,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Student login ID',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Login ID is required.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: participantController,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Participant code (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: emailController,
                          enabled: !saving,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: sendEmail
                                ? 'Email address'
                                : 'Email (optional)',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (sendEmail && email.isEmpty) {
                              return 'Email is required for an invitation.';
                            }
                            if (email.isNotEmpty && !email.contains('@')) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: passwordController,
                          enabled: !saving && !sendEmail,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Temporary password (optional)',
                            helperText:
                                'Leave blank to generate a secure password.',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (!sendEmail &&
                                value != null &&
                                value.isNotEmpty &&
                                value.length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            return null;
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: sendEmail,
                          onChanged: saving || !emailConfigured
                              ? null
                              : (value) => setDialogState(
                                    () => sendEmail = value ?? false,
                                  ),
                          title: const Text('Send one-time activation link'),
                          subtitle: Text(
                            emailConfigured
                                ? 'No reusable password is sent by email.'
                                : 'Configure SMTP in backend/.env first.',
                          ),
                        ),
                        if (dialogError != null)
                          Text(
                            dialogError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : submit,
                  child: Text(saving ? 'Creating...' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    loginController.dispose();
    participantController.dispose();
    emailController.dispose();
    passwordController.dispose();
    if (result != null) {
      await _load();
      if (mounted) {
        await _showCredentials(result, title: 'Student account created');
      }
    }
  }

  Future<void> _showCredentials(
    Map<String, dynamic> result, {
    required String title,
  }) async {
    final user = Map<String, dynamic>.from(result['user'] as Map);
    final password = result['temporary_password'] as String?;
    final emailSent = result['email_sent'] as bool? ?? false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('Login ID: ${user['login_id']}'),
              const SizedBox(height: 8),
              if (password != null) ...[
                SelectableText('Temporary password: $password'),
                const SizedBox(height: 12),
                const Text(
                  'Copy and share this password securely now. It will not be '
                  'shown again.',
                ),
              ] else if (emailSent)
                const Text(
                  'A one-time password setup link was sent to the student.',
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final emailController =
        TextEditingController(text: student['email']?.toString() ?? '');
    final participantController = TextEditingController(
      text: student['participant_code']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) {
              return;
            }
            setDialogState(() {
              saving = true;
              dialogError = null;
            });
            try {
              await updateStudent(
                student['id'] as String,
                email: emailController.text,
                participantCode: participantController.text,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            } on Object catch (error) {
              setDialogState(() {
                saving = false;
                dialogError = _displayError(error);
              });
            }
          }

          return AlertDialog(
            title: Text('Edit ${student['login_id']}'),
            content: SizedBox(
              width: 460,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: participantController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Participant code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: emailController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.isNotEmpty && !email.contains('@')
                            ? 'Enter a valid email address.'
                            : null;
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    emailController.dispose();
    participantController.dispose();
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> student) async {
    final passwordController = TextEditingController();
    bool sendEmail = false;
    final emailConfigured = _emailStatus['configured'] == true;
    bool saving = false;
    String? dialogError;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            if (sendEmail && student['email'] == null) {
              setDialogState(
                () => dialogError = 'Add an email address first.',
              );
              return;
            }
            if (!sendEmail &&
                passwordController.text.isNotEmpty &&
                passwordController.text.length < 8) {
              setDialogState(
                () => dialogError = 'Use at least 8 characters.',
              );
              return;
            }
            setDialogState(() {
              saving = true;
              dialogError = null;
            });
            try {
              final value = await resetStudentPassword(
                student['id'] as String,
                temporaryPassword: sendEmail ? null : passwordController.text,
                sendEmail: sendEmail,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(value);
              }
            } on Object catch (error) {
              setDialogState(() {
                saving = false;
                dialogError = _displayError(error);
              });
            }
          }

          return AlertDialog(
            title: Text('Reset password for ${student['login_id']}'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passwordController,
                    enabled: !saving && !sendEmail,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New temporary password (optional)',
                      helperText: 'Leave blank to generate one.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sendEmail,
                    onChanged: saving || !emailConfigured
                        ? null
                        : (value) => setDialogState(
                              () => sendEmail = value ?? false,
                            ),
                    title: const Text('Send one-time reset link by email'),
                    subtitle: emailConfigured
                        ? null
                        : const Text('Configure SMTP in backend/.env first.'),
                  ),
                  if (dialogError != null)
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'Resetting...' : 'Reset password'),
              ),
            ],
          );
        },
      ),
    );
    passwordController.dispose();
    if (result != null && mounted) {
      await _showCredentials(result, title: 'Password reset');
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> student) async {
    final isActive = student['is_active'] as bool? ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'Deactivate student?' : 'Reactivate student?'),
        content: Text(
          isActive
              ? '${student['login_id']} will be signed out and unable to log in. '
                  'Their study records are preserved.'
              : '${student['login_id']} will be allowed to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await updateStudent(
        student['id'] as String,
        active: !isActive,
      );
      await _load();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_displayError(error))),
        );
      }
    }
  }

  Future<void> _importAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await importStudyAccounts();
      await _load();
      if (mounted) {
        final errors = report['errors'] as List? ?? const [];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'JSON import complete: '
              '${(report['created'] as List? ?? const []).length} created, '
              '${(report['updated'] as List? ?? const []).length} updated, '
              '${errors.length} errors.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _displayError(error);
        });
      }
    }
  }

  Future<void> _testEmailDelivery() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final recipient = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send SMTP test email'),
        content: SizedBox(
          width: 430,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Recipient email address',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                return email.contains('@')
                    ? null
                    : 'Enter a valid email address.';
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Send test'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (recipient == null || !mounted) {
      return;
    }
    setState(() => _loading = true);
    try {
      await sendTestEmail(recipient);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test email sent to $recipient.')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_displayError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailConfigured = _emailStatus['configured'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student accounts'),
        actions: [
          IconButton(
            tooltip: 'Import study_accounts.json',
            onPressed: _loading ? null : _importAccounts,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: 'Create student',
            onPressed: _loading ? null : _createStudent,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Study participant access',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create login credentials, connect optional participant '
                  'codes and email addresses, reset access, or deactivate an '
                  'account while preserving its study data.',
                ),
                const SizedBox(height: 16),
                Card(
                  color: emailConfigured
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: ListTile(
                    leading: Icon(
                      emailConfigured
                          ? Icons.mark_email_read_outlined
                          : Icons.mark_email_unread_outlined,
                      color: emailConfigured
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                    title: Text(
                      emailConfigured
                          ? 'Real email delivery is configured'
                          : 'Real email delivery is not configured',
                    ),
                    subtitle: Text(
                      emailConfigured
                          ? '${_emailStatus['host']}:${_emailStatus['port']} • '
                              '${_emailStatus['sender']}'
                          : 'Add SMTP_HOST, SMTP_PORT, SMTP_USERNAME, '
                              'SMTP_PASSWORD, and SMTP_FROM to backend/.env, '
                              'then restart the backend.',
                    ),
                    trailing: emailConfigured
                        ? TextButton.icon(
                            onPressed: _loading ? null : _testEmailDelivery,
                            icon: const Icon(Icons.outgoing_mail),
                            label: const Text('Send test'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _students.isEmpty
                          ? const Center(
                              child: Text('No student accounts found.'),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                itemCount: _students.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final student = _students[index];
                                  final active =
                                      student['is_active'] as bool? ?? false;
                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: active
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        child: Icon(
                                          active
                                              ? Icons.person_rounded
                                              : Icons.person_off_outlined,
                                        ),
                                      ),
                                      title:
                                          Text(student['login_id'] as String),
                                      subtitle: Text(
                                        [
                                          student['participant_code'],
                                          student['email'],
                                          active ? 'Active' : 'Inactive',
                                        ]
                                            .where(
                                              (value) =>
                                                  value != null &&
                                                  value.toString().isNotEmpty,
                                            )
                                            .join(' • '),
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'edit':
                                              _editStudent(student);
                                            case 'reset':
                                              _resetPassword(student);
                                            case 'active':
                                              _toggleActive(student);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit details'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'reset',
                                            child: Text('Reset password'),
                                          ),
                                          PopupMenuItem(
                                            value: 'active',
                                            child: Text(
                                              active
                                                  ? 'Deactivate'
                                                  : 'Reactivate',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createStudent,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New student'),
      ),
    );
  }
}

String _displayError(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}
