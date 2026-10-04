import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../models/service_request.dart';
import '../widgets/common.dart';
import '../widgets/request_tile.dart';

/// Every request across all providers (optionally one provider's).
class AdminRequestsPage extends StatefulWidget {
  const AdminRequestsPage({super.key, this.providerId});

  final String? providerId;

  @override
  State<AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends State<AdminRequestsPage> {
  late final _stream = widget.providerId == null
      ? Api.watchAllRequests()
      : Api.watchProviderRequests(widget.providerId!);
  RequestFilter _filter = RequestFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go(widget.providerId == null ? '/admin' : '/admin/providers/${widget.providerId}'),
        ),
        title: const Text('Service requests'),
        actions: accountActions(context),
      ),
      body: StreamBuilder<List<ServiceRequest>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final shown = all.where(_filter.matches).toList();
          return ListView(
            children: [
              Bounded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.providerId != null && all.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(all.first.providerName, style: Theme.of(context).textTheme.titleLarge),
                      ),
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
                          child: Text('No requests.', style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      ),
                    for (final r in shown)
                      RequestTile(
                        request: r,
                        showProvider: widget.providerId == null,
                        onTap: () => context.go('/admin/requests/${r.id}'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
