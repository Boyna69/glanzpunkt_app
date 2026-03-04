import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/environment_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _labelForEnvironment(ApiEnvironment environment) {
    switch (environment) {
      case ApiEnvironment.dev:
        return 'Development';
      case ApiEnvironment.stage:
        return 'Staging';
      case ApiEnvironment.prod:
        return 'Production';
    }
  }

  String _labelForRole(AccountRole role) {
    switch (role) {
      case AccountRole.customer:
        return 'customer';
      case AccountRole.operator:
        return 'operator';
      case AccountRole.owner:
        return 'owner';
    }
  }

  String _buildBackendDiagnostics(AuthService auth, EnvironmentService env) {
    final mode = AppConfig.useMockBackend ? 'Mock' : 'Live';
    final sessionState = auth.hasAccount
        ? 'Konto'
        : (auth.isGuest ? 'Gast' : 'Abgemeldet');
    final hasJwt = (auth.backendJwt ?? '').isNotEmpty;
    final userId = auth.backendUserId ?? '-';
    final role = _labelForRole(auth.profileRole);
    return 'Modus: $mode\n'
        'API-Umgebung: ${_labelForEnvironment(env.environment)}\n'
        'Aktive Base URL: ${env.activeBaseUrl}\n'
        'Supabase URL: ${AppConfig.supabaseProjectUrl}\n'
        'API-Key Quelle: ${AppConfig.supabaseApiKeySource}\n'
        'API-Key (maskiert): ${AppConfig.maskedSupabaseApiKey}\n'
        'Session: $sessionState\n'
        'JWT vorhanden: ${hasJwt ? 'ja' : 'nein'}\n'
        'User UUID: $userId\n'
        'Rolle: $role';
  }

  Future<void> _confirmAndDeleteAccount(BuildContext context) async {
    final authService = context.read<AuthService>();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konto loeschen?'),
        content: const Text(
          'Dieser Vorgang loescht dein Konto dauerhaft. Dieser Schritt kann '
          'nicht rueckgaengig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Konto loeschen'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await authService.deleteAccount();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Konto wurde geloescht.')));
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Konto-Loeschung fehlgeschlagen: $e'),
        ),
      );
    }
  }

  Future<void> _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final env = context.watch<EnvironmentService>();
    final analytics = context.watch<AnalyticsService>();
    final recentAnalytics = analytics.recentEvents(limit: 8);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (auth.hasOperatorAccess)
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Betreiber Dashboard'),
                subtitle: const Text(
                  'Monitoring, Quick-Fix und Betriebssteuerung',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, '/operator-dashboard'),
              ),
            )
          else
            Card(
              color: Colors.white10,
              child: const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('System Monitoring (gesperrt)'),
                subtitle: Text(
                  'Nur Betreiber/Inhaber haben Zugriff auf Gesamtdaten.',
                ),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet & Buchungen'),
              subtitle: Text(
                auth.hasAccount
                    ? 'Guthaben, Aufladungen und Buchungen'
                    : 'Nur mit Konto verfuegbar',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: auth.hasAccount,
              onTap: auth.hasAccount
                  ? () => Navigator.pushNamed(context, '/wallet')
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'API-Umgebung',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (AppConfig.useMockBackend)
            const Card(
              color: Colors.orange,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Mock-Backend ist aktiv. Die Auswahl unten beeinflusst den Live-Backend-Flow erst bei USE_MOCK_BACKEND=false.',
                ),
              ),
            ),
          if (kDebugMode)
            RadioGroup<ApiEnvironment>(
              groupValue: env.environment,
              onChanged: (value) {
                if (value != null) {
                  context.read<EnvironmentService>().selectEnvironment(value);
                }
              },
              child: Column(
                children: ApiEnvironment.values.map((item) {
                  return RadioListTile<ApiEnvironment>(
                    value: item,
                    title: Text(_labelForEnvironment(item)),
                    subtitle: Text(AppConfig.baseUrlForEnvironment(item)),
                  );
                }).toList(),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(_labelForEnvironment(env.environment)),
                subtitle: Text(env.activeBaseUrl),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('Backend-Diagnose'),
              subtitle: Text(
                'Quelle: ${AppConfig.supabaseApiKeySource}, '
                'Key: ${AppConfig.maskedSupabaseApiKey}',
              ),
              onTap: () => _showInfoDialog(
                context,
                title: 'Backend-Diagnose',
                message: _buildBackendDiagnostics(auth, env),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Letzte Telemetrie',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (recentAnalytics.isEmpty)
            const Text('Noch keine Events.')
          else
            ...recentAnalytics.map((event) {
              final details = event.properties.entries
                  .map((entry) => '${entry.key}=${entry.value}')
                  .join(', ');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(event.name),
                  subtitle: Text(
                    '${event.timestamp.toIso8601String()}'
                    '${details.isEmpty ? '' : '\n$details'}',
                  ),
                ),
              );
            }),
          if (auth.hasAccount) ...[
            const SizedBox(height: 20),
            const Text(
              'Konto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Card(
              color: Colors.red.shade900.withValues(alpha: 0.35),
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text('Konto loeschen'),
                subtitle: const Text(
                  'Dauerhaftes Entfernen deines Accounts und Profils',
                ),
                onTap: () => _confirmAndDeleteAccount(context),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Rechtliches & Support',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Datenschutz'),
              subtitle: Text(AppConfig.legalPrivacyUrl),
              onTap: () => _showInfoDialog(
                context,
                title: 'Datenschutz',
                message: 'Datenschutzhinweise:\n${AppConfig.legalPrivacyUrl}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Impressum'),
              subtitle: Text(AppConfig.legalImprintUrl),
              onTap: () => _showInfoDialog(
                context,
                title: 'Impressum',
                message: 'Impressum:\n${AppConfig.legalImprintUrl}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Support'),
              subtitle: Text(AppConfig.supportEmail),
              onTap: () => _showInfoDialog(
                context,
                title: 'Support',
                message: 'Kontakt:\n${AppConfig.supportEmail}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
