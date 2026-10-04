import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/portfolio.dart';
import '../widgets/common.dart';

const _maxPhotos = 3;
const _otherServiceId = 'other';

/// Form a student fills in to request a service from one provider.
class ServiceRequestPage extends StatefulWidget {
  const ServiceRequestPage({super.key, required this.slug, this.source, this.serviceId});

  final String slug;
  final String? source;
  final String? serviceId;

  @override
  State<ServiceRequestPage> createState() => _ServiceRequestPageState();
}

class _ServiceRequestPageState extends State<ServiceRequestPage> {
  late final Future<Portfolio?> _future = Api.portfolioBySlug(widget.slug);

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  String? _serviceId;
  DateTime? _date;
  TimeOfDay? _time;
  final List<XFile> _photos = [];

  bool _busy = false;
  String? _error;
  String? _submittedRef;

  CampusStayStudent? _student;
  bool _lookingUp = false;
  String? _lookupMessage;

  Future<void> _fillFromCampusStay() async {
    setState(() {
      _lookingUp = true;
      _lookupMessage = null;
    });
    try {
      final s = await Api.campusStayProfile();
      setState(() {
        _student = s;
        if (s.name.isNotEmpty) _name.text = s.name;
        if (s.phone.isNotEmpty) _phone.text = s.phone;
        if (s.email.isNotEmpty) _email.text = s.email;
        if (_location.text.trim().isEmpty) _location.text = s.hostel.isNotEmpty ? s.hostel : s.school;
      });
    } on FirebaseAuthException catch (e) {
      if (e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request') {
        setState(() => _lookupMessage = friendlyError(e));
      }
    } catch (e) {
      setState(() => _lookupMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _forgetCampusStay() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _student = null;
      _lookupMessage = null;
    });
  }

  Widget _campusStayCard() {
    const purple = Color(0xFF7C3AED);
    final s = _student;
    return Card(
      color: const Color(0xFFF5F3FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: s != null
            ? Row(
                children: [
                  const Icon(Icons.verified, color: purple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Using your Campus Stay account — ${s.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (s.school.isNotEmpty || s.hostel.isNotEmpty)
                          Text(
                            [s.school, s.hostel].where((x) => x.isNotEmpty).join(' · '),
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _forgetCampusStay, child: const Text('Not you?')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Have a Campus Stay account?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    "Fill in your details automatically and show the provider you're a verified student.",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _lookingUp ? null : _fillFromCampusStay,
                    icon: _lookingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.school_outlined),
                    label: const Text('Fill in from my Campus Stay account (Google)'),
                  ),
                  if (_lookupMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_lookupMessage!, style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
                  ],
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _location, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(_maxPhotos - _photos.length));
    });
  }

  Future<void> _submit(Portfolio p) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final preferredTime = _time == null ? '' : _time!.format(context);
    try {
      final uploads = await Api.uploadRequestPhotos(_photos);
      final ref = await Api.submitRequest({
        'providerId': p.id,
        'serviceId': _serviceId,
        'studentName': _name.text.trim(),
        'studentPhone': _phone.text.trim(),
        'studentEmail': _email.text.trim(),
        'location': _location.text.trim(),
        'preferredDate': _date == null ? '' : DateFormat('yyyy-MM-dd').format(_date!),
        'preferredTime': preferredTime,
        'description': _description.text.trim(),
        'uploads': uploads,
        'source': widget.source ?? 'direct',
      });
      setState(() => _submittedRef = ref);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        if (p == null) {
          return const Scaffold(body: Center(child: Text('This service is not available right now.')));
        }
        _serviceId ??= p.services.any((s) => s.id == widget.serviceId)
            ? widget.serviceId
            : (p.services.isNotEmpty ? p.services.first.id : _otherServiceId);

        return Scaffold(
          appBar: AppBar(
            title: Text('Request — ${p.name}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(
                      Uri(
                        path: '/p/${widget.slug}',
                        queryParameters: widget.source == null ? null : {'source': widget.source},
                      ).toString(),
                    ),
            ),
          ),
          body: SingleChildScrollView(
            child: Bounded(maxWidth: 640, child: _submittedRef != null ? _success(p) : _formView(p)),
          ),
        );
      },
    );
  }

  Widget _success(Portfolio p) {
    final wa = whatsappLink(
      p.whatsapp.isNotEmpty ? p.whatsapp : p.phone,
      text: 'Hi ${p.name}, I just sent service request $_submittedRef via Campus Stay Ghana.',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 64),
            const SizedBox(height: 12),
            Text('Request sent!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Your reference number is', style: TextStyle(color: Colors.grey.shade700)),
            SelectableText(
              _submittedRef!,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '${p.name} has received your request and will contact you on ${_phone.text.trim()}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (wa != null)
              FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_outlined),
                label: Text('Message ${p.name} on WhatsApp'),
              ),
            TextButton(
              onPressed: () => context.go(
                Uri(
                  path: '/p/${widget.slug}',
                  queryParameters: widget.source == null ? null : {'source': widget.source},
                ).toString(),
              ),
              child: const Text('Back to portfolio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView(Portfolio p) {
    const gap = SizedBox(height: 14);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _campusStayCard(),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _serviceId,
            decoration: const InputDecoration(labelText: 'What do you need?'),
            items: [
              for (final s in p.services) DropdownMenuItem(value: s.id, child: Text(s.name)),
              const DropdownMenuItem(value: _otherServiceId, child: Text('Something else')),
            ],
            onChanged: (v) => setState(() => _serviceId = v),
          ),
          gap,
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Describe what you need',
              hintText: 'e.g. My HP laptop turns off after 10 minutes',
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            maxLength: 1000,
            validator: (v) => (v ?? '').trim().length < 5 ? 'Please describe what you need' : null,
          ),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Your name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
          ),
          gap,
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone / WhatsApp number', hintText: '024 123 4567'),
            keyboardType: TextInputType.phone,
            validator: (v) =>
                (v ?? '').replaceAll(RegExp(r'\D'), '').length < 9 ? 'Enter a valid phone number' : null,
          ),
          gap,
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || t.contains('@') ? null : 'Enter a valid email';
            },
          ),
          gap,
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Your location',
              hintText: 'e.g. KNUST, Unity Hall / Ayeduase',
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter where you are' : null,
          ),
          gap,
          LayoutBuilder(
            builder: (context, c) {
              final date = OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_date == null ? 'Preferred date' : DateFormat('EEE d MMM').format(_date!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 90)),
                    initialDate: _date ?? now,
                  );
                  if (d != null) setState(() => _date = d);
                },
              );
              final time = OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(_time == null ? 'Preferred time' : _time!.format(context)),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
                  );
                  if (t != null) setState(() => _time = t);
                },
              );
              if (c.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [date, const SizedBox(height: 10), time],
                );
              }
              return Row(
                children: [
                  Expanded(child: date),
                  const SizedBox(width: 10),
                  Expanded(child: time),
                ],
              );
            },
          ),
          gap,
          Text('Photos (optional, up to $_maxPhotos)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: NetImage(_photos[i].path, width: 84, height: 84),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_photos.length < _maxPhotos)
                InkWell(
                  onTap: _pickPhotos,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            gap,
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _submit(p),
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send request'),
          ),
          const SizedBox(height: 8),
          Text(
            'Your name and phone number are shared only with ${p.name} so they can contact you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
