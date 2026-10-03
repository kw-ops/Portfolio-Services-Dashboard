import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../widgets/common.dart';

/// Public portfolio — the page a Campus Stay service link opens.
class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key, required this.slug, this.source});

  final String slug;
  final String? source;

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  late final Future<Portfolio?> _future = Api.portfolioBySlug(widget.slug);

  void _request([String? serviceId]) {
    final q = <String, String>{
      'source': ?widget.source,
      'service': ?serviceId,
    };
    context.push(Uri(path: '/p/${widget.slug}/request', queryParameters: q.isEmpty ? null : q).toString());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Portfolio?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final p = snap.data;
        if (snap.hasError || p == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.storefront_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(snap.hasError ? 'Could not load this service. Check your connection.' :
                      'This service is not available right now.',
                      textAlign: TextAlign.center),
                ]),
              ),
            ),
          );
        }
        return _PortfolioView(portfolio: p, source: widget.source, onRequest: _request);
      },
    );
  }
}

class _PortfolioView extends StatelessWidget {
  const _PortfolioView({required this.portfolio, required this.source, required this.onRequest});

  final Portfolio portfolio;
  final String? source;
  final void Function([String? serviceId]) onRequest;

  @override
  Widget build(BuildContext context) {
    final p = portfolio;
    final theme = Theme.of(context);
    final wa = whatsappLink(p.whatsapp.isNotEmpty ? p.whatsapp : p.phone,
        text: 'Hi ${p.name}, I found you on Campus Stay Ghana.');

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: FilledButton.icon(
                onPressed: () => onRequest(),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Request a service'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ),
        ),
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _Header(portfolio: p)),
        SliverToBoxAdapter(
          child: Bounded(
            maxWidth: 760,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (source == kSourceCampusStay || p.isVerified)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(children: [
                    Icon(Icons.verified_outlined, size: 18, color: Color(0xFF7C3AED)),
                    SizedBox(width: 8),
                    Expanded(child: Text('Service partner of Campus Stay Ghana')),
                  ]),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (p.phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:${p.phone}')),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                  ),
                if (wa != null)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp'),
                  ),
                if (p.email.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('mailto:${p.email}')),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Email'),
                  ),
              ]),
              if (p.description.isNotEmpty) ...[
                _sectionTitle(context, 'About ${p.name}'),
                Text(p.description, style: const TextStyle(height: 1.5)),
              ],
              if (p.services.isNotEmpty) ...[
                _sectionTitle(context, 'Our services'),
                for (final s in p.services)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (s.description.isNotEmpty) Text(s.description),
                          if (s.priceFrom != null)
                            Text('From GH₵${s.priceFrom}',
                                style: TextStyle(
                                    color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                        ]),
                        trailing: TextButton(onPressed: () => onRequest(s.id), child: const Text('Request')),
                      ),
                    ),
                  ),
              ],
              if (p.photos.isNotEmpty) ...[
                _sectionTitle(context, 'Gallery'),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final url in p.photos)
                      GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            clipBehavior: Clip.antiAlias,
                            child: NetImage(url, fit: BoxFit.contain),
                          ),
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(url)),
                      ),
                  ],
                ),
              ],
              _sectionTitle(context, 'Location & hours'),
              if (p.location.isNotEmpty) _infoRow(Icons.place_outlined, p.location),
              if (p.hours.isNotEmpty) _infoRow(Icons.schedule, p.hours),
              const SizedBox(height: 32),
              Center(
                child: Text('Listed on Campus Stay Ghana',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.portfolio});

  final Portfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final p = portfolio;
    final theme = Theme.of(context);
    return Column(children: [
      SizedBox(
        height: 240,
        child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
          if (p.coverImage != null)
            NetImage(p.coverImage!)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          Positioned(
            bottom: -44,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
                ),
                clipBehavior: Clip.antiAlias,
                child: p.logoUrl != null
                    ? NetImage(p.logoUrl!)
                    : Center(
                        child: Text(
                          p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 52),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          Text(p.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(p.category, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500)),
          if (p.tagline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.tagline, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (p.location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(p.location, style: TextStyle(color: Colors.grey.shade600)),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }
}
