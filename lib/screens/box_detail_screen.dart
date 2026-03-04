import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/box.dart';
import '../services/backend_error_message_service.dart';
import '../services/box_service.dart';
import '../services/wash_backend_gateway.dart';
import '../widgets/app_feedback_banner.dart';

class BoxDetailScreen extends StatefulWidget {
  final int boxNumber;

  const BoxDetailScreen({super.key, required this.boxNumber});

  @override
  State<BoxDetailScreen> createState() => _BoxDetailScreenState();
}

class _BoxDetailScreenState extends State<BoxDetailScreen> {
  bool _isStopping = false;
  String? _persistentErrorMessage;

  String _formatAge(DateTime timestamp) {
    final seconds = DateTime.now().difference(timestamp).inSeconds;
    return 'vor ${seconds}s';
  }

  String _mapBackendErrorToUiMessage(BackendGatewayException e) {
    return BackendErrorMessageService.mapForBoxDetail(e);
  }

  String _remainingLabelForState(BoxState state) {
    switch (state) {
      case BoxState.cleaning:
        return 'Reinigungszeit';
      case BoxState.active:
        return 'Restzeit';
      case BoxState.available:
      case BoxState.reserved:
      case BoxState.outOfService:
        return 'Zeit';
    }
  }

  String _remainingValueForBox(WashBox box) {
    final remainingSeconds =
        box.remainingSeconds ??
        (box.remainingMinutes == null ? null : box.remainingMinutes! * 60);
    if (remainingSeconds == null) {
      return '-';
    }
    final formatted = _formatDuration(remainingSeconds);
    if (box.state == BoxState.active) {
      return 'noch $formatted';
    }
    if (box.state == BoxState.cleaning) {
      return 'endet in $formatted';
    }
    return formatted;
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutesPart = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  Future<void> _refreshBox() async {
    try {
      await context.read<BoxService>().refreshBoxStatus(widget.boxNumber);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _persistentErrorMessage = 'Status konnte nicht geladen werden: $e';
      });
    }
  }

  Future<void> _stopSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session stoppen?'),
        content: const Text(
          'Die aktive Session dieser Box wird sofort beendet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stoppen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _isStopping = true;
    });

    try {
      await context.read<BoxService>().stopActiveSession(widget.boxNumber);
      if (!mounted) {
        return;
      }
      setState(() {
        _persistentErrorMessage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Session wurde gestoppt')));
    } on BackendGatewayException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _persistentErrorMessage = _mapBackendErrorToUiMessage(e);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _persistentErrorMessage = 'Session konnte nicht gestoppt werden: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStopping = false;
        });
      }
    }
  }

  Future<void> _clearTimeline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Timeline leeren?'),
        content: const Text(
          'Alle Timeline-Events dieser Box werden dauerhaft entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await context.read<BoxService>().clearTimelineForBox(widget.boxNumber);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BoxService>();
    final box = service.getBoxByNumber(widget.boxNumber);
    final timeline = service.timelineForBox(widget.boxNumber);

    if (box == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Box ${widget.boxNumber}')),
        body: const Center(child: Text('Box nicht gefunden')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Box ${box.number}'),
        actions: [
          IconButton(
            onPressed: _refreshBox,
            icon: const Icon(Icons.refresh),
            tooltip: 'Status aktualisieren',
          ),
          IconButton(
            onPressed: _clearTimeline,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Timeline leeren',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_persistentErrorMessage != null)
            AppFeedbackBanner(
              title: 'Box-Fehler',
              message: _persistentErrorMessage!,
              severity: AppFeedbackSeverity.error,
              actionLabel: 'Schliessen',
              onAction: () {
                setState(() {
                  _persistentErrorMessage = null;
                });
              },
              onDismiss: () {
                setState(() {
                  _persistentErrorMessage = null;
                });
              },
            ),
          if (_persistentErrorMessage != null) const SizedBox(height: 8),
          if (box.state == BoxState.active)
            ElevatedButton.icon(
              onPressed: _isStopping ? null : _stopSession,
              icon: _isStopping
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: const Text('Aktive Session stoppen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          if (box.state == BoxState.active) const SizedBox(height: 10),
          if (box.state == BoxState.cleaning)
            Card(
              color: Colors.orange.shade900,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Box wird gereinigt. Start ist moeglich, sobald die Reinigung beendet ist.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (box.state == BoxState.cleaning) const SizedBox(height: 10),
          _DetailRow(label: 'Status', value: box.state.label),
          _DetailRow(
            label: _remainingLabelForState(box.state),
            value: _remainingValueForBox(box),
          ),
          _DetailRow(
            label: 'Session gestartet',
            value: box.sessionStartedAt == null
                ? '-'
                : _formatAge(box.sessionStartedAt!),
          ),
          _DetailRow(
            label: 'Backend-Update',
            value: box.lastBackendUpdateAt == null
                ? '-'
                : _formatAge(box.lastBackendUpdateAt!),
          ),
          _DetailRow(
            label: 'Globaler Sync',
            value: service.lastSuccessfulSyncAt == null
                ? '-'
                : _formatAge(service.lastSuccessfulSyncAt!),
          ),
          _DetailRow(
            label: 'Sync-Fehler',
            value: service.lastSyncErrorMessage ?? '-',
          ),
          const SizedBox(height: 10),
          const Text(
            'Session Timeline',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Noch keine Events vorhanden.'),
              ),
            ),
          ...timeline.map((event) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatAge(event.timestamp),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (event.details != null) ...[
                      const SizedBox(height: 4),
                      Text(event.details!),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(flex: 3, child: Text(value)),
          ],
        ),
      ),
    );
  }
}
