import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wallet_transaction.dart';
import '../services/auth_service.dart';
import '../services/box_service.dart';
import '../services/loyalty_service.dart';
import '../services/wallet_service.dart';
import '../widgets/app_feedback_banner.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isRefreshing = false;
  bool _isToppingUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing || !mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    final boxService = context.read<BoxService>();
    final loyaltyService = context.read<LoyaltyService>();
    final walletService = context.read<WalletService>();
    if (!auth.hasAccount) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      await auth.refreshProfileAndBalance();
      await boxService.syncRecentSessions(limit: 100);
      await loyaltyService.syncWithBackendIfAvailable();
      await walletService.refresh(limit: 120);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _topUp(int amountEuro) async {
    if (_isToppingUp || _isRefreshing || !mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    if (!auth.hasAccount) {
      return;
    }

    setState(() {
      _isToppingUp = true;
    });
    try {
      final nextBalance = await auth.topUpBalance(amountEuro: amountEuro);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$amountEuro EUR aufgeladen. Neues Guthaben: ${_formatEuro(nextBalance)} EUR',
          ),
        ),
      );
      await context.read<WalletService>().refresh(limit: 120);
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aufladen aktuell nicht moeglich. Bitte in wenigen Sekunden erneut versuchen.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isToppingUp = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yyyy $hh:$min';
  }

  String _formatEuro(num value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  Widget _buildTransactionTile(WalletTransaction tx) {
    final isPositive = tx.amount >= 0;
    final amountText = '${isPositive ? '+' : ''}${_formatEuro(tx.amount)} EUR';
    final amountColor = isPositive ? Colors.greenAccent : Colors.orangeAccent;
    final title = tx.kind == WalletTransactionKind.topUp
        ? 'Aufladung'
        : tx.kind == WalletTransactionKind.charge
        ? 'Waschbuchung'
        : 'Transaktion';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: Icon(
        isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline,
        color: amountColor,
      ),
      title: Text(title),
      subtitle: Text(
        '${_formatDateTime(tx.createdAt)}'
        '${tx.description == null || tx.description!.trim().isEmpty ? '' : '\n${tx.description}'}',
      ),
      trailing: Text(
        amountText,
        style: TextStyle(color: amountColor, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final wallet = context.watch<WalletService>();
    final boxService = context.watch<BoxService>();
    final canTopUp = auth.canTopUpBalance;

    if (!auth.hasAccount) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wallet & Buchungen')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Wallet und Buchungen sind nur mit Konto verfuegbar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/register'),
                  child: const Text('Konto erstellen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final topUps = wallet.topUps;
    final charges = wallet.charges;
    final completedSessions = boxService.backendRecentSessions
        .where((session) => session.endedAt != null)
        .take(20)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet & Buchungen'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _isRefreshing ? null : _refreshAll,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF0F2D52),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aktuelles Guthaben',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatEuro(auth.profileBalanceEuro)} EUR',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    canTopUp
                        ? 'Schnell aufladen (Testmodus)'
                        : auth.isCustomerAccount
                        ? 'Kunden-Aufladung ist aktuell deaktiviert.'
                        : 'Aufladen aktuell nicht verfuegbar.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (canTopUp) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [5, 10, 20].map((amount) {
                        return OutlinedButton(
                          onPressed: _isToppingUp || _isRefreshing
                              ? null
                              : () => _topUp(amount),
                          child: Text('+ $amount EUR'),
                        );
                      }).toList(),
                    ),
                  ],
                  if (_isToppingUp)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (wallet.lastSyncedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Wallet-Sync: ${_formatDateTime(wallet.lastSyncedAt!)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (wallet.lastErrorMessage != null)
            AppFeedbackBanner(
              title: 'Wallet-Sync Fehler',
              message: wallet.lastErrorMessage!,
              severity: AppFeedbackSeverity.error,
              actionLabel: _isRefreshing ? null : 'Erneut laden',
              onAction: _isRefreshing ? null : _refreshAll,
              onDismiss: wallet.clearError,
            ),
          if (wallet.lastErrorMessage != null) const SizedBox(height: 8),
          if (_isRefreshing && wallet.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Letzte Aufladungen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (topUps.isEmpty)
                    const Text(
                      'Keine Aufladungen vorhanden.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else
                    ...topUps.take(8).map(_buildTransactionTile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Letzte Buchungen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (charges.isEmpty)
                    const Text(
                      'Keine Buchungen vorhanden.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else
                    ...charges.take(12).map(_buildTransactionTile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Abgeschlossene Sessions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (completedSessions.isEmpty)
                    const Text(
                      'Noch keine abgeschlossenen Sessions.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else
                    ...completedSessions.map((session) {
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text('${session.boxNumber}'),
                        ),
                        title: Text('Box ${session.boxNumber}'),
                        subtitle: Text(
                          '${_formatDateTime(session.startedAt)}'
                          '${session.endedAt == null ? '' : '\nEnde: ${_formatDateTime(session.endedAt!)}'}',
                        ),
                        trailing: Text(
                          session.amountEuro == null
                              ? '-'
                              : '${session.amountEuro} EUR',
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
