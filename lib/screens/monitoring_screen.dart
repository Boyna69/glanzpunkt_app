import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_service.dart';
import '../services/backend_http_client.dart';
import '../services/environment_service.dart';
import '../services/ops_maintenance_service.dart';
import '../widgets/app_feedback_banner.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  static const Duration _refreshInterval = Duration(seconds: 10);

  late final BackendHttpClient _client;
  late final OpsMaintenanceService _opsMaintenance;
  Timer? _timer;
  bool _isLoading = false;
  bool _isApplyingQuickFix = false;
  String? _error;
  DateTime? _lastUpdatedAt;
  _MonitoringSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    final apiKey = AppConfig.supabaseApiKey;
    _client = createBackendHttpClient(
      defaultHeaders: <String, String>{
        if (apiKey.isNotEmpty) ...{
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
        },
        'x-client-info': 'glanzpunkt_app/1.0',
      },
    );
    _opsMaintenance = OpsMaintenanceService(httpClient: _client);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSnapshot();
    });
    _timer = Timer.periodic(_refreshInterval, (_) {
      _loadSnapshot();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSnapshot() async {
    if (_isLoading || !mounted) {
      return;
    }

    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      setState(() {
        _error = 'Monitoring ist nur fuer Betreiber/Inhaber verfuegbar.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
      final uri = Uri.parse('$baseUrl/rest/v1/rpc/monitoring_snapshot');
      final response = await _client.postJson(
        uri,
        const <String, dynamic>{},
        headers: <String, String>{'Authorization': 'Bearer $jwt'},
      );

      if (response.statusCode < 200 || response.statusCode > 299) {
        final message = response.body is Map
            ? (response.body as Map)['message'] as String?
            : null;
        throw StateError(
          message ??
              'Monitoring laden fehlgeschlagen (HTTP ${response.statusCode})',
        );
      }

      if (response.body is! Map) {
        throw const BackendHttpException(
          kind: BackendHttpErrorKind.invalidResponse,
          message: 'Monitoring-Response ist kein JSON-Objekt.',
        );
      }

      final snapshot = _MonitoringSnapshot.fromJson(
        Map<String, dynamic>.from(response.body as Map),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _lastUpdatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatAge(DateTime timestamp) {
    final seconds = DateTime.now().difference(timestamp).inSeconds;
    return 'vor ${seconds}s';
  }

  String _formatDateTime(DateTime timestamp) {
    final t = timestamp.toLocal();
    final dd = t.day.toString().padLeft(2, '0');
    final mm = t.month.toString().padLeft(2, '0');
    final yyyy = t.year.toString();
    final hh = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    final sec = t.second.toString().padLeft(2, '0');
    return '$dd.$mm.$yyyy $hh:$min:$sec';
  }

  String _formatEuro(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} EUR';
  }

  _OpsHealth _opsHealth(_MonitoringSnapshot snapshot) {
    if (snapshot.sessionsWithNullBox > 0 || snapshot.staleReservations >= 3) {
      return _OpsHealth.critical;
    }
    if (snapshot.staleReservations > 0) {
      return _OpsHealth.warning;
    }
    return _OpsHealth.ok;
  }

  Color _opsHealthColor(_OpsHealth health) {
    switch (health) {
      case _OpsHealth.ok:
        return Colors.green.shade700;
      case _OpsHealth.warning:
        return Colors.orange.shade700;
      case _OpsHealth.critical:
        return Colors.red.shade700;
    }
  }

  String _opsHealthLabel(_OpsHealth health) {
    switch (health) {
      case _OpsHealth.ok:
        return 'Gruen - stabil';
      case _OpsHealth.warning:
        return 'Gelb - beobachten';
      case _OpsHealth.critical:
        return 'Rot - Eingriff noetig';
    }
  }

  IconData _opsHealthIcon(_OpsHealth health) {
    switch (health) {
      case _OpsHealth.ok:
        return Icons.check_circle;
      case _OpsHealth.warning:
        return Icons.warning_amber;
      case _OpsHealth.critical:
        return Icons.error;
    }
  }

  bool _hasOpsIssues(_MonitoringSnapshot snapshot) {
    return snapshot.staleReservations > 0 || snapshot.sessionsWithNullBox > 0;
  }

  String _opsHealthDetails(_MonitoringSnapshot snapshot, _OpsHealth health) {
    switch (health) {
      case _OpsHealth.ok:
        return 'Keine stale Reservations und keine Sessions ohne Boxzuordnung.';
      case _OpsHealth.warning:
        return 'Auffaellig: ${snapshot.staleReservations} stale Reservations.';
      case _OpsHealth.critical:
        return 'Kritisch: ${snapshot.staleReservations} stale Reservations, '
            '${snapshot.sessionsWithNullBox} Sessions ohne Boxzuordnung.';
    }
  }

  Widget _buildOpsStatusCard(_MonitoringSnapshot snapshot, _OpsHealth health) {
    final accent = _opsHealthColor(health);
    final hasIssues = _hasOpsIssues(snapshot);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 1.2),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_opsHealthIcon(health), color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Betriebsstatus: ${_opsHealthLabel(health)}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TrafficLamp(
                  label: 'Gruen',
                  color: Colors.green.shade600,
                  isActive: health == _OpsHealth.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TrafficLamp(
                  label: 'Gelb',
                  color: Colors.orange.shade600,
                  isActive: health == _OpsHealth.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TrafficLamp(
                  label: 'Rot',
                  color: Colors.red.shade600,
                  isActive: health == _OpsHealth.critical,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _opsHealthDetails(snapshot, health),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_isApplyingQuickFix || _isLoading || !hasIssues)
                ? null
                : _confirmAndRunQuickFix,
            icon: _isApplyingQuickFix
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.build_circle),
            label: Text(
              _isApplyingQuickFix
                  ? 'Quick-Fix laeuft...'
                  : hasIssues
                  ? 'Quick-Fix ausfuehren'
                  : 'Keine Aktion noetig',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runQuickFix() async {
    if (_isApplyingQuickFix || !mounted) {
      return;
    }

    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      setState(() {
        _error = 'Quick-Fix ist nur fuer Betreiber/Inhaber verfuegbar.';
      });
      return;
    }

    setState(() {
      _isApplyingQuickFix = true;
      _error = null;
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quick-Fix ausgefuehrt: '
            '${result.expiredReservations} stale Reservations geloescht, '
            '${result.releasedReservedBoxes} reservierte Boxen freigegeben.',
          ),
        ),
      );
      await _loadSnapshot();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Quick-Fix fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingQuickFix = false;
        });
      }
    }
  }

  Future<void> _confirmAndRunQuickFix() async {
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
      await _runQuickFix();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final health = snapshot == null ? null : _opsHealth(snapshot);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSnapshot,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSnapshot,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              AppFeedbackBanner(
                title: 'Monitoring-Fehler',
                message: _error!,
                severity: AppFeedbackSeverity.error,
                actionLabel: 'Erneut laden',
                onAction: _isLoading ? null : _loadSnapshot,
                onDismiss: () {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _error = null;
                  });
                },
              ),
            if (_lastUpdatedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Zuletzt aktualisiert ${_formatAge(_lastUpdatedAt!)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            if (_isLoading && snapshot == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_isLoading && snapshot == null && _error == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Noch keine Monitoring-Daten verfuegbar.'),
                ),
              ),
            if (snapshot != null) ...[
              _buildOpsStatusCard(snapshot, health!),
              const SizedBox(height: 12),
              _SectionTitle('Boxen'),
              _MetricGrid(
                items: <_MetricItem>[
                  _MetricItem('Gesamt', '${snapshot.totalBoxes}'),
                  _MetricItem('Verfuegbar', '${snapshot.availableBoxes}'),
                  _MetricItem('Reserviert', '${snapshot.reservedBoxes}'),
                  _MetricItem('Aktiv', '${snapshot.activeBoxes}'),
                  _MetricItem('Reinigung', '${snapshot.cleaningBoxes}'),
                  _MetricItem(
                    'Out of Service',
                    '${snapshot.outOfServiceBoxes}',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Sessions'),
              _MetricGrid(
                items: <_MetricItem>[
                  _MetricItem('Aktiv', '${snapshot.activeSessions}'),
                  _MetricItem('Naechste 5 min', '${snapshot.sessionsNext5m}'),
                  _MetricItem('Letzte 24h', '${snapshot.sessionsLast24h}'),
                  _MetricItem(
                    'Seit letztem Lauf',
                    '${snapshot.expiredSessionsSinceLastRun}',
                  ),
                  _MetricItem('Null-Box', '${snapshot.sessionsWithNullBox}'),
                ],
              ),
              if (snapshot.reconcileLastRunAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Letzter Reconcile-Lauf: ${_formatDateTime(snapshot.reconcileLastRunAt!)}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              const SizedBox(height: 16),
              _SectionTitle('Umsatz'),
              _MetricGrid(
                items: <_MetricItem>[
                  _MetricItem(
                    'Wasch-Umsatz heute',
                    _formatEuro(snapshot.washRevenueTodayEur),
                  ),
                  _MetricItem(
                    'Wasch-Umsatz 24h',
                    _formatEuro(snapshot.washRevenue24hEur),
                  ),
                  _MetricItem(
                    'Top-up heute',
                    _formatEuro(snapshot.topUpTodayEur),
                  ),
                  _MetricItem('Top-up 24h', _formatEuro(snapshot.topUp24hEur)),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Reservierungen'),
              _MetricGrid(
                items: <_MetricItem>[
                  _MetricItem('Offen', '${snapshot.openReservations}'),
                  _MetricItem('Stale', '${snapshot.staleReservations}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;

  const _MetricItem(this.label, this.value);
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricItem> items;

  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return Container(
          width: 160,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                item.value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TrafficLamp extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;

  const _TrafficLamp({
    required this.label,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.22) : Colors.white10,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? color : Colors.white24,
          width: isActive ? 1.2 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? color : Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitoringSnapshot {
  final int totalBoxes;
  final int availableBoxes;
  final int reservedBoxes;
  final int activeBoxes;
  final int cleaningBoxes;
  final int outOfServiceBoxes;
  final int activeSessions;
  final int sessionsNext5m;
  final int openReservations;
  final int staleReservations;
  final int sessionsWithNullBox;
  final int sessionsLast24h;
  final int expiredSessionsSinceLastRun;
  final double washRevenue24hEur;
  final double washRevenueTodayEur;
  final double topUp24hEur;
  final double topUpTodayEur;
  final DateTime? reconcileLastRunAt;

  const _MonitoringSnapshot({
    required this.totalBoxes,
    required this.availableBoxes,
    required this.reservedBoxes,
    required this.activeBoxes,
    required this.cleaningBoxes,
    required this.outOfServiceBoxes,
    required this.activeSessions,
    required this.sessionsNext5m,
    required this.openReservations,
    required this.staleReservations,
    required this.sessionsWithNullBox,
    required this.sessionsLast24h,
    required this.expiredSessionsSinceLastRun,
    required this.washRevenue24hEur,
    required this.washRevenueTodayEur,
    required this.topUp24hEur,
    required this.topUpTodayEur,
    required this.reconcileLastRunAt,
  });

  factory _MonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    final boxesRaw = json['boxes'];
    final boxes = boxesRaw is Map
        ? Map<String, dynamic>.from(boxesRaw)
        : <String, dynamic>{};

    int read(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    double readDouble(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value.trim()) ?? 0;
      }
      return 0;
    }

    DateTime? readDateTime(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim())?.toLocal();
      }
      return null;
    }

    return _MonitoringSnapshot(
      totalBoxes: read(boxes, 'total'),
      availableBoxes: read(boxes, 'available'),
      reservedBoxes: read(boxes, 'reserved'),
      activeBoxes: read(boxes, 'active'),
      cleaningBoxes: read(boxes, 'cleaning'),
      outOfServiceBoxes: read(boxes, 'out_of_service'),
      activeSessions: read(json, 'activeSessions'),
      sessionsNext5m: read(json, 'sessionsNext5m'),
      openReservations: read(json, 'openReservations'),
      staleReservations: read(json, 'staleReservations'),
      sessionsWithNullBox: read(json, 'sessionsWithNullBox'),
      sessionsLast24h: read(json, 'sessionsLast24h'),
      expiredSessionsSinceLastRun: read(json, 'expiredSessionsSinceLastRun'),
      washRevenue24hEur: readDouble(json, 'washRevenue24hEur'),
      washRevenueTodayEur: readDouble(json, 'washRevenueTodayEur'),
      topUp24hEur: readDouble(json, 'topUp24hEur'),
      topUpTodayEur: readDouble(json, 'topUpTodayEur'),
      reconcileLastRunAt: readDateTime(json, 'reconcileLastRunAt'),
    );
  }
}

enum _OpsHealth { ok, warning, critical }
