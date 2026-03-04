import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/box_service.dart';
import '../services/loyalty_service.dart';
import '../widgets/app_feedback_banner.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<void> _syncHistoryAndLoyalty() async {
    final boxService = context.read<BoxService>();
    final loyalty = context.read<LoyaltyService>();
    await boxService.syncRecentSessions(limit: 100);
    if (!mounted) {
      return;
    }
    await loyalty.syncWithBackendIfAvailable();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHistoryAndLoyalty();
    });
  }

  String _formatTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String _formatAge(DateTime value) {
    final seconds = DateTime.now().difference(value).inSeconds;
    return 'vor ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BoxService>();
    final events = service.allTimelineEvents();
    final backendSessions = service.backendRecentSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Waschhistorie'),
        actions: [
          IconButton(
            tooltip: 'Backend-Historie aktualisieren',
            onPressed: _syncHistoryAndLoyalty,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: events.isEmpty && backendSessions.isEmpty
          ? const Center(child: Text('Noch keine Historie vorhanden.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                if (index < backendSessions.length) {
                  final session = backendSessions[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: CircleAvatar(child: Text('${session.boxNumber}')),
                    title: Text('Session ${session.status}'),
                    subtitle: Text(
                      '${_formatTimestamp(session.startedAt)}'
                      '${session.endedAt == null ? '' : '\nEnde: ${_formatTimestamp(session.endedAt!)}'}',
                    ),
                    trailing: Text(
                      session.amountEuro == null
                          ? '-'
                          : '${session.amountEuro} EUR',
                    ),
                  );
                }
                final event = events[index - backendSessions.length];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(child: Text('${event.boxNumber}')),
                  title: Text(event.title),
                  subtitle: Text(
                    '${_formatTimestamp(event.timestamp)}'
                    '${event.details == null ? '' : '\n${event.details}'}',
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: backendSessions.length + events.length,
            ),
      bottomNavigationBar: service.lastHistorySyncErrorMessage == null
          ? (service.lastHistorySyncAt == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'Backend-Historie: ${_formatAge(service.lastHistorySyncAt!)}',
                      textAlign: TextAlign.center,
                    ),
                  ))
          : Padding(
              padding: const EdgeInsets.all(10),
              child: AppFeedbackBanner(
                title: 'Backend-Historie Fehler',
                message: service.lastHistorySyncErrorMessage!,
                severity: AppFeedbackSeverity.error,
                actionLabel: 'Schliessen',
                onAction: () =>
                    context.read<BoxService>().clearLastHistorySyncError(),
                onDismiss: () =>
                    context.read<BoxService>().clearLastHistorySyncError(),
              ),
            ),
    );
  }
}
