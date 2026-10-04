import 'package:flutter/material.dart';

import '../models/service_request.dart';
import 'common.dart';

class RequestTile extends StatelessWidget {
  const RequestTile({super.key, required this.request, required this.onTap, this.showProvider = false});

  final ServiceRequest request;
  final VoidCallback onTap;
  final bool showProvider;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(r.ref, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          SourceBadge(r.sourcePlatform),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        showProvider ? '${r.serviceName} · ${r.providerName}' : r.serviceName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${r.studentName} · ${r.location}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade800),
                            ),
                          ),
                          if (r.studentVerified) ...[
                            const SizedBox(width: 4),
                            const Tooltip(
                              message: 'Verified Campus Stay student',
                              child: Icon(Icons.verified, size: 16, color: Color(0xFF7C3AED)),
                            ),
                          ],
                        ],
                      ),
                      if (r.description.isNotEmpty)
                        Text(
                          r.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        formatDateTime(r.createdAt),
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(r.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter tabs used on both request lists.
enum RequestFilter {
  open('Open', ['pending', 'accepted', 'scheduled', 'in_progress']),
  newOnes('New', ['pending']),
  accepted('Accepted', ['accepted', 'scheduled']),
  inProgress('In progress', ['in_progress']),
  completed('Completed', ['completed']),
  closed('Rejected / cancelled', ['rejected', 'cancelled']),
  all('All', []);

  const RequestFilter(this.label, this.statuses);

  final String label;
  final List<String> statuses;

  bool matches(ServiceRequest r) => statuses.isEmpty || statuses.contains(r.status);
}

class RequestFilterBar extends StatelessWidget {
  const RequestFilterBar({super.key, required this.value, required this.onChanged, required this.requests});

  final RequestFilter value;
  final ValueChanged<RequestFilter> onChanged;
  final List<ServiceRequest> requests;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final f in RequestFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${f.label} (${requests.where(f.matches).length})'),
              selected: value == f,
              onSelected: (_) => onChanged(f),
            ),
          ),
      ],
    ),
  );
}
