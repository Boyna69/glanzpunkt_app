import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_config.dart';
import '../services/auth_service.dart';
import '../services/backend_http_client.dart';
import '../services/box_service.dart';
import '../services/environment_service.dart';
import '../services/loyalty_service.dart';
import '../services/ops_maintenance_service.dart';
import '../models/box.dart';
import '../widgets/app_feedback_banner.dart';
import 'start_wash_screen.dart';
import 'box_detail_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool autoSyncOnOpen;

  const HomeScreen({super.key, this.autoSyncOnOpen = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _didInitialSync = false;
  bool _isApplyingQuickFix = false;
  late final OpsMaintenanceService _opsMaintenance;

  @override
  void initState() {
    super.initState();
    final apiKey = AppConfig.supabaseApiKey;
    final opsClient = createBackendHttpClient(
      defaultHeaders: <String, String>{
        if (apiKey.isNotEmpty) ...{
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
        },
        'x-client-info': 'glanzpunkt_app/1.0',
      },
    );
    _opsMaintenance = OpsMaintenanceService(httpClient: opsClient);
  }

  bool get _isWidgetTestBinding => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.autoSyncOnOpen || _isWidgetTestBinding) {
      return;
    }
    if (_didInitialSync) {
      return;
    }
    _didInitialSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final boxService = context.read<BoxService>();
      await boxService.refreshBoxesReadOnly();
      await boxService.syncRecentSessions(limit: 100);
      if (!mounted) {
        return;
      }
      await context.read<LoyaltyService>().syncWithBackendIfAvailable();
    });
  }

  String _buildSyncLabel(BoxService service) {
    if (service.isSyncInProgress) {
      return 'Sync laeuft...';
    }
    if (service.lastSyncErrorMessage != null) {
      return 'Sync-Fehler';
    }
    final lastSync = service.lastSuccessfulSyncAt;
    if (lastSync == null) {
      return 'Noch kein Sync';
    }
    final seconds = DateTime.now().difference(lastSync).inSeconds;
    return 'Zuletzt vor ${seconds}s';
  }

  Future<void> _runQuickFixFromHome() async {
    if (_isApplyingQuickFix || !mounted) {
      return;
    }

    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick-Fix ist nur fuer Betreiber/Inhaber verfuegbar.'),
        ),
      );
      return;
    }

    setState(() {
      _isApplyingQuickFix = true;
    });

    try {
      final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
      final result = await _opsMaintenance.runExpireActiveSessions(
        baseUrl: baseUrl,
        jwt: jwt,
      );

      if (!mounted) {
        return;
      }

      await context.read<BoxService>().refreshBoxesReadOnly();
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quick-Fix: ${result.expiredReservations} stale geloescht, '
            '${result.releasedReservedBoxes} Boxen freigegeben.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Quick-Fix fehlgeschlagen: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingQuickFix = false;
        });
      }
    }
  }

  Future<void> _confirmAndRunQuickFixFromHome() async {
    if (_isApplyingQuickFix || !mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick-Fix ausfuehren?'),
        content: const Text(
          'Es werden abgelaufene Reservierungen bereinigt und haengende '
          'reserved-Boxen freigegeben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ausfuehren'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runQuickFixFromHome();
    }
  }

  _SyncChannelInfo _buildSyncChannelInfo(BoxService service) {
    if (!service.hasRealtimeStream) {
      return const _SyncChannelInfo(
        label: 'Datenkanal: Polling (5s)',
        color: Colors.white54,
        icon: Icons.sync,
      );
    }

    if (service.isRealtimeLive) {
      final lastRealtime = service.lastRealtimeEventAt;
      final liveAge = lastRealtime == null
          ? ''
          : ' (${_formatAge(lastRealtime)})';
      return _SyncChannelInfo(
        label: 'Datenkanal: Live (Realtime)$liveAge',
        color: Colors.greenAccent.shade200,
        icon: Icons.bolt,
      );
    }

    if (service.lastRealtimeErrorMessage != null) {
      return const _SyncChannelInfo(
        label: 'Datenkanal: Polling-Fallback (Realtime-Fehler)',
        color: Colors.orangeAccent,
        icon: Icons.warning_amber,
      );
    }

    return const _SyncChannelInfo(
      label: 'Datenkanal: Realtime bereit, Polling aktiv',
      color: Colors.lightBlueAccent,
      icon: Icons.wifi_tethering,
    );
  }

  String _formatAge(DateTime timestamp) {
    final seconds = DateTime.now().difference(timestamp).inSeconds;
    return 'vor ${seconds}s';
  }

  String _buildBoxDurationText(WashBox box) {
    final remainingSeconds =
        box.remainingSeconds ??
        (box.remainingMinutes == null ? null : box.remainingMinutes! * 60);
    if (remainingSeconds == null) {
      return '';
    }
    return '\n${_formatDuration(remainingSeconds)}';
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutesPart = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  int _displayPriorityForState(BoxState state) {
    switch (state) {
      case BoxState.available:
        return 0;
      case BoxState.active:
      case BoxState.cleaning:
        return 1;
      case BoxState.reserved:
        return 2;
      case BoxState.outOfService:
        return 3;
    }
  }

  int _secondsUntilAvailableForDisplay(WashBox box) {
    if (box.state == BoxState.available) {
      return 0;
    }
    final remaining =
        box.remainingSeconds ??
        (box.remainingMinutes == null ? null : box.remainingMinutes! * 60);
    if (remaining != null) {
      return remaining < 0 ? 0 : remaining;
    }
    switch (box.state) {
      case BoxState.reserved:
        return 60 * 60;
      case BoxState.outOfService:
        return 24 * 60 * 60;
      case BoxState.active:
      case BoxState.cleaning:
      case BoxState.available:
        return 0;
    }
  }

  List<WashBox> _sortedBoxesForDisplay(List<WashBox> boxes) {
    final sorted = List<WashBox>.from(boxes);
    sorted.sort((a, b) {
      final priorityCompare = _displayPriorityForState(
        a.state,
      ).compareTo(_displayPriorityForState(b.state));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      final etaCompare = _secondsUntilAvailableForDisplay(
        a,
      ).compareTo(_secondsUntilAvailableForDisplay(b));
      if (etaCompare != 0) {
        return etaCompare;
      }
      return a.number.compareTo(b.number);
    });
    return sorted;
  }

  String _boxAvailabilityHint(WashBox box) {
    switch (box.state) {
      case BoxState.available:
        return 'Jetzt verfuegbar';
      case BoxState.active:
        return 'In Benutzung';
      case BoxState.cleaning:
        return 'Reinigung laeuft';
      case BoxState.reserved:
        return 'Aktuell reserviert';
      case BoxState.outOfService:
        return 'Derzeit ausser Betrieb';
    }
  }

  String? _buildNextBestBoxMessage(List<WashBox> boxes) {
    if (boxes.isEmpty) {
      return null;
    }
    final next = boxes.first;
    if (next.state == BoxState.outOfService) {
      return 'Aktuell ist keine Box verfuegbar.';
    }
    if (next.state == BoxState.available) {
      return 'Empfehlung: Box ${next.number} ist sofort verfuegbar.';
    }
    final etaSeconds = _secondsUntilAvailableForDisplay(next);
    if (etaSeconds > 0 && etaSeconds < 24 * 60 * 60) {
      return 'Naechste freie Box: ${next.number} in ca. ${_formatDuration(etaSeconds)}.';
    }
    return 'Naechste freie Box: ${next.number}';
  }

  Future<void> _openLoyalty(BuildContext context) async {
    final auth = context.read<AuthService>();
    if (auth.hasAccount) {
      Navigator.pushNamed(context, '/loyalty');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stempelkarte nur mit Konto'),
        content: const Text(
          'Bitte erstelle ein Konto, um die Loyalty-Funktionen zu nutzen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Spaeter'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/register');
            },
            child: const Text('Konto erstellen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxService = context.watch<BoxService>();
    final authService = context.watch<AuthService>();
    final boxes = boxService.boxes;
    final sortedBoxes = _sortedBoxesForDisplay(boxes);
    final nextBestBoxMessage = _buildNextBestBoxMessage(sortedBoxes);
    final recentEvents = boxService.recentTimelineEvents(limit: 3);

    return Scaffold(
      appBar: AppBar(
        title: Text('Glanzpunkt Boxen - ${authService.displayName}'),
        actions: [
          IconButton(
            onPressed: () {
              context.read<AuthService>().logout();
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
          ),
          IconButton(
            onPressed: () async {
              await context.read<BoxService>().refreshBoxesReadOnly();
            },
            icon: const Icon(Icons.sync),
            tooltip: 'Jetzt synchronisieren',
          ),
          IconButton(
            onPressed: () => _openLoyalty(context),
            icon: const Icon(Icons.card_giftcard),
            tooltip: 'Stempelkarte',
          ),
          IconButton(
            onPressed: () {
              Navigator.pushNamed(context, '/wallet');
            },
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Wallet',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
            tooltip: 'Waschhistorie',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StartWashScreen()),
              );
            },
            icon: const Icon(Icons.play_circle_fill),
            tooltip: 'Waschvorgang starten',
          ),
          if (authService.hasOperatorAccess)
            PopupMenuButton<_HomeMenuAction>(
              tooltip: 'Mehr',
              onSelected: (action) {
                switch (action) {
                  case _HomeMenuAction.operatorDashboard:
                    Navigator.pushNamed(context, '/operator-dashboard');
                    break;
                  case _HomeMenuAction.quickFixNow:
                    _confirmAndRunQuickFixFromHome();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<_HomeMenuAction>(
                  value: _HomeMenuAction.operatorDashboard,
                  child: Row(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Betreiber Dashboard'),
                    ],
                  ),
                ),
                PopupMenuItem<_HomeMenuAction>(
                  value: _HomeMenuAction.quickFixNow,
                  enabled: !_isApplyingQuickFix,
                  child: Row(
                    children: [
                      Icon(
                        Icons.build_circle_outlined,
                        size: 18,
                        color: _isApplyingQuickFix
                            ? Colors.white38
                            : Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isApplyingQuickFix
                            ? 'Quick-Fix laeuft...'
                            : 'Quick-Fix jetzt',
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (boxService.lastSyncErrorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AppFeedbackBanner(
                title: 'Backend-Fehler',
                message: boxService.lastSyncErrorMessage!,
                severity: AppFeedbackSeverity.error,
                actionLabel: 'Schliessen',
                onAction: () => context.read<BoxService>().clearLastSyncError(),
                onDismiss: () =>
                    context.read<BoxService>().clearLastSyncError(),
              ),
            ),
          Container(
            width: double.infinity,
            color: Colors.white10,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _buildSyncLabel(boxService),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final info = _buildSyncChannelInfo(boxService);
                    return Row(
                      children: [
                        Icon(info.icon, size: 16, color: info.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            info.label,
                            style: TextStyle(color: info.color),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _KpiChip(label: 'Gesamt', value: '${boxService.totalBoxCount}'),
                _KpiChip(
                  label: 'Frei',
                  value: '${boxService.availableBoxCount}',
                ),
                _KpiChip(label: 'Aktiv', value: '${boxService.activeBoxCount}'),
                _KpiChip(
                  label: 'Reinigung',
                  value: '${boxService.cleaningBoxCount}',
                ),
                _KpiChip(
                  label: 'Auslastung',
                  value: '${boxService.occupancyPercent}%',
                ),
              ],
            ),
          ),
          if (authService.isGuest)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.teal.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Du nutzt die App als Gast. Erstelle ein Konto, um deine Historie und Vorteile zu speichern.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/register');
                        },
                        child: const Text('Konto erstellen'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (nextBestBoxMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.lightBlue.shade900.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(Icons.timeline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nextBestBoxMessage,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (recentEvents.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.white10,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Letzte Ereignisse',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      ...recentEvents.map((event) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Box ${event.boxNumber}: ${event.title} (${_formatAge(event.timestamp)})',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: boxes.isEmpty
                ? const Center(
                    child: Text(
                      'Keine Boxen verfuegbar',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: sortedBoxes.length,
                    itemBuilder: (context, index) {
                      final box = sortedBoxes[index];

                      Color color;
                      switch (box.state) {
                        case BoxState.available:
                          color = Colors.green;
                          break;
                        case BoxState.reserved:
                          color = Colors.blueGrey;
                          break;
                        case BoxState.active:
                          color = Colors.red;
                          break;
                        case BoxState.cleaning:
                          color = Colors.orange;
                          break;
                        case BoxState.outOfService:
                          color = Colors.grey.shade700;
                          break;
                      }

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BoxDetailScreen(boxNumber: box.number),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Card(
                          color: color,
                          child: Center(
                            child: Text(
                              'Box ${box.number}\n'
                              '${_boxAvailabilityHint(box)}'
                              '${_buildBoxDurationText(box)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;

  const _KpiChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.white70),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncChannelInfo {
  final String label;
  final Color color;
  final IconData icon;

  const _SyncChannelInfo({
    required this.label,
    required this.color,
    required this.icon,
  });
}

enum _HomeMenuAction { operatorDashboard, quickFixNow }
