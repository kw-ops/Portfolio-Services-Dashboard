import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/session.dart';
import '../auth/login_page.dart';
import '../config.dart';

final _dateTime = DateFormat('d MMM yyyy, h:mm a');

/// Phone-sized screen (below a typical tablet width).
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;
String formatDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);

/// The PSD platform mark. Providers keep their own logos; this is PSD's.
class PsdLogo extends StatelessWidget {
  const PsdLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/psd_logo.svg',
    width: size,
    height: size,
    semanticsLabel: 'PSD logo',
  );
}

/// Network image that still renders when the Storage bucket has no CORS
/// config (falls back to an <img> element on web).
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height});

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    errorBuilder: (_, _, _) => Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
    ),
  );
}

/// Centers content and caps its width on large screens.
class Bounded extends StatelessWidget {
  const Bounded({super.key, required this.child, this.maxWidth = 1000, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding ?? EdgeInsets.all(isCompact(context) ? 12 : 16), child: child),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final campus = source == kSourceCampusStay;
    final c = campus ? const Color(0xFF7C3AED) : Colors.blueGrey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(campus ? Icons.school_outlined : Icons.link, size: 14, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            sourceLabel(source),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color, this.onTap});

  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                style:
                    (isCompact(context)
                            ? Theme.of(context).textTheme.headlineSmall
                            : Theme.of(context).textTheme.headlineMedium)
                        ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Lays out [StatTile]s in equal columns that fit the available width:
/// 2 per row on phones, more on tablets and desktops.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 12.0;
      final cols = (c.maxWidth / 170).floor().clamp(2, children.length);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in children) SizedBox(width: w, child: t)],
      );
    },
  );
}

void showSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

Future<void> copyText(BuildContext context, String text, {String label = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, label);
}

/// Shows the child only to a signed-in user with [role]; otherwise shows the
/// login form (or a no-access message) in place.
class RoleGate extends StatelessWidget {
  const RoleGate({super.key, required this.role, required this.builder});

  final String role;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (!session.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (!session.signedIn) return const LoginPage(stayHere: true);
      final allowed = role == 'admin' ? session.isAdmin : session.isProvider;
      if (!allowed) return const _NoAccess();
      return builder(context);
    },
  );
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'This account (${session.user?.email}) has no access to this page.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (session.isAdmin)
                  FilledButton(onPressed: () => context.go('/admin'), child: const Text('Go to admin')),
                if (session.isProvider)
                  FilledButton(
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Go to dashboard'),
                  ),
                OutlinedButton(onPressed: session.signOut, child: const Text('Sign out')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// App bar actions shared by admin and provider screens.
List<Widget> accountActions(BuildContext context) => [
  if (session.profile != null && !isCompact(context))
    Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: Text(session.user?.email ?? '', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
      ),
    ),
  IconButton(
    tooltip: 'Sign out',
    icon: const Icon(Icons.logout),
    onPressed: () async {
      await session.signOut();
      if (context.mounted) context.go('/login');
    },
  ),
];
