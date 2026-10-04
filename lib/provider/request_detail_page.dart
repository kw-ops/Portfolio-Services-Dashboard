import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/service_request.dart';
import '../widgets/common.dart';

/// One request, with contact buttons and status actions.
/// Shared by the provider dashboard and the PSD admin.
class RequestDetailPage extends StatelessWidget {
  const RequestDetailPage({super.key, required this.requestId, required this.isAdmin});

  final String requestId;
  final bool isAdmin;

  String get _back => isAdmin ? '/admin/requests' : '/dashboard';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServiceRequest?>(
      stream: Api.watchRequest(requestId),
      builder: (context, snap) {
        final r = snap.data;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(_back)),
            title: Text(r == null ? 'Request' : 'Request ${r.ref}'),
            actions: accountActions(context),
          ),
          body: snap.hasError
              ? Center(child: Text(friendlyError(snap.error!)))
              : !snap.hasData && snap.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : r == null
              ? const Center(child: Text('Request not found.'))
              : SingleChildScrollView(
                  child: Bounded(
                    maxWidth: 760,
                    child: RequestDetailBody(request: r, isAdmin: isAdmin),
                  ),
                ),
        );
      },
    );
  }
}

class RequestDetailBody extends StatefulWidget {
  const RequestDetailBody({super.key, required this.request, required this.isAdmin});

  final ServiceRequest request;
  final bool isAdmin;

  @override
  State<RequestDetailBody> createState() => _RequestDetailBodyState();
}

class _RequestDetailBodyState extends State<RequestDetailBody> {
  bool _busy = false;

  Future<void> _changeStatus(String status) async {
    final askNote = status == 'rejected' || status == 'cancelled' || status == 'scheduled';
    String note = '';
    if (askNote) {
      final input = await _askNote(status);
      if (input == null) return;
      note = input;
    }
    setState(() => _busy = true);
    try {
      await Api.updateRequestStatus(widget.request.id, status, note: note);
      if (mounted) showSnack(context, 'Marked as ${statusLabel(status).toLowerCase()}');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askNote(String status) {
    final c = TextEditingController();
    final hint = switch (status) {
      'scheduled' => 'e.g. Tomorrow 2pm at Unity Hall',
      'rejected' => 'Reason (optional) — e.g. Fully booked this week',
      _ => 'Reason (optional)',
    };
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(statusActionLabel(status)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final next = kNextStatuses[r.status] ?? const [];
    final wa = whatsappLink(
      r.studentPhone,
      text:
          'Hi ${r.studentName}, this is ${r.providerName} about your request ${r.ref} '
          '(${r.serviceName}) from Campus Stay Ghana.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.serviceName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    StatusChip(r.status),
                  ],
                ),
                const SizedBox(height: 6),
                SourceBadge(r.sourcePlatform),
                if (widget.isAdmin) ...[const SizedBox(height: 6), Text('Provider: ${r.providerName}')],
                const Divider(height: 28),
                _row('Student', r.studentName),
                if (r.studentVerified)
                  Padding(
                    padding: const EdgeInsets.only(left: 90, bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, size: 16, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Verified Campus Stay student${r.studentSchool.isEmpty ? '' : ' · ${r.studentSchool}'}',
                            style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                _row('Phone', r.studentPhone),
                if (r.studentEmail.isNotEmpty) _row('Email', r.studentEmail),
                _row('Location', r.location),
                _row(
                  'Preferred',
                  [
                    r.preferredDate,
                    r.preferredTime,
                  ].where((s) => s.isNotEmpty).join(' at ').ifEmpty('Any time'),
                ),
                _row('Received', formatDateTime(r.createdAt)),
                const SizedBox(height: 12),
                Text('Details', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(r.description, style: const TextStyle(height: 1.4)),
                if (r.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Photos', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final path in r.attachments) _Attachment(path: path)],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('tel:${r.studentPhone}')),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Call student'),
            ),
            if (wa != null)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp'),
              ),
            if (r.studentEmail.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('mailto:${r.studentEmail}?subject=Your request ${r.ref}')),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Email'),
              ),
          ],
        ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Update status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in next)
                s == 'rejected' || s == 'cancelled'
                    ? OutlinedButton(
                        onPressed: _busy ? null : () => _changeStatus(s),
                        style: OutlinedButton.styleFrom(foregroundColor: statusColor(s)),
                        child: Text(statusActionLabel(s)),
                      )
                    : FilledButton(
                        onPressed: _busy ? null : () => _changeStatus(s),
                        style: FilledButton.styleFrom(backgroundColor: statusColor(s)),
                        child: Text(statusActionLabel(s)),
                      ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final h in r.statusHistory.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.circle, size: 12, color: statusColor(h.status)),
            title: Text(statusLabel(h.status)),
            subtitle: Text([formatDateTime(h.at), if (h.note.isNotEmpty) h.note].join(' — ')),
          ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: Api.attachmentUrl(path),
    builder: (context, snap) {
      if (!snap.hasData) {
        return Container(
          width: 110,
          height: 110,
          color: Colors.grey.shade200,
          child: snap.hasError ? const Icon(Icons.broken_image_outlined) : null,
        );
      }
      return InkWell(
        onTap: () => launchUrl(Uri.parse(snap.data!)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: NetImage(snap.data!, width: 110, height: 110),
        ),
      );
    },
  );
}
