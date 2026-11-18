import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth_repository.dart';
import '../data/services.dart';
import '../theme/orbit_theme.dart';

/// Sign in, create account, and password reset.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<OrbitServices>().auth;
    try {
      if (_creating) {
        await auth.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
      } else {
        await auth.signIn(email: _email.text, password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<OrbitServices>().auth.sendPasswordReset(email);
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'If an account exists for that email, a reset link is on its way.'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _creating ? 'Create account' : 'Sign in',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _creating
                            ? 'Enter your details to start messaging.'
                            : 'Use your email and password to continue.',
                        style: TextStyle(
                          color: palette.secondaryInk,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_creating) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'Display name'),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Enter a display name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) => (v ?? '').contains('@')
                            ? null
                            : 'Enter a valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autofillHints: [
                          _creating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: palette.secondaryInk,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (v) => (v ?? '').length < 6
                            ? 'Use at least 6 characters'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: palette.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: palette.danger.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    size: 18,
                                    color: palette.danger,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: palette.danger,
                                      fontSize: 13.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(_busy
                            ? 'Please wait…'
                            : _creating
                                ? 'Create account'
                                : 'Sign in'),
                      ),
                      const SizedBox(height: 8),
                      if (!_creating)
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(44)),
                          child: const Text('Forgot password?'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _creating = !_creating;
                                  _error = null;
                                }),
                        style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44)),
                        child: Text(_creating
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account'),
                      ),
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
