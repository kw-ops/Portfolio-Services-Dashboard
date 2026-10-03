import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../widgets/common.dart';

/// Admin view of one provider: the Campus Stay link, the provider's login,
/// and shortcuts to edit the portfolio or see its requests.
class ProviderDetailPage extends StatelessWidget {
  const ProviderDetailPage({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Portfolio?>(
      stream: Api.watchPortfolio(providerId),
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/admin')),
            title: Text(p?.name ?? 'Provider'),
            actions: accountActions(context),
          ),
          body: p == null
              ? Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Text('Provider not found.'))
              : SingleChildScrollView(child: Bounded(maxWidth: 760, child: _Body(p: p))),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.p});

  final Portfolio p;

  @override
  Widget build(BuildContext context) {
    final link = portfolioUrl(p.slug);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: const Color(0xFFF5F3FF),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.link, color: Color(0xFF7C3AED)),
              SizedBox(width: 8),
              Text('Campus Stay link', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            const Text('Paste this into Campus Stay admin → Services → this service → Service URL.'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(link, style: const TextStyle(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => copyText(context, link, label: 'Link copied'),
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(link)),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open portfolio'),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit portfolio'),
            subtitle: const Text('Logo, cover, tagline, hours, prices, extra photos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/admin/providers/${p.id}/edit'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('Requests'),
            subtitle: Text('${p.requestCounter} received so far'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/admin/requests?provider=${p.id}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(p.isActive ? Icons.check_circle_outline : Icons.pause_circle_outline,
                color: p.isActive ? Colors.green : Colors.orange),
            title: Text(p.isActive
                ? 'Active — visible to students'
                : 'Hidden — ${p.status == 'removed' ? 'deleted' : 'hidden'} in Campus Stay'),
            subtitle: Text(p.category),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _AccountCard(p: p),
    ]);
  }
}

class _AccountCard extends StatefulWidget {
  const _AccountCard({required this.p});

  final Portfolio p;

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  late Future<List<String>> _emails = Api.providerAccountEmails(widget.p.id);
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final existed = await Api.createProviderAccount(
        providerId: widget.p.id,
        email: _email.text.trim(),
        password: _password.text,
        displayName: widget.p.name,
      );
      if (!mounted) return;
      final dashboard = '${Uri.base.origin}${Uri.base.path}#/login';
      final password = existed
          ? '(their existing password — unchanged)'
          : _password.text;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(existed ? 'Existing account linked' : 'Login created'),
          content: SelectableText(
            'Send these to ${widget.p.name}:\n\n'
            'Dashboard: $dashboard\n'
            'Email: ${_email.text.trim()}\n'
            'Password: $password\n\n'
            'They can change it with "Forgot password" on the login page.',
          ),
          actions: [
            TextButton(
              onPressed: () => copyText(ctx,
                  'Your Campus Stay Services dashboard\n$dashboard\nEmail: ${_email.text.trim()}\nPassword: $password'),
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      _email.clear();
      _password.clear();
      setState(() => _emails = Api.providerAccountEmails(widget.p.id));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Provider dashboard login', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<String>>(
            future: _emails,
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              if (snap.data!.isEmpty) {
                return Text('No login yet — the provider cannot see requests until you create one.',
                    style: TextStyle(color: Colors.orange.shade800));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in snap.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.person_outline, size: 18),
                      const SizedBox(width: 6),
                      Text(e),
                    ]),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 16),
          Form(
            key: _form,
            child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 260,
                child: TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Provider email', isDense: true),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter an email',
                ),
              ),
              SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Temporary password', isDense: true),
                  validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? 'Creating…' : 'Create login'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
