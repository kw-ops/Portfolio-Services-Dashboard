import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../models/service_request.dart';
import '../widgets/common.dart';
import '../widgets/request_tile.dart';

/// A provider's home: live request inbox from Campus Stay students.
class ProviderDashboardPage extends StatefulWidget {
  const ProviderDashboardPage({super.key, required this.providerId});

  final String providerId;

  @override
  State<ProviderDashboardPage> createState() => _ProviderDashboardPageState();
}

class _ProviderDashboardPageState extends State<ProviderDashboardPage> {
  late final _portfolio = Api.watchPortfolio(widget.providerId);
  late final _requests = Api.watchProviderRequests(widget.providerId);
  RequestFilter _filter = RequestFilter.open;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Portfolio?>(
      stream: _portfolio,
      builder: (context, pSnap) {
        final p = pSnap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p?.name ?? 'Dashboard'),
            actions: [
              if (p != null)
                IconButton(
                  tooltip: 'View my public page',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => launchUrl(Uri.parse(portfolioUrl(p.slug, campusStay: false))),
                ),
              IconButton(
                tooltip: 'Edit my portfolio',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.go('/dashboard/portfolio'),
              ),
              ...accountActions(context),
            ],
          ),
          body: StreamBuilder<List<ServiceRequest>>(
            stream: _requests,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Could not load requests: ${friendlyError(snap.error!)}'));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final all = snap.data!;
              int n(List<String> s) => all.where((r) => s.contains(r.status)).length;
              final shown = all.where(_filter.matches).toList();

              return ListView(children: [
                Bounded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (p != null && !p.isActive)
                      const Card(
                        color: Color(0xFFFFF7ED),
                        child: ListTile(
                          leading: Icon(Icons.pause_circle_outline, color: Colors.orange),
                          title: Text('Your portfolio is currently hidden from students.'),
                          subtitle: Text('It is hidden in Campus Stay. Contact the Campus Stay services admin.'),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      StatTile(
                        label: 'New requests',
                        value: '${n(['pending'])}',
                        color: statusColor('pending'),
                        onTap: () => setState(() => _filter = RequestFilter.newOnes),
                      ),
                      StatTile(
                        label: 'Accepted',
                        value: '${n(['accepted', 'scheduled'])}',
                        color: statusColor('accepted'),
                        onTap: () => setState(() => _filter = RequestFilter.accepted),
                      ),
                      StatTile(
                        label: 'In progress',
                        value: '${n(['in_progress'])}',
                        color: statusColor('in_progress'),
                        onTap: () => setState(() => _filter = RequestFilter.inProgress),
                      ),
                      StatTile(
                        label: 'Completed',
                        value: '${n(['completed'])}',
                        color: statusColor('completed'),
                        onTap: () => setState(() => _filter = RequestFilter.completed),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    Text('Requests', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    RequestFilterBar(
                      value: _filter,
                      requests: all,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            all.isEmpty
                                ? 'No requests yet. They will appear here the moment a student sends one.'
                                : 'Nothing in this list.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    for (final r in shown)
                      RequestTile(request: r, onTap: () => context.go('/dashboard/requests/${r.id}')),
                  ]),
                ),
              ]);
            },
          ),
        );
      },
    );
  }
}
