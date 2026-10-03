import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../widgets/common.dart';

/// Edits the PSD-only parts of a portfolio. Business details come from
/// Campus Stay and are shown read-only (also enforced in firestore.rules).
/// The public link (slug) never changes.
class EditPortfolioPage extends StatefulWidget {
  const EditPortfolioPage({super.key, required this.providerId, required this.isAdmin});

  final String providerId;
  final bool isAdmin;

  @override
  State<EditPortfolioPage> createState() => _EditPortfolioPageState();
}

class _EditPortfolioPageState extends State<EditPortfolioPage> {
  late final Future<Portfolio?> _initial = Api.watchPortfolio(widget.providerId).first;

  final _tagline = TextEditingController();
  final _hours = TextEditingController();
  final _email = TextEditingController();
  String? _logoUrl;
  String? _coverUrl;
  List<String> _gallery = [];
  List<ServiceItem> _services = [];
  bool _loaded = false;
  bool _saving = false;
  String? _uploading;

  String get _back => widget.isAdmin ? '/admin/providers/${widget.providerId}' : '/dashboard';

  void _load(Portfolio p) {
    if (_loaded) return;
    _loaded = true;
    _tagline.text = p.tagline;
    _hours.text = p.hours;
    _email.text = p.email;
    _logoUrl = p.logoUrl;
    _coverUrl = p.coverUrl;
    _gallery = [...p.gallery];
    _services = [...p.services];
  }

  @override
  void dispose() {
    _tagline.dispose();
    _hours.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<String?> _pickAndUpload(String kind) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
    if (f == null) return null;
    setState(() => _uploading = kind);
    try {
      return await Api.uploadPortfolioImage(widget.providerId, f, kind);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
      return null;
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.updatePortfolio(widget.providerId, {
        'tagline': _tagline.text.trim(),
        'hours': _hours.text.trim(),
        'email': _email.text.trim(),
        'logoUrl': _logoUrl,
        'coverUrl': _coverUrl,
        'gallery': _gallery,
        'services': _services.map((s) => s.toMap()).toList(),
      });
      if (!mounted) return;
      showSnack(context, 'Portfolio saved — the public page is updated.');
      context.go(_back);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editService(int index) async {
    final result = await showDialog<ServiceItem>(
      context: context,
      builder: (_) => _ServiceDialog(service: _services[index]),
    );
    if (result != null) setState(() => _services[index] = result);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Portfolio?>(
      future: _initial,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) {
          return const Scaffold(body: Center(child: Text('Portfolio not found.')));
        }
        _load(snap.data!);
        final p = snap.data!;
        const gap = SizedBox(height: 14);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go(_back)),
            title: Text('Edit ${p.name}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: _saving || _uploading != null ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Bounded(
              maxWidth: 760,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Public link (never changes)'),
                    subtitle: Text(portfolioUrl(p.slug, campusStay: false)),
                  ),
                ),
                _section('From Campus Stay'),
                _CampusStayDetails(p: p),
                _section('Images'),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  _imageBox('Logo', _logoUrl, 'logo', 110, 110,
                      onPicked: (u) => setState(() => _logoUrl = u),
                      onRemove: () => setState(() => _logoUrl = null)),
                  _imageBox('Cover (defaults to the first Campus Stay photo)', _coverUrl, 'cover', 260, 110,
                      onPicked: (u) => setState(() => _coverUrl = u),
                      onRemove: () => setState(() => _coverUrl = null)),
                ]),
                _section('Extra details'),
                TextFormField(
                  controller: _tagline,
                  decoration: const InputDecoration(
                      labelText: 'Tagline', hintText: 'Fast, affordable laptop repairs on campus'),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: _hours,
                  decoration: const InputDecoration(labelText: 'Working hours', hintText: 'Mon–Sat, 8am–7pm'),
                ),
                gap,
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Business email (shown publicly)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                _section('Services — prices & descriptions'),
                if (_services.isEmpty)
                  Text('No services listed in Campus Stay yet.', style: TextStyle(color: Colors.grey.shade600)),
                for (var i = 0; i < _services.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(_services[i].name),
                        subtitle: Text([
                          if (_services[i].priceFrom != null) 'From GH₵${_services[i].priceFrom}',
                          if (_services[i].description.isNotEmpty) _services[i].description,
                        ].join(' · ').ifEmpty('Tap to add a price or description')),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editService(i),
                      ),
                    ),
                  ),
                _section('Extra gallery photos'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _gallery.length; i++)
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: NetImage(_gallery[i], width: 110, height: 110),
                      ),
                      Positioned(right: 2, top: 2, child: _miniButton(Icons.close, () => setState(() => _gallery.removeAt(i)))),
                    ]),
                  _addBox('gallery', onPicked: (u) => setState(() => _gallery.add(u))),
                ]),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _imageBox(String label, String? url, String kind, double w, double h,
      {required ValueChanged<String> onPicked, required VoidCallback onRemove}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      url == null
          ? _addBox(kind, width: w, height: h, onPicked: onPicked)
          : Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImage(url, width: w, height: h)),
              Positioned(
                right: 2,
                top: 2,
                child: Row(children: [
                  _miniButton(Icons.edit, () async {
                    final u = await _pickAndUpload(kind);
                    if (u != null) onPicked(u);
                  }),
                  const SizedBox(width: 4),
                  _miniButton(Icons.close, onRemove),
                ]),
              ),
            ]),
    ]);
  }

  Widget _miniButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: CircleAvatar(
          radius: 12,
          backgroundColor: Colors.black54,
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );

  Widget _addBox(String kind, {double width = 110, double height = 110, required ValueChanged<String> onPicked}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _uploading != null
          ? null
          : () async {
              final u = await _pickAndUpload(kind);
              if (u != null) onPicked(u);
            },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: _uploading == kind
              ? const CircularProgressIndicator()
              : const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// Read-only summary of what Campus Stay owns.
class _CampusStayDetails extends StatelessWidget {
  const _CampusStayDetails({required this.p});

  final Portfolio p;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ]),
        );
    return Card(
      color: const Color(0xFFF5F3FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          row('Name', p.name),
          row('Category', p.category),
          row('Location', p.location),
          row('Phone', p.phone),
          row('WhatsApp', p.whatsapp),
          row('Services', p.services.map((s) => s.name).join(', ')),
          row('Photos', '${p.csPhotos.length}'),
          row('About', p.description),
          const SizedBox(height: 8),
          Text(
            'These come from Campus Stay. To change them, edit the service in Campus Stay admin → Services. '
            'PSD picks up changes within 30 minutes${p.syncedAt == null ? '' : ' (last synced ${formatDateTime(p.syncedAt)})'}.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({required this.service});

  final ServiceItem service;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final _desc = TextEditingController(text: widget.service.description);
  late final _price = TextEditingController(text: widget.service.priceFrom?.toString());
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.service.name),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _desc,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Short description (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Starting price in GH₵ (optional)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) =>
                    (v ?? '').trim().isEmpty || num.tryParse(v!.trim()) != null ? null : 'Enter a number',
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                context,
                ServiceItem(
                  id: widget.service.id,
                  name: widget.service.name,
                  description: _desc.text.trim(),
                  priceFrom: num.tryParse(_price.text.trim()),
                ),
              );
            },
            child: const Text('Done'),
          ),
        ],
      );
}
