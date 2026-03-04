import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class OperatorAccessGuard extends StatelessWidget {
  final Widget child;
  final String title;

  const OperatorAccessGuard({
    super.key,
    required this.child,
    this.title = 'Bereich gesperrt',
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.hasOperatorAccess) {
      return child;
    }

    final hint = auth.isLoggedIn && !auth.isGuest
        ? 'Nur Betreiber/Inhaber haben Zugriff auf diesen Bereich.'
        : 'Bitte mit einem Betreiberkonto anmelden.';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Kein Zugriff',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                  (_) => false,
                ),
                child: const Text('Zur Startseite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
