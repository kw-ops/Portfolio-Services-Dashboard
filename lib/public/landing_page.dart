import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root page. Students normally arrive straight on a portfolio link from
/// Campus Stay, so this only explains where to go and offers staff sign-in.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Campus Stay Services',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find trusted student services — laptop repairs, hairdressers, drivers and more — '
                  'in the Services section of the Campus Stay Ghana app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.login),
                  label: const Text('Service provider / admin sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
