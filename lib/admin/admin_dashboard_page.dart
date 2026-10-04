import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../widgets/common.dart';

/// PSD super-admin home: platform numbers and every provider portfolio.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _portfolios = Api.watchAllPortfolios();
  final _lastSync = Api.watchLastSync();
  late Future<List<int>> _counts = _loadCounts();
  String _search = '';
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final r = await Api.syncCampusStay();
      if (mounted) {
        showSnack(
          context,
          'Synced ${r.total} services from Campus Stay — ${r.created} new, ${r.updated} updated, ${r.removed} removed.',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<List<int>> _loadCounts() {
    final r = Api.allRequestsQuery;
    return Future.wait([
      Api.count(r),
      Api.count(r.where('status', isEqualTo: 'pending')),
      Api.count(r.where('status', isEqualTo: 'completed')),
      Api.count(r.where('sourcePlatform', isEqualTo: kSourceCampusStay)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PSD Admin'),
        actions: [
          if (isCompact(context))
            IconButton(
              tooltip: 'All requests',
              onPressed: () => context.go('/admin/requests'),
              icon: const Icon(Icons.inbox_outlined),
            )
          else
            TextButton.icon(
              onPressed: () => context.go('/admin/requests'),
              icon: const Icon(Icons.inbox_outlined),
              label: const Text('All requests'),
            ),
          ...accountActions(context),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncing ? null : _sync,
        icon: _syncing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
        label: Text(_syncing ? 'Syncing…' : (isCompact(context) ? 'Sync' : 'Sync from Campus Stay')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _counts = _loadCounts()),
        child: StreamBuilder<List<Portfolio>>(
          stream: _portfolios,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
            final all = snap.data;
            final shown = (all ?? const <Portfolio>[])
                .where(
                  (p) =>
                      _search.isEmpty ||
                      p.name.toLowerCase().contains(_search) ||
                      p.category.toLowerCase().contains(_search),
                )
                .toList();
            return ListView(
              children: [
                Bounded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<List<int>>(
                        future: _counts,
                        builder: (context, c) {
                          String v(int i) => c.hasData ? '${c.data![i]}' : '…';
                          return StatGrid(
                            children: [
                              StatTile(label: 'Providers', value: all == null ? '…' : '${all.length}'),
                              StatTile(
                                label: 'Active portfolios',
                                value: all == null ? '…' : '${all.where((p) => p.isActive).length}',
                              ),
                              StatTile(
                                label: 'Total requests',
                                value: v(0),
                                onTap: () => context.go('/admin/requests'),
                              ),
                              StatTile(label: 'New (pending)', value: v(1), color: statusColor('pending')),
                              StatTile(label: 'Completed', value: v(2), color: statusColor('completed')),
                              StatTile(
                                label: 'From Campus Stay',
                                value: v(3),
                                color: const Color(0xFF7C3AED),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      _header(context),
                      const SizedBox(height: 12),
                      if (all == null) const Center(child: CircularProgressIndicator()),
                      if (all != null && all.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No providers yet. Tap "Sync from Campus Stay" to import the services '
                              'listed in Campus Stay admin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                      _ProviderList(providers: shown),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Title + last-sync note and the search box: side by side on wide
  /// screens, stacked on phones.
  Widget _header(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Providers', style: Theme.of(context).textTheme.titleLarge),
        StreamBuilder<DateTime?>(
          stream: _lastSync,
          builder: (context, s) => Text(
            'From Campus Stay · auto-sync every 30 min · last: ${formatDateTime(s.data)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      ],
    );
    final search = TextField(
      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
    );
    if (isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 10), search],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        SizedBox(width: 260, child: search),
      ],
    );
  }
}

/// One column on phones/tablets, two on wide screens.
class _ProviderList extends StatelessWidget {
  const _ProviderList({required this.providers});

  final List<Portfolio> providers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 10.0;
      final cols = c.maxWidth >= 860 ? 2 : 1;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final p in providers)
            SizedBox(
              width: w,
              child: _ProviderCard(p: p),
            ),
        ],
      );
    },
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.p});

  final Portfolio p;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundImage: p.logoUrl == null ? null : NetworkImage(p.logoUrl!),
        onForegroundImageError: p.logoUrl == null ? null : (_, _) {},
        child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.category} · ${p.requestCounter} requests${p.ownerUid == null ? ' · no login yet' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!p.isActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                p.status == 'removed' ? 'Deleted in Campus Stay' : 'Hidden in Campus Stay',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
        ],
      ),
      onTap: () => context.go('/admin/providers/${p.id}'),
      trailing: IconButton(
        tooltip: 'Copy Campus Stay link',
        icon: const Icon(Icons.copy),
        onPressed: () =>
            copyText(context, portfolioUrl(p.slug), label: 'Link copied — paste it into Campus Stay admin'),
      ),
    ),
  );
}
