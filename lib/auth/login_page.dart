import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/session.dart';
import '../data/api.dart';

/// Login for the PSD admin and service providers.
/// [stayHere] is used when the page is shown in place by RoleGate: after
/// signing in, the gated page appears instead of navigating away.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.stayHere = false});

  final bool stayHere;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.stayHere) session.addListener(_routeWhenReady);
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeWhenReady());
  }

  @override
  void dispose() {
    session.removeListener(_routeWhenReady);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _routeWhenReady() {
    if (widget.stayHere || !mounted || !session.ready || !session.signedIn) return;
    if (session.isAdmin) {
      context.go('/admin');
    } else if (session.isProvider) {
      context.go('/dashboard');
    } else {
      setState(() => _error = 'This account is not set up as an admin or provider yet.');
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    session.googleError = null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(_email.text, _password.text);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first, then tap "Forgot password".');
      return;
    }
    try {
      await session.sendPasswordReset(_email.text);
      setState(() => _error = 'Password reset email sent to ${_email.text.trim()}.');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: session, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final error = _error ?? session.googleError;
    final busy = _busy || !session.ready;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.storefront, size: 40, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          'Portfolio Services Dashboard',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sign in to manage your service requests',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: busy ? null : session.signInWithGoogle,
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Admin: continue with Google'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text('Service providers', style: TextStyle(color: Colors.grey.shade600)),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          decoration: const InputDecoration(labelText: 'Password'),
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign in'),
                        ),
                        TextButton(onPressed: _reset, child: const Text('Forgot password')),
                        if (session.signedIn && session.ready && session.profile == null)
                          TextButton(onPressed: session.signOut, child: const Text('Sign out')),
                      ],
                    ),
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
