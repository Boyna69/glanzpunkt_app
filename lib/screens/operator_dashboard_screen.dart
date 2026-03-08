import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_config.dart';
import '../models/box.dart';
import '../models/wash_session.dart';
import '../services/auth_service.dart';
import '../services/backend_http_client.dart';
import '../services/box_service.dart';
import '../services/environment_service.dart';
import '../services/ops_maintenance_service.dart';

class OperatorDashboardScreen extends StatefulWidget {
  const OperatorDashboardScreen({super.key});

  @override
  State<OperatorDashboardScreen> createState() =>
      _OperatorDashboardScreenState();
}

class _OperatorDashboardScreenState extends State<OperatorDashboardScreen> {
  static const int _defaultCleaningIntervalWashes = 75;
  static const int _defaultLongActiveSessionThresholdMinutes = 20;
  static const int _operatorActionPageSize = 20;
  static const String _kpiBusinessTimeZone = 'Europe/Berlin';
  static const String _defaultUatTargetBuild = 'current';
  static const Duration _operatorActionSearchDebounceDuration = Duration(
    milliseconds: 350,
  );

  bool _isApplyingQuickFix = false;
  bool _isRefreshingCleaningPlan = false;
  final Set<int> _markingCleanedBoxes = <int>{};
  final Map<int, OpsBoxCleaningPlanItem> _remoteCleaningPlanByBox =
      <int, OpsBoxCleaningPlanItem>{};
  final List<OpsBoxCleaningHistoryItem> _cleaningHistory =
      <OpsBoxCleaningHistoryItem>[];
  final List<OpsOperatorActionItem> _operatorActions =
      <OpsOperatorActionItem>[];
  final List<OpsOperatorActionItem> _thresholdAuditActions =
      <OpsOperatorActionItem>[];
  final TextEditingController _operatorActionSearchController =
      TextEditingController();
  OpsMonitoringSnapshot? _monitoringSnapshot;
  String? _cleaningPlanWarning;
  String? _operatorActionWarning;
  String? _thresholdAuditWarning;
  String? _kpiExportWarning;
  bool _isRefreshingOperatorActions = false;
  bool _isRefreshingThresholdAudit = false;
  bool _operatorActionsHasMore = false;
  bool _isExportingKpi = false;
  bool _isSavingThresholdSettings = false;
  int _operatorActionPage = 0;
  String _operatorActionSearchQuery = '';
  String _operatorActionStatusFilter = 'all';
  String _operatorActionTimeFilter = 'all';
  String _kpiExportPeriod = 'day';
  int? _operatorActionBoxFilter;
  OpsKpiExportSnapshot? _kpiPreviewSnapshot;
  int _cleaningIntervalWashes = _defaultCleaningIntervalWashes;
  Duration _longActiveSessionThreshold = const Duration(
    minutes: _defaultLongActiveSessionThresholdMinutes,
  );
  DateTime? _thresholdSettingsUpdatedAt;
  Timer? _operatorActionSearchDebounce;
  late final OpsMaintenanceService _opsMaintenance;

  @override
  void initState() {
    super.initState();
    final apiKey = AppConfig.supabaseApiKey;
    final client = createBackendHttpClient(
      defaultHeaders: <String, String>{
        if (apiKey.isNotEmpty) ...{
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
        },
        'x-client-info': 'glanzpunkt_app/1.0',
      },
    );
    _opsMaintenance = OpsMaintenanceService(httpClient: client);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshCleaningPlanData());
    });
  }

  @override
  void dispose() {
    _operatorActionSearchDebounce?.cancel();
    _operatorActionSearchController.dispose();
    super.dispose();
  }

  String _roleLabel(AccountRole role) {
    switch (role) {
      case AccountRole.customer:
        return 'Kunde';
      case AccountRole.operator:
        return 'Betreiber';
      case AccountRole.owner:
        return 'Inhaber';
    }
  }

  Future<void> _logOperatorActionSafe({
    required String actionName,
    required String actionStatus,
    int? boxId,
    Map<String, dynamic>? details,
    String? uatSummary,
    String? uatArea,
    OpsUatStatus? uatStatus,
    OpsUatSeverity? uatSeverity,
    String uatTargetBuild = _defaultUatTargetBuild,
  }) async {
    if (!mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      return;
    }
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
    final summary = (uatSummary?.trim().isNotEmpty ?? false)
        ? uatSummary!.trim()
        : _operatorActionTitle(actionName);
    final area = (uatArea?.trim().isNotEmpty ?? false)
        ? uatArea!.trim()
        : (boxId != null ? 'box_$boxId' : 'operator_dashboard');
    try {
      await _opsMaintenance.logUatAction(
        baseUrl: baseUrl,
        jwt: jwt,
        actionName: actionName,
        actionStatus: actionStatus,
        summary: summary,
        area: area,
        uatStatus: uatStatus ?? _defaultUatStatusForActionStatus(actionStatus),
        severity:
            uatSeverity ?? _defaultUatSeverityForActionStatus(actionStatus),
        targetBuild: uatTargetBuild,
        boxId: boxId,
        details: details,
      );
    } catch (_) {
      // Intentionally ignored: operational logging must never break UX flow.
    }
  }

  Future<void> _refreshOperatorActionsCache({
    required String baseUrl,
    required String jwt,
    bool resetPage = false,
    int? page,
  }) async {
    final previousPage = _operatorActionPage;
    final targetPage = page ?? (resetPage ? 0 : _operatorActionPage);
    final statusFilter = _operatorActionStatusFilter == 'all'
        ? null
        : _operatorActionStatusFilter;
    final searchQuery = _operatorActionSearchQuery.trim().isEmpty
        ? null
        : _operatorActionSearchQuery.trim();
    final fromAt = _operatorActionFromAtFilter();

    if (mounted) {
      setState(() {
        _isRefreshingOperatorActions = true;
        _operatorActionPage = targetPage;
      });
    }

    try {
      final rows = await _opsMaintenance.fetchOperatorActions(
        baseUrl: baseUrl,
        jwt: jwt,
        maxRows: _operatorActionPageSize + 1,
        offsetRows: targetPage * _operatorActionPageSize,
        filterStatus: statusFilter,
        filterBoxId: _operatorActionBoxFilter,
        searchQuery: searchQuery,
        fromAt: fromAt,
      );
      final hasMore = rows.length > _operatorActionPageSize;
      final pageRows = hasMore
          ? rows.take(_operatorActionPageSize).toList()
          : rows;
      if (!mounted) {
        return;
      }
      setState(() {
        _operatorActions
          ..clear()
          ..addAll(pageRows);
        _operatorActionsHasMore = hasMore;
        _operatorActionWarning = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _operatorActionPage = previousPage;
        _operatorActionsHasMore = false;
        _operatorActionWarning = 'Operator-Aktionslog nicht verfuegbar. ($e)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingOperatorActions = false;
        });
      }
    }
  }

  Future<void> _refreshThresholdAuditCache({
    required String baseUrl,
    required String jwt,
  }) async {
    if (mounted) {
      setState(() {
        _isRefreshingThresholdAudit = true;
      });
    }

    try {
      final rows = await _opsMaintenance.fetchOperatorActions(
        baseUrl: baseUrl,
        jwt: jwt,
        maxRows: 8,
        filterStatus: 'success',
        searchQuery: 'update_thresholds',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _thresholdAuditActions
          ..clear()
          ..addAll(rows.where((row) => row.actionName == 'update_thresholds'));
        _thresholdAuditWarning = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _thresholdAuditActions.clear();
        _thresholdAuditWarning = 'Threshold-Historie nicht verfuegbar. ($e)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingThresholdAudit = false;
        });
      }
    }
  }

  DateTime? _operatorActionFromAtFilter() {
    final now = DateTime.now();
    switch (_operatorActionTimeFilter) {
      case '24h':
        return now.subtract(const Duration(hours: 24));
      case '7d':
        return now.subtract(const Duration(days: 7));
      default:
        return null;
    }
  }

  void _triggerOperatorActionRefresh({bool resetPage = true, int? page}) {
    if (!mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      return;
    }
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
    unawaited(
      _refreshOperatorActionsCache(
        baseUrl: baseUrl,
        jwt: jwt,
        resetPage: resetPage,
        page: page,
      ),
    );
  }

  void _scheduleOperatorActionSearchRefresh() {
    _operatorActionSearchDebounce?.cancel();
    _operatorActionSearchDebounce = Timer(
      _operatorActionSearchDebounceDuration,
      () => _triggerOperatorActionRefresh(resetPage: true),
    );
  }

  Future<void> _runQuickFix() async {
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

    final confirm = await showDialog<bool>(
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
    if (confirm != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _isApplyingQuickFix = true;
    });

    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;

    try {
      final result = await _opsMaintenance.runExpireActiveSessions(
        baseUrl: baseUrl,
        jwt: jwt,
      );
      await _logOperatorActionSafe(
        actionName: 'quick_fix',
        actionStatus: 'success',
        uatSummary: 'Quick-Fix erfolgreich ausgefuehrt',
        uatArea: 'operator_dashboard',
        uatStatus: OpsUatStatus.fixed,
        uatSeverity: OpsUatSeverity.medium,
        details: <String, dynamic>{
          'expiredReservations': result.expiredReservations,
          'releasedReservedBoxes': result.releasedReservedBoxes,
          'expiredSessions': result.expiredSessions,
          'updatedBoxes': result.updatedBoxes,
        },
      );
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
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
      await _logOperatorActionSafe(
        actionName: 'quick_fix',
        actionStatus: 'failed',
        uatSummary: 'Quick-Fix fehlgeschlagen',
        uatArea: 'operator_dashboard',
        uatStatus: OpsUatStatus.open,
        uatSeverity: OpsUatSeverity.high,
        details: <String, dynamic>{'error': _trimForTelemetry(e)},
      );
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
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

  Future<void> _refreshCleaningPlanData({bool showFeedback = false}) async {
    if (!mounted || _isRefreshingCleaningPlan) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nur mit gueltiger Betreiber-Session moeglich.'),
        ),
      );
      return;
    }
    final boxService = context.read<BoxService>();
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;

    setState(() {
      _isRefreshingCleaningPlan = true;
    });

    String? warning;
    final nextRemotePlan = <int, OpsBoxCleaningPlanItem>{};
    final nextHistory = <OpsBoxCleaningHistoryItem>[];
    OpsMonitoringSnapshot? nextMonitoringSnapshot;
    var nextCleaningIntervalWashes = _cleaningIntervalWashes;
    var nextLongActiveSessionThreshold = _longActiveSessionThreshold;
    DateTime? nextThresholdSettingsUpdatedAt = _thresholdSettingsUpdatedAt;
    try {
      await boxService.forceSyncAllBoxes();
      try {
        final thresholdSettings = await _opsMaintenance
            .fetchOperatorThresholdSettings(baseUrl: baseUrl, jwt: jwt);
        nextCleaningIntervalWashes = thresholdSettings.cleaningIntervalWashes;
        nextLongActiveSessionThreshold = Duration(
          minutes: thresholdSettings.longActiveMinutes,
        );
        nextThresholdSettingsUpdatedAt = thresholdSettings.updatedAt;
      } catch (e) {
        final thresholdWarning =
            'Threshold-Settings nicht verfuegbar. '
            'Standardwerte aktiv. ($e)';
        warning = thresholdWarning;
      }
      try {
        final remotePlans = await _opsMaintenance.fetchBoxCleaningPlan(
          baseUrl: baseUrl,
          jwt: jwt,
          intervalWashes: nextCleaningIntervalWashes,
        );
        nextRemotePlan.addEntries(
          remotePlans.map((item) => MapEntry(item.boxId, item)),
        );
      } catch (e) {
        final remotePlanWarning =
            'Backend-Reinigungsplan nicht verfuegbar. '
            'Lokale Berechnung aktiv. ($e)';
        warning = warning == null
            ? remotePlanWarning
            : '$warning\n$remotePlanWarning';
      }
      try {
        final history = await _opsMaintenance.fetchCleaningHistory(
          baseUrl: baseUrl,
          jwt: jwt,
          maxRows: 20,
        );
        nextHistory.addAll(history);
      } catch (e) {
        final historyWarning = 'Reinigungsverlauf nicht verfuegbar. ($e)';
        warning = warning == null
            ? historyWarning
            : '$warning\n$historyWarning';
      }
      try {
        nextMonitoringSnapshot = await _opsMaintenance.fetchMonitoringSnapshot(
          baseUrl: baseUrl,
          jwt: jwt,
        );
      } catch (e) {
        final monitoringWarning = 'Monitoring nicht verfuegbar. ($e)';
        warning = warning == null
            ? monitoringWarning
            : '$warning\n$monitoringWarning';
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _remoteCleaningPlanByBox
          ..clear()
          ..addAll(nextRemotePlan);
        _cleaningHistory
          ..clear()
          ..addAll(nextHistory);
        if (nextMonitoringSnapshot != null) {
          _monitoringSnapshot = nextMonitoringSnapshot;
        }
        _cleaningIntervalWashes = nextCleaningIntervalWashes;
        _longActiveSessionThreshold = nextLongActiveSessionThreshold;
        _thresholdSettingsUpdatedAt = nextThresholdSettingsUpdatedAt;
        _cleaningPlanWarning = warning;
      });
      if (!_isExportingKpi) {
        unawaited(_fetchKpiSnapshotForCurrentPeriod(showErrorSnack: false));
      }
      await _refreshThresholdAuditCache(baseUrl: baseUrl, jwt: jwt);
      if (!showFeedback) {
        await _refreshOperatorActionsCache(
          baseUrl: baseUrl,
          jwt: jwt,
          resetPage: false,
        );
      }
      if (showFeedback && mounted) {
        await _logOperatorActionSafe(
          actionName: 'status_refresh',
          actionStatus: warning == null ? 'success' : 'partial',
          uatSummary: warning == null
              ? 'Status-Refresh erfolgreich'
              : 'Status-Refresh mit Warnungen',
          uatArea: 'operator_dashboard',
          uatStatus: warning == null
              ? OpsUatStatus.closed
              : OpsUatStatus.inProgress,
          uatSeverity: warning == null
              ? OpsUatSeverity.low
              : OpsUatSeverity.medium,
          details: <String, dynamic>{
            'warning': warning == null ? 'none' : 'present',
            'historyRows': nextHistory.length,
            'remotePlanBoxes': nextRemotePlan.length,
            'monitoring': nextMonitoringSnapshot == null ? 'missing' : 'ok',
            'cleaningIntervalWashes': nextCleaningIntervalWashes,
            'longActiveMinutes': nextLongActiveSessionThreshold.inMinutes,
          },
        );
        if (mounted) {
          unawaited(
            _refreshOperatorActionsCache(
              baseUrl: baseUrl,
              jwt: jwt,
              resetPage: true,
            ),
          );
        }
      }
      if (showFeedback && mounted) {
        final updatedHistory = nextHistory.isNotEmpty;
        final feedback = warning == null
            ? 'Status-, Reinigungsplan- und Verlaufdaten aktualisiert.'
            : updatedHistory
            ? 'Status aktualisiert, teilweise mit Fallback geladen.'
            : 'Status aktualisiert, Reinigungsverlauf aktuell nicht verfuegbar.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(feedback)));
      }
    } catch (e) {
      if (showFeedback && mounted) {
        await _logOperatorActionSafe(
          actionName: 'status_refresh',
          actionStatus: 'failed',
          uatSummary: 'Status-Refresh fehlgeschlagen',
          uatArea: 'operator_dashboard',
          uatStatus: OpsUatStatus.open,
          uatSeverity: OpsUatSeverity.high,
          details: <String, dynamic>{'error': _trimForTelemetry(e)},
        );
        if (mounted) {
          unawaited(
            _refreshOperatorActionsCache(
              baseUrl: baseUrl,
              jwt: jwt,
              resetPage: false,
            ),
          );
        }
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Reinigungsdaten konnten nicht geladen werden: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingCleaningPlan = false;
        });
      }
    }
  }

  Future<void> _markBoxCleaned(int boxNumber) async {
    if (!mounted || _markingCleanedBoxes.contains(boxNumber)) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nur mit gueltiger Betreiber-Session moeglich.'),
        ),
      );
      return;
    }

    final noteController = TextEditingController();
    final note = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Box $boxNumber als gereinigt markieren?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Der Zaehler wird auf 0 gesetzt und die letzte Reinigung '
              'auf jetzt gespeichert.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                hintText: 'z. B. Duesen geprueft, Boden gereinigt',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, noteController.text.trim()),
            child: const Text('Bestaetigen'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || !mounted) {
      return;
    }

    setState(() {
      _markingCleanedBoxes.add(boxNumber);
    });

    try {
      final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
      await _opsMaintenance.markBoxCleaned(
        baseUrl: baseUrl,
        jwt: jwt,
        boxId: boxNumber,
        note: note.isEmpty ? null : note,
      );
      await _logOperatorActionSafe(
        actionName: 'mark_cleaned',
        actionStatus: 'success',
        boxId: boxNumber,
        uatSummary: 'Reinigung fuer Box $boxNumber gespeichert',
        uatStatus: OpsUatStatus.closed,
        uatSeverity: OpsUatSeverity.low,
        details: <String, dynamic>{'hasNote': note.isNotEmpty},
      );
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
      await _refreshCleaningPlanData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Box $boxNumber wurde als gereinigt gespeichert.'),
        ),
      );
    } catch (e) {
      final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
      await _logOperatorActionSafe(
        actionName: 'mark_cleaned',
        actionStatus: 'failed',
        boxId: boxNumber,
        uatSummary: 'Reinigung fuer Box $boxNumber fehlgeschlagen',
        uatStatus: OpsUatStatus.open,
        uatSeverity: OpsUatSeverity.high,
        details: <String, dynamic>{'error': _trimForTelemetry(e)},
      );
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Reinigung konnte nicht gespeichert werden: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingCleanedBoxes.remove(boxNumber);
        });
      }
    }
  }

  Future<void> _editThresholdSettings() async {
    if (!mounted || _isSavingThresholdSettings) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nur mit gueltiger Betreiber-Session moeglich.'),
        ),
      );
      return;
    }
    if (auth.profileRole != AccountRole.owner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thresholds koennen nur vom Inhaber geaendert werden.'),
        ),
      );
      return;
    }

    final intervalController = TextEditingController(
      text: _cleaningIntervalWashes.toString(),
    );
    final longActiveController = TextEditingController(
      text: _longActiveSessionThreshold.inMinutes.toString(),
    );
    String? validationError;

    final input = await showDialog<_ThresholdDialogInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Thresholds anpassen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: intervalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Reinigungsintervall (Waeschen)',
                  hintText: '1-500',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: longActiveController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Long-Active-Warnung (Minuten)',
                  hintText: '1-240',
                  border: OutlineInputBorder(),
                ),
              ),
              if (validationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  validationError!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final interval = int.tryParse(intervalController.text.trim());
                final longActive = int.tryParse(
                  longActiveController.text.trim(),
                );
                String? error;
                if (interval == null || interval < 1 || interval > 500) {
                  error = 'Reinigungsintervall muss zwischen 1 und 500 liegen.';
                } else if (longActive == null ||
                    longActive < 1 ||
                    longActive > 240) {
                  error =
                      'Long-Active-Minuten muessen zwischen 1 und 240 liegen.';
                }
                if (error != null) {
                  setDialogState(() {
                    validationError = error;
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  _ThresholdDialogInput(
                    cleaningIntervalWashes: interval!,
                    longActiveMinutes: longActive!,
                  ),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    intervalController.dispose();
    longActiveController.dispose();

    if (input == null || !mounted) {
      return;
    }

    final previousCleaningIntervalWashes = _cleaningIntervalWashes;
    final previousLongActiveMinutes = _longActiveSessionThreshold.inMinutes;
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;

    setState(() {
      _isSavingThresholdSettings = true;
    });

    try {
      final settings = await _opsMaintenance.updateOperatorThresholdSettings(
        baseUrl: baseUrl,
        jwt: jwt,
        cleaningIntervalWashes: input.cleaningIntervalWashes,
        longActiveMinutes: input.longActiveMinutes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _cleaningIntervalWashes = settings.cleaningIntervalWashes;
        _longActiveSessionThreshold = Duration(
          minutes: settings.longActiveMinutes,
        );
        _thresholdSettingsUpdatedAt = settings.updatedAt;
      });
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
      await _refreshCleaningPlanData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Thresholds gespeichert: '
            '${settings.cleaningIntervalWashes} Waeschen / '
            '${settings.longActiveMinutes} Minuten.',
          ),
        ),
      );
    } catch (e) {
      await _logOperatorActionSafe(
        actionName: 'update_thresholds',
        actionStatus: 'failed',
        uatSummary: 'Threshold-Update fehlgeschlagen',
        uatArea: 'threshold_settings',
        uatStatus: OpsUatStatus.open,
        uatSeverity: OpsUatSeverity.high,
        details: <String, dynamic>{
          'error': _trimForTelemetry(e),
          'beforeCleaningIntervalWashes': previousCleaningIntervalWashes,
          'beforeLongActiveMinutes': previousLongActiveMinutes,
          'requestedCleaningIntervalWashes': input.cleaningIntervalWashes,
          'requestedLongActiveMinutes': input.longActiveMinutes,
        },
      );
      if (mounted) {
        unawaited(
          _refreshOperatorActionsCache(
            baseUrl: baseUrl,
            jwt: jwt,
            resetPage: true,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Thresholds konnten nicht gespeichert werden: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingThresholdSettings = false;
        });
      }
    }
  }

  String _issueSourceLabel(String source) {
    switch (source) {
      case 'catalog':
        return 'Box-Katalog';
      case 'status':
        return 'Box-Status';
      case 'history':
        return 'Session-Historie';
      case 'realtime':
        return 'Realtime';
      default:
        return source;
    }
  }

  String _formatIssueAge(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) {
      return 'vor ${diff.inSeconds}s';
    }
    if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes}m';
    }
    if (diff.inHours < 24) {
      return 'vor ${diff.inHours}h';
    }
    return 'vor ${diff.inDays}d';
  }

  String _trimForTelemetry(Object error, {int maxLength = 140}) {
    final raw = '$error'.trim();
    if (raw.length <= maxLength) {
      return raw;
    }
    return '${raw.substring(0, maxLength)}...';
  }

  OpsUatStatus _defaultUatStatusForActionStatus(String actionStatus) {
    switch (actionStatus.trim().toLowerCase()) {
      case 'success':
        return OpsUatStatus.closed;
      case 'partial':
      case 'warning':
        return OpsUatStatus.inProgress;
      case 'fixed':
        return OpsUatStatus.fixed;
      case 'retest':
        return OpsUatStatus.retest;
      default:
        return OpsUatStatus.open;
    }
  }

  OpsUatSeverity _defaultUatSeverityForActionStatus(String actionStatus) {
    switch (actionStatus.trim().toLowerCase()) {
      case 'failed':
      case 'error':
      case 'timeout':
      case 'forbidden':
        return OpsUatSeverity.high;
      case 'partial':
      case 'warning':
        return OpsUatSeverity.medium;
      default:
        return OpsUatSeverity.low;
    }
  }

  String _operatorActionTitle(String name) {
    switch (name) {
      case 'status_refresh':
        return 'Status neu laden';
      case 'quick_fix':
        return 'Quick-Fix';
      case 'mark_cleaned':
        return 'Reinigung gespeichert';
      case 'update_thresholds':
        return 'Thresholds aktualisiert';
      default:
        return name;
    }
  }

  String _operatorActionStatusLabel(String status) {
    switch (status) {
      case 'success':
        return 'Erfolg';
      case 'partial':
        return 'Teilweise';
      case 'failed':
        return 'Fehler';
      default:
        return status;
    }
  }

  Color _operatorActionStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.greenAccent;
      case 'partial':
        return Colors.orangeAccent;
      case 'failed':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  String _formatActionDetails(Map<String, dynamic> properties) {
    if (properties.isEmpty) {
      return '-';
    }
    return properties.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' • ');
  }

  String _operatorActionTimeFilterLabel() {
    switch (_operatorActionTimeFilter) {
      case '24h':
        return '24h';
      case '7d':
        return '7 Tage';
      default:
        return 'Gesamt';
    }
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _buildOperatorActionCsv(List<OpsOperatorActionItem> actions) {
    final rows = <String>[
      'id,created_at,action_name,action_status,box_id,actor_email,actor_id,source,details_json',
    ];
    for (final action in actions) {
      rows.add(
        [
          action.id.toString(),
          _csvEscape(action.createdAt.toIso8601String()),
          _csvEscape(action.actionName),
          _csvEscape(action.actionStatus),
          action.boxId?.toString() ?? '',
          _csvEscape(action.actorEmail ?? ''),
          _csvEscape(action.actorId),
          _csvEscape(action.source),
          _csvEscape(jsonEncode(action.details)),
        ].join(','),
      );
    }
    return rows.join('\n');
  }

  String _buildOperatorActionExportFileName() {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return 'glanzpunkt_operator_actions_$timestamp.csv';
  }

  Future<void> _exportOperatorActionsCsv(
    List<OpsOperatorActionItem> actions,
  ) async {
    if (actions.isEmpty || !mounted) {
      return;
    }
    final csv = _buildOperatorActionCsv(actions);
    final fileName = _buildOperatorActionExportFileName();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv, flush: true);

      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
          text:
              'Glanzpunkt Operator-Aktionen (${actions.length} Eintraege) als CSV',
          subject: fileName,
        ),
      );

      if (!mounted) {
        return;
      }
      final statusLabel = shareResult.status == ShareResultStatus.success
          ? 'geteilt'
          : 'erstellt';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${actions.length} Operator-Aktionen als CSV-Datei $statusLabel ($fileName).',
          ),
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV-Datei konnte nicht geteilt werden. '
            '${actions.length} Eintraege in Zwischenablage kopiert.',
          ),
        ),
      );
    }
  }

  Future<void> _saveOperatorActionsCsvLocally(
    List<OpsOperatorActionItem> actions,
  ) async {
    if (actions.isEmpty || !mounted) {
      return;
    }
    final csv = _buildOperatorActionCsv(actions);
    final fileName = _buildOperatorActionExportFileName();

    Future<Directory> resolveDirectory() async {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return downloads;
        }
      } catch (_) {
        // Fallback below.
      }
      return getApplicationDocumentsDirectory();
    }

    try {
      final dir = await resolveDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv, flush: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${actions.length} Operator-Aktionen lokal gespeichert.',
          ),
          action: SnackBarAction(
            label: 'Pfad kopieren',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
            },
          ),
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lokales Speichern fehlgeschlagen. '
            '${actions.length} Eintraege in Zwischenablage kopiert.',
          ),
        ),
      );
    }
  }

  String _kpiPeriodLabel(String period) {
    switch (period) {
      case 'week':
        return 'Woche';
      case 'month':
        return 'Monat';
      default:
        return 'Tag';
    }
  }

  String _kpiWindowLabel(OpsKpiExportSnapshot snapshot) {
    return '${_formatDateTime(snapshot.windowStart)} bis '
        '${_formatDateTime(snapshot.windowEnd)} ($_kpiBusinessTimeZone)';
  }

  String _buildKpiExportCsv(OpsKpiExportSnapshot snapshot) {
    final headers = <String>[
      'period',
      'timezone',
      'generated_at_local',
      'window_start_local',
      'window_end_local',
      'previous_window_start_local',
      'previous_window_end_local',
      'generated_at_utc',
      'window_start_utc',
      'window_end_utc',
      'previous_window_start_utc',
      'previous_window_end_utc',
      'boxes_total',
      'boxes_available',
      'boxes_reserved',
      'boxes_active',
      'boxes_cleaning',
      'boxes_out_of_service',
      'active_sessions',
      'sessions_started',
      'previous_sessions_started',
      'delta_sessions_started',
      'delta_sessions_started_pct',
      'wash_revenue_eur',
      'previous_wash_revenue_eur',
      'delta_wash_revenue_eur',
      'delta_wash_revenue_pct',
      'top_up_revenue_eur',
      'previous_top_up_revenue_eur',
      'delta_top_up_revenue_eur',
      'delta_top_up_revenue_pct',
      'quick_fixes',
      'cleaning_actions',
      'open_reservations',
      'stale_reservations',
    ];
    final values = <String>[
      _csvEscape(snapshot.period),
      _csvEscape(_kpiBusinessTimeZone),
      _csvEscape(_formatDateTime(snapshot.generatedAt)),
      _csvEscape(_formatDateTime(snapshot.windowStart)),
      _csvEscape(_formatDateTime(snapshot.windowEnd)),
      _csvEscape(
        snapshot.previousWindowStart == null
            ? ''
            : _formatDateTime(snapshot.previousWindowStart!),
      ),
      _csvEscape(
        snapshot.previousWindowEnd == null
            ? ''
            : _formatDateTime(snapshot.previousWindowEnd!),
      ),
      _csvEscape(snapshot.generatedAt.toUtc().toIso8601String()),
      _csvEscape(snapshot.windowStart.toUtc().toIso8601String()),
      _csvEscape(snapshot.windowEnd.toUtc().toIso8601String()),
      _csvEscape(snapshot.previousWindowStart?.toUtc().toIso8601String() ?? ''),
      _csvEscape(snapshot.previousWindowEnd?.toUtc().toIso8601String() ?? ''),
      snapshot.totalBoxes.toString(),
      snapshot.availableBoxes.toString(),
      snapshot.reservedBoxes.toString(),
      snapshot.activeBoxes.toString(),
      snapshot.cleaningBoxes.toString(),
      snapshot.outOfServiceBoxes.toString(),
      snapshot.activeSessions.toString(),
      snapshot.sessionsStarted.toString(),
      (snapshot.previousSessionsStarted ?? '').toString(),
      (snapshot.deltaSessionsStarted ?? '').toString(),
      snapshot.deltaSessionsStartedPct?.toStringAsFixed(2) ?? '',
      snapshot.washRevenueEur.toStringAsFixed(2),
      snapshot.previousWashRevenueEur?.toStringAsFixed(2) ?? '',
      snapshot.deltaWashRevenueEur?.toStringAsFixed(2) ?? '',
      snapshot.deltaWashRevenuePct?.toStringAsFixed(2) ?? '',
      snapshot.topUpRevenueEur.toStringAsFixed(2),
      snapshot.previousTopUpRevenueEur?.toStringAsFixed(2) ?? '',
      snapshot.deltaTopUpRevenueEur?.toStringAsFixed(2) ?? '',
      snapshot.deltaTopUpRevenuePct?.toStringAsFixed(2) ?? '',
      snapshot.quickFixes.toString(),
      snapshot.cleaningActions.toString(),
      snapshot.openReservations.toString(),
      snapshot.staleReservations.toString(),
    ];
    return '${headers.join(',')}\n${values.join(',')}';
  }

  String _buildKpiExportFileName(String period) {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return 'glanzpunkt_kpi_${period}_$timestamp.csv';
  }

  String _buildKpiSummaryText(OpsKpiExportSnapshot snapshot) {
    final deltaLine = _buildKpiDeltaSummary(snapshot);
    final buffer = StringBuffer()
      ..writeln('Glanzpunkt KPI-Bericht (${_kpiPeriodLabel(snapshot.period)})')
      ..writeln('Zeitzone: $_kpiBusinessTimeZone')
      ..writeln('Fenster: ${_kpiWindowLabel(snapshot)}')
      ..writeln(
        snapshot.previousWindowStart != null &&
                snapshot.previousWindowEnd != null
            ? 'Vorzeitraum: ${_formatDateTime(snapshot.previousWindowStart!)} bis ${_formatDateTime(snapshot.previousWindowEnd!)} ($_kpiBusinessTimeZone)'
            : 'Vorzeitraum: -',
      )
      ..writeln('Generiert: ${_formatDateTime(snapshot.generatedAt)}')
      ..writeln('')
      ..writeln('Sessions gestartet: ${snapshot.sessionsStarted}')
      ..writeln('Aktive Sessions: ${snapshot.activeSessions}')
      ..writeln('Umsatz Waeschen: ${_formatEuro(snapshot.washRevenueEur)}')
      ..writeln('Umsatz Top-up: ${_formatEuro(snapshot.topUpRevenueEur)}')
      ..writeln(deltaLine)
      ..writeln('')
      ..writeln(
        'Boxen: gesamt ${snapshot.totalBoxes}, verfuegbar ${snapshot.availableBoxes}, '
        'reserviert ${snapshot.reservedBoxes}, aktiv ${snapshot.activeBoxes}, '
        'cleaning ${snapshot.cleaningBoxes}, out_of_service ${snapshot.outOfServiceBoxes}',
      )
      ..writeln(
        'Reservierungen: offen ${snapshot.openReservations}, stale ${snapshot.staleReservations}',
      )
      ..writeln(
        'Operator-Aktionen: quick_fix ${snapshot.quickFixes}, mark_cleaned ${snapshot.cleaningActions}',
      );
    return buffer.toString().trimRight();
  }

  String _signedInt(int value) {
    if (value > 0) {
      return '+$value';
    }
    return '$value';
  }

  String _signedEuro(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)} EUR';
  }

  String _signedPercent(double? value) {
    if (value == null) {
      return 'n/a';
    }
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}%';
  }

  String _buildKpiDeltaSummary(OpsKpiExportSnapshot snapshot) {
    final sessionsDelta = snapshot.deltaSessionsStarted;
    final washDelta = snapshot.deltaWashRevenueEur;
    final topUpDelta = snapshot.deltaTopUpRevenueEur;
    if (sessionsDelta == null || washDelta == null || topUpDelta == null) {
      return 'Delta Vorzeitraum: keine Vergleichsdaten';
    }
    return 'Delta Vorzeitraum: Sessions ${_signedInt(sessionsDelta)} '
        '(${_signedPercent(snapshot.deltaSessionsStartedPct)}), '
        'Umsatz ${_signedEuro(washDelta)} '
        '(${_signedPercent(snapshot.deltaWashRevenuePct)}), '
        'Top-up ${_signedEuro(topUpDelta)} '
        '(${_signedPercent(snapshot.deltaTopUpRevenuePct)})';
  }

  Future<OpsKpiExportSnapshot?> _fetchKpiSnapshotForCurrentPeriod({
    bool showErrorSnack = false,
  }) async {
    if (!mounted) {
      return null;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      if (showErrorSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('KPI-Export nur mit Betreiber-Session moeglich.'),
          ),
        );
      }
      return null;
    }
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
    setState(() {
      _isExportingKpi = true;
    });
    try {
      final snapshot = await _opsMaintenance.fetchKpiExportSnapshot(
        baseUrl: baseUrl,
        jwt: jwt,
        period: _kpiExportPeriod,
      );
      if (!mounted) {
        return snapshot;
      }
      setState(() {
        _kpiPreviewSnapshot = snapshot;
        _kpiExportWarning = null;
      });
      return snapshot;
    } catch (e) {
      if (!mounted) {
        return null;
      }
      final message = _readableError(e);
      final hasCachedPreview =
          _kpiPreviewSnapshot != null &&
          _kpiPreviewSnapshot!.period == _kpiExportPeriod;
      setState(() {
        _kpiExportWarning = hasCachedPreview
            ? 'KPI-Export aktuell nicht erreichbar: $message '
                  '(letzte erfolgreiche Werte werden angezeigt).'
            : 'KPI-Export aktuell nicht erreichbar: $message';
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text(_kpiExportWarning!),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isExportingKpi = false;
        });
      }
    }
  }

  Future<void> _shareKpiCsv() async {
    final snapshot = await _fetchKpiSnapshotForCurrentPeriod(
      showErrorSnack: true,
    );
    if (snapshot == null || !mounted) {
      return;
    }
    final fileName = _buildKpiExportFileName(snapshot.period);
    final csv = _buildKpiExportCsv(snapshot);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv, flush: true);
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
          text:
              'Glanzpunkt KPI-Export (${_kpiPeriodLabel(snapshot.period)}) als CSV',
          subject: fileName,
        ),
      );
      if (!mounted) {
        return;
      }
      final statusLabel = shareResult.status == ShareResultStatus.success
          ? 'geteilt'
          : 'erstellt';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KPI-CSV $statusLabel ($fileName).')),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'KPI-CSV konnte nicht geteilt werden. In Zwischenablage kopiert.',
          ),
        ),
      );
    }
  }

  Future<void> _copyKpiSummaryToClipboard() async {
    final snapshot = await _fetchKpiSnapshotForCurrentPeriod(
      showErrorSnack: true,
    );
    if (snapshot == null || !mounted) {
      return;
    }
    final summary = _buildKpiSummaryText(snapshot);
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'KPI-Bericht (${_kpiPeriodLabel(snapshot.period)}) in Zwischenablage kopiert.',
        ),
      ),
    );
  }

  Future<void> _shareKpiSummary() async {
    final snapshot = await _fetchKpiSnapshotForCurrentPeriod(
      showErrorSnack: true,
    );
    if (snapshot == null || !mounted) {
      return;
    }
    final summary = _buildKpiSummaryText(snapshot);
    try {
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          text: summary,
          subject:
              'Glanzpunkt KPI-Bericht (${_kpiPeriodLabel(snapshot.period)})',
        ),
      );
      if (!mounted) {
        return;
      }
      final statusLabel = shareResult.status == ShareResultStatus.success
          ? 'geteilt'
          : 'erstellt';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'KPI-Bericht (${_kpiPeriodLabel(snapshot.period)}) $statusLabel.',
          ),
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: summary));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'KPI-Bericht konnte nicht geteilt werden. In Zwischenablage kopiert.',
          ),
        ),
      );
    }
  }

  Future<void> _saveKpiCsvLocally() async {
    final snapshot = await _fetchKpiSnapshotForCurrentPeriod(
      showErrorSnack: true,
    );
    if (snapshot == null || !mounted) {
      return;
    }
    final fileName = _buildKpiExportFileName(snapshot.period);
    final csv = _buildKpiExportCsv(snapshot);
    Future<Directory> resolveDirectory() async {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return downloads;
        }
      } catch (_) {
        // fallback below
      }
      return getApplicationDocumentsDirectory();
    }

    try {
      final dir = await resolveDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv, flush: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'KPI-CSV lokal gespeichert (${_kpiPeriodLabel(snapshot.period)}).',
          ),
          action: SnackBarAction(
            label: 'Pfad kopieren',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
            },
          ),
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'KPI-CSV konnte nicht lokal gespeichert werden. In Zwischenablage kopiert.',
          ),
        ),
      );
    }
  }

  Widget _buildRecentErrorsCard({
    required BoxService boxService,
    required bool canAccess,
  }) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    final issues = boxService.recentSyncIssues(limit: 6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline),
                SizedBox(width: 8),
                Text(
                  'Letzte Fehler',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (issues.isEmpty)
              const Text(
                'Keine aktuellen Fehler in den letzten Synchronisationen.',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: issues.map((issue) {
                  final sourceLabel = _issueSourceLabel(issue.source);
                  final where = issue.boxNumber == null
                      ? sourceLabel
                      : '$sourceLabel • Box ${issue.boxNumber}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$where • ${_formatIssueAge(issue.timestamp)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          issue.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperatorActionLogCard({
    required bool canAccess,
    required BoxService boxService,
  }) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    final actions = _operatorActions;
    final boxIds = boxService.boxes.map((item) => item.number).toSet().toList()
      ..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                const Text(
                  'Operator Aktionen',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Log aktualisieren',
                  onPressed: _isRefreshingOperatorActions
                      ? null
                      : () => _triggerOperatorActionRefresh(resetPage: false),
                  icon: _isRefreshingOperatorActions
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'CSV lokal speichern',
                  onPressed: actions.isEmpty
                      ? null
                      : () => _saveOperatorActionsCsvLocally(actions),
                  icon: const Icon(Icons.save_alt_outlined),
                ),
                IconButton(
                  tooltip: 'CSV-Datei teilen',
                  onPressed: actions.isEmpty
                      ? null
                      : () => _exportOperatorActionsCsv(actions),
                  icon: const Icon(Icons.file_download_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _operatorActionSearchController,
              onChanged: (value) {
                setState(() {
                  _operatorActionSearchQuery = value;
                });
                _scheduleOperatorActionSearchRefresh();
              },
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _operatorActionSearchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche leeren',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _operatorActionSearchController.clear();
                          setState(() {
                            _operatorActionSearchQuery = '';
                          });
                          _triggerOperatorActionRefresh(resetPage: true);
                        },
                      ),
                labelText: 'Suche (Aktion, Box, Betreiber, Details)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _operatorActionStatusFilter == 'all',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionStatusFilter = 'all';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Erfolg'),
                  selected: _operatorActionStatusFilter == 'success',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionStatusFilter = 'success';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Teilweise'),
                  selected: _operatorActionStatusFilter == 'partial',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionStatusFilter = 'partial';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Fehler'),
                  selected: _operatorActionStatusFilter == 'failed',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionStatusFilter = 'failed';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Gesamt'),
                  selected: _operatorActionTimeFilter == 'all',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionTimeFilter = 'all';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('24h'),
                  selected: _operatorActionTimeFilter == '24h',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionTimeFilter = '24h';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('7 Tage'),
                  selected: _operatorActionTimeFilter == '7d',
                  onSelected: (_) {
                    setState(() {
                      _operatorActionTimeFilter = '7d';
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
                DropdownButton<int?>(
                  value: _operatorActionBoxFilter,
                  hint: const Text('Alle Boxen'),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Alle Boxen'),
                    ),
                    ...boxIds.map(
                      (boxId) => DropdownMenuItem<int?>(
                        value: boxId,
                        child: Text('Box $boxId'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _operatorActionBoxFilter = value;
                    });
                    _triggerOperatorActionRefresh(resetPage: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Treffer: ${actions.length}${_operatorActionsHasMore ? '+' : ''} • '
              'Zeitraum: ${_operatorActionTimeFilterLabel()} • '
              'Seite ${_operatorActionPage + 1}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _operatorActionPage > 0 && !_isRefreshingOperatorActions
                      ? () => _triggerOperatorActionRefresh(
                          resetPage: false,
                          page: _operatorActionPage - 1,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Zurueck'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      _operatorActionsHasMore && !_isRefreshingOperatorActions
                      ? () => _triggerOperatorActionRefresh(
                          resetPage: false,
                          page: _operatorActionPage + 1,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Weiter'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_operatorActionWarning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _operatorActionWarning!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            if (actions.isEmpty)
              Text(
                _operatorActionPage == 0
                    ? 'Noch keine Betreiberaktionen protokolliert.'
                    : 'Keine Treffer fuer die aktuelle Filterung.',
                style: const TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: actions.map((action) {
                  final accent = _operatorActionStatusColor(
                    action.actionStatus,
                  );
                  final actor = (action.actorEmail ?? '').trim().isNotEmpty
                      ? action.actorEmail!.trim()
                      : action.actorId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_operatorActionTitle(action.actionName)} • '
                          '${_operatorActionStatusLabel(action.actionStatus)} • '
                          '${_formatIssueAge(action.createdAt)}',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Von: $actor',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (action.boxId != null)
                          Text(
                            'Box: ${action.boxId}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        Text(
                          _formatActionDetails(action.details),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  DateTime? _lastCleaningAt(BoxService boxService, int boxNumber) {
    final events = boxService.timelineForBox(boxNumber);
    for (final event in events) {
      final title = event.title.toLowerCase();
      final details = (event.details ?? '').toLowerCase();
      final isCleaningEnded = title.contains('reinigung beendet');
      final isBackendTransitionToAvailable =
          title.contains('backend-status aktualisiert') &&
          details.contains('reinigung') &&
          details.contains('-> verfuegbar');
      if (isCleaningEnded || isBackendTransitionToAvailable) {
        return event.timestamp;
      }
    }
    return null;
  }

  int _washesSinceLastCleaning(
    BoxService boxService,
    int boxNumber,
    DateTime? lastCleaningAt,
  ) {
    final sessionsForBox = boxService.backendRecentSessions
        .where((session) => session.boxNumber == boxNumber)
        .toList();
    if (sessionsForBox.isNotEmpty) {
      return sessionsForBox.where((session) {
        if (lastCleaningAt == null) {
          return true;
        }
        return !session.startedAt.isBefore(lastCleaningAt);
      }).length;
    }

    // Fallback to local timeline when backend session history is empty.
    return boxService.timelineForBox(boxNumber).where((event) {
      if (lastCleaningAt != null && event.timestamp.isBefore(lastCleaningAt)) {
        return false;
      }
      final title = event.title.toLowerCase();
      return title.contains('session aktiv') ||
          title.contains('reward-session aktiv');
    }).length;
  }

  List<_BoxCleaningPlan> _buildCleaningPlans(BoxService boxService) {
    final sortedBoxes = List.of(boxService.boxes)
      ..sort((a, b) => a.number.compareTo(b.number));
    return sortedBoxes.map((box) {
      final remote = _remoteCleaningPlanByBox[box.number];
      if (remote != null) {
        return _BoxCleaningPlan(
          boxNumber: box.number,
          lastCleaningAt: remote.lastCleanedAt,
          washesSinceLastCleaning: remote.washesSinceCleaning,
          washesUntilNextCleaning: remote.washesUntilNextCleaning,
          dueNow: remote.isDue,
          fromBackend: true,
        );
      }
      final lastCleaningAt = _lastCleaningAt(boxService, box.number);
      final washesSinceLastCleaning = _washesSinceLastCleaning(
        boxService,
        box.number,
        lastCleaningAt,
      );
      final remaining = _cleaningIntervalWashes - washesSinceLastCleaning;
      return _BoxCleaningPlan(
        boxNumber: box.number,
        lastCleaningAt: lastCleaningAt,
        washesSinceLastCleaning: washesSinceLastCleaning,
        washesUntilNextCleaning: remaining > 0 ? remaining : 0,
        dueNow: remaining <= 0,
        fromBackend: false,
      );
    }).toList();
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

  String _readableError(Object error) {
    final text = '$error'.trim();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
    return text;
  }

  String _formatEuro(double value) {
    return '${value.toStringAsFixed(2)} EUR';
  }

  Color _alertSeverityColor(_OperatorAlertSeverity severity) {
    switch (severity) {
      case _OperatorAlertSeverity.critical:
        return Colors.redAccent;
      case _OperatorAlertSeverity.warning:
        return Colors.orangeAccent;
      case _OperatorAlertSeverity.info:
        return Colors.lightBlueAccent;
    }
  }

  List<_LongActiveBoxInfo> _findLongActiveBoxes(BoxService boxService) {
    final now = DateTime.now();
    final activeSessionsByBox = <int, WashSession>{};
    for (final session in boxService.backendRecentSessions) {
      final endedAt = session.endedAt;
      final isActive = endedAt == null || endedAt.isAfter(now);
      if (!isActive) {
        continue;
      }
      final current = activeSessionsByBox[session.boxNumber];
      if (current == null || session.startedAt.isAfter(current.startedAt)) {
        activeSessionsByBox[session.boxNumber] = session;
      }
    }

    final longActive = <_LongActiveBoxInfo>[];
    for (final box in boxService.boxes) {
      if (box.state != BoxState.active) {
        continue;
      }
      final session = activeSessionsByBox[box.number];
      if (session == null) {
        continue;
      }
      final age = now.difference(session.startedAt);
      if (age >= _longActiveSessionThreshold) {
        longActive.add(_LongActiveBoxInfo(boxNumber: box.number, age: age));
      }
    }
    longActive.sort((a, b) => b.age.compareTo(a.age));
    return longActive;
  }

  List<_OperatorAlertItem> _buildOperatorAlerts(BoxService boxService) {
    final alerts = <_OperatorAlertItem>[];
    final plans = _buildCleaningPlans(boxService);
    final duePlans = plans.where((plan) => plan.dueNow).toList();
    if (duePlans.isNotEmpty) {
      final dueBoxes = duePlans
          .take(4)
          .map((plan) => '${plan.boxNumber}')
          .join(', ');
      final overflow = duePlans.length > 4
          ? ' +${duePlans.length - 4} weitere'
          : '';
      alerts.add(
        _OperatorAlertItem(
          severity: duePlans.length >= 3
              ? _OperatorAlertSeverity.critical
              : _OperatorAlertSeverity.warning,
          title: 'Reinigung faellig',
          description:
              '${duePlans.length} Box(en) sind ueberfaellig. '
              'Betroffen: $dueBoxes$overflow.',
          actionLabel: 'Status neu laden',
          onTap: _isRefreshingCleaningPlan
              ? null
              : () => _refreshCleaningPlanData(showFeedback: true),
        ),
      );
    }

    final staleReservations = _monitoringSnapshot?.staleReservations ?? 0;
    if (staleReservations > 0) {
      alerts.add(
        _OperatorAlertItem(
          severity: _OperatorAlertSeverity.critical,
          title: 'Stale Reservierungen',
          description:
              '$staleReservations abgelaufene Reservierung(en) offen. '
              'Quick-Fix empfohlen.',
          actionLabel: 'Quick-Fix jetzt',
          onTap: _isApplyingQuickFix ? null : _runQuickFix,
        ),
      );
    }

    final longActiveBoxes = _findLongActiveBoxes(boxService);
    if (longActiveBoxes.isNotEmpty) {
      String ageLabel(Duration duration) {
        if (duration.inHours >= 1) {
          final h = duration.inHours;
          final m = duration.inMinutes % 60;
          return '${h}h ${m}m';
        }
        return '${duration.inMinutes}m';
      }

      final topBoxes = longActiveBoxes
          .take(4)
          .map((entry) => 'Box ${entry.boxNumber} (${ageLabel(entry.age)})')
          .join(', ');
      final overflow = longActiveBoxes.length > 4
          ? ' +${longActiveBoxes.length - 4} weitere'
          : '';
      alerts.add(
        _OperatorAlertItem(
          severity: _OperatorAlertSeverity.warning,
          title: 'Box lange aktiv',
          description:
              '${longActiveBoxes.length} Box(en) laenger als '
              '${_longActiveSessionThreshold.inMinutes} Minuten aktiv: '
              '$topBoxes$overflow.',
          actionLabel: 'Monitoring',
          onTap: () async {
            await Navigator.pushNamed(context, '/monitoring');
          },
        ),
      );
    }

    if (alerts.isEmpty) {
      alerts.add(
        _OperatorAlertItem(
          severity: _OperatorAlertSeverity.info,
          title: 'Keine akuten Warnungen',
          description:
              'Reinigung, Reservierungen und aktive Laufzeiten sind unauffaellig.',
        ),
      );
    }
    return alerts;
  }

  Widget _buildOperatorAlertsCard({
    required BoxService boxService,
    required bool canAccess,
  }) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    final alerts = _buildOperatorAlerts(boxService);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notification_important_outlined),
                SizedBox(width: 8),
                Text(
                  'Betriebswarnungen',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              children: alerts.map((alert) {
                final accent = _alertSeverityColor(alert.severity);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alert.description,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (alert.onTap != null && alert.actionLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: () => unawaited(alert.onTap!.call()),
                            child: Text(alert.actionLabel!),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _maintenanceAccent(_BoxCleaningPlan plan) {
    if (plan.dueNow) {
      return Colors.redAccent;
    }
    if (plan.washesUntilNextCleaning <= 10) {
      return Colors.orangeAccent;
    }
    return Colors.greenAccent;
  }

  String _readThresholdDetail(Map<String, dynamic> details, String key) {
    final value = details[key];
    if (value is num) {
      return value.toInt().toString();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '-';
  }

  Widget _buildThresholdAuditCard({required bool canAccess}) {
    if (!canAccess) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Threshold-Historie'),
          subtitle: const Text(
            'Nur Betreiber/Inhaber koennen Threshold-Aenderungen einsehen.',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Threshold-Historie',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Threshold-Historie aktualisieren',
                  onPressed: _isRefreshingThresholdAudit
                      ? null
                      : () {
                          final auth = context.read<AuthService>();
                          final jwt = auth.backendJwt;
                          if (jwt == null || jwt.isEmpty) {
                            return;
                          }
                          final baseUrl = context
                              .read<EnvironmentService>()
                              .activeBaseUrl;
                          unawaited(
                            _refreshThresholdAuditCache(
                              baseUrl: baseUrl,
                              jwt: jwt,
                            ),
                          );
                        },
                  icon: _isRefreshingThresholdAudit
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_thresholdAuditWarning != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _thresholdAuditWarning!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            const SizedBox(height: 8),
            if (_thresholdAuditActions.isEmpty)
              const Text('Keine Threshold-Aenderungen erfasst.')
            else
              Column(
                children: _thresholdAuditActions.map((action) {
                  final details = action.details;
                  final beforeWashes = _readThresholdDetail(
                    details,
                    'beforeCleaningIntervalWashes',
                  );
                  final afterWashes = _readThresholdDetail(
                    details,
                    'afterCleaningIntervalWashes',
                  );
                  final beforeMinutes = _readThresholdDetail(
                    details,
                    'beforeLongActiveMinutes',
                  );
                  final afterMinutes = _readThresholdDetail(
                    details,
                    'afterLongActiveMinutes',
                  );
                  final actor = (action.actorEmail ?? '').trim().isNotEmpty
                      ? action.actorEmail!.trim()
                      : action.actorId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatDateTime(action.createdAt)} • $actor',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Intervall: $beforeWashes -> $afterWashes Waeschen',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Long-Active: $beforeMinutes -> $afterMinutes Minuten',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Quelle: ${action.source}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleaningPlanCard({
    required BoxService boxService,
    required bool canAccess,
    required bool canEditThresholds,
  }) {
    if (!canAccess) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Reinigungsintervall'),
          subtitle: const Text(
            'Nur Betreiber/Inhaber koennen Reinigungsdaten einsehen.',
          ),
        ),
      );
    }

    final plans = _buildCleaningPlans(boxService);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reinigungsintervall: alle $_cleaningIntervalWashes Waeschen',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Reinigungsdaten aktualisieren',
                  onPressed: _isRefreshingCleaningPlan
                      ? null
                      : () => _refreshCleaningPlanData(showFeedback: true),
                  icon: _isRefreshingCleaningPlan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Thresholds bearbeiten',
                  onPressed: _isSavingThresholdSettings || !canEditThresholds
                      ? null
                      : _editThresholdSettings,
                  icon: _isSavingThresholdSettings
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _remoteCleaningPlanByBox.isNotEmpty
                  ? 'Quelle: Backend (persistente Reinigungsdaten).'
                  : 'Quelle: Lokale Verlaufdaten.',
              style: TextStyle(
                color: _remoteCleaningPlanByBox.isNotEmpty
                    ? Colors.white70
                    : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Long-Active-Warnung ab ${_longActiveSessionThreshold.inMinutes} Minuten.',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              canEditThresholds
                  ? 'Bearbeitung: Inhaber-Modus aktiv.'
                  : 'Bearbeitung: nur fuer Inhaber freigeschaltet.',
              style: TextStyle(
                color: canEditThresholds ? Colors.white54 : Colors.orangeAccent,
              ),
            ),
            if (_thresholdSettingsUpdatedAt != null)
              Text(
                'Threshold-Stand: ${_formatDateTime(_thresholdSettingsUpdatedAt!)}',
                style: const TextStyle(color: Colors.white54),
              ),
            if (_cleaningPlanWarning != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _cleaningPlanWarning!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            const SizedBox(height: 10),
            if (plans.isEmpty)
              const Text('Keine Boxdaten verfuegbar.')
            else
              Column(
                children: plans.map((plan) {
                  final accent = _maintenanceAccent(plan);
                  final intervalForProgress = _cleaningIntervalWashes > 0
                      ? _cleaningIntervalWashes
                      : 1;
                  final progress =
                      (plan.washesSinceLastCleaning / intervalForProgress)
                          .clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.65)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Box ${plan.boxNumber}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        FilledButton.icon(
                          onPressed:
                              _markingCleanedBoxes.contains(plan.boxNumber)
                              ? null
                              : () => _markBoxCleaned(plan.boxNumber),
                          icon: _markingCleanedBoxes.contains(plan.boxNumber)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.task_alt),
                          label: Text(
                            _markingCleanedBoxes.contains(plan.boxNumber)
                                ? 'Speichere...'
                                : 'Reinigung durchgefuehrt',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan.lastCleaningAt == null
                              ? 'Letzte Reinigung: nicht erfasst'
                              : 'Letzte Reinigung: ${_formatDateTime(plan.lastCleaningAt!)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Waeschen seit letzter Reinigung: '
                          '${plan.washesSinceLastCleaning}/$_cleaningIntervalWashes',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          plan.dueNow
                              ? 'Naechste Reinigung: jetzt faellig'
                              : 'Naechste Reinigung in ${plan.washesUntilNextCleaning} Waeschen',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!plan.fromBackend)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'Geschaetzt aus lokaler Historie',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: progress,
                            color: accent,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleaningHistoryCard({required bool canAccess}) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history_toggle_off),
                SizedBox(width: 8),
                Text(
                  'Letzte Reinigungen',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_cleaningHistory.isEmpty)
              const Text(
                'Noch keine Reinigungsereignisse vorhanden.',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: _cleaningHistory.take(8).map((entry) {
                  final performedBy =
                      (entry.performedByEmail ?? '').trim().isNotEmpty
                      ? entry.performedByEmail!.trim()
                      : entry.performedBy;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Box ${entry.boxId} • ${_formatDateTime(entry.cleanedAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Durchgefuehrt von: $performedBy',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Zaehler vor Reinigung: ${entry.washesBefore}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (entry.note != null)
                          Text(
                            'Notiz: ${entry.note}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiOverviewCard({
    required BoxService boxService,
    required bool canAccess,
  }) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    final boxes = boxService.boxes;
    final plans = _buildCleaningPlans(boxService);
    final monitoring = _monitoringSnapshot;
    final now = DateTime.now();
    final activeSessionsLocal = boxService.backendRecentSessions.where((
      session,
    ) {
      final endedAt = session.endedAt;
      return endedAt == null || endedAt.isAfter(now);
    }).length;
    final activeSessions = monitoring?.activeSessions ?? activeSessionsLocal;
    final sessions24h =
        monitoring?.sessionsLast24h ??
        boxService.backendRecentSessions.where((session) {
          return session.startedAt.isAfter(
            now.subtract(const Duration(hours: 24)),
          );
        }).length;
    final washRevenueToday = monitoring?.washRevenueTodayEur;
    final washRevenue24h = monitoring?.washRevenue24hEur;
    final dueNow = plans.where((plan) => plan.dueNow).length;
    final dueSoon = plans.where((plan) {
      return !plan.dueNow && plan.washesUntilNextCleaning <= 10;
    }).length;
    final syncIssueCount = boxService.recentSyncIssues(limit: 40).length;
    final kpiPreview =
        (_kpiPreviewSnapshot != null &&
            _kpiPreviewSnapshot!.period == _kpiExportPeriod)
        ? _kpiPreviewSnapshot
        : null;

    int count(BoxState state) {
      return boxes.where((box) => box.state == state).length;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.space_dashboard_outlined),
                const SizedBox(width: 8),
                const Text(
                  'Betriebsuebersicht',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'KPI-Bericht teilen',
                  onPressed: _isExportingKpi ? null : _shareKpiSummary,
                  icon: const Icon(Icons.share_outlined),
                ),
                IconButton(
                  tooltip: 'KPI-Bericht kopieren',
                  onPressed: _isExportingKpi
                      ? null
                      : _copyKpiSummaryToClipboard,
                  icon: const Icon(Icons.assignment_outlined),
                ),
                IconButton(
                  tooltip: 'KPI CSV lokal speichern',
                  onPressed: _isExportingKpi ? null : _saveKpiCsvLocally,
                  icon: _isExportingKpi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_outlined),
                ),
                IconButton(
                  tooltip: 'KPI CSV teilen',
                  onPressed: _isExportingKpi ? null : _shareKpiCsv,
                  icon: const Icon(Icons.ios_share_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tag'),
                  selected: _kpiExportPeriod == 'day',
                  onSelected: (_) {
                    setState(() {
                      _kpiExportPeriod = 'day';
                    });
                    unawaited(
                      _fetchKpiSnapshotForCurrentPeriod(showErrorSnack: false),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Woche'),
                  selected: _kpiExportPeriod == 'week',
                  onSelected: (_) {
                    setState(() {
                      _kpiExportPeriod = 'week';
                    });
                    unawaited(
                      _fetchKpiSnapshotForCurrentPeriod(showErrorSnack: false),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Monat'),
                  selected: _kpiExportPeriod == 'month',
                  onSelected: (_) {
                    setState(() {
                      _kpiExportPeriod = 'month';
                    });
                    unawaited(
                      _fetchKpiSnapshotForCurrentPeriod(showErrorSnack: false),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'KPI-Exportzeitraum: ${_kpiPeriodLabel(_kpiExportPeriod)} ($_kpiBusinessTimeZone)',
              style: const TextStyle(color: Colors.white70),
            ),
            if (kpiPreview != null)
              Text(
                'Export-Vorschau: Sessions ${kpiPreview.sessionsStarted}, '
                'Umsatz ${_formatEuro(kpiPreview.washRevenueEur)}, '
                'Top-up ${_formatEuro(kpiPreview.topUpRevenueEur)}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (kpiPreview != null)
              Text(
                _buildKpiDeltaSummary(kpiPreview),
                style: const TextStyle(color: Colors.white70),
              ),
            if (kpiPreview != null)
              Text(
                'Fenster: ${_kpiWindowLabel(kpiPreview)}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (kpiPreview != null)
              Text(
                'Generiert: ${_formatDateTime(kpiPreview.generatedAt)}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (_kpiExportWarning != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _kpiExportWarning!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildKpiTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Boxen gesamt',
                  value: '${boxes.length}',
                  color: Colors.white70,
                ),
                _buildKpiTile(
                  icon: Icons.check_circle_outline,
                  label: 'Verfuegbar',
                  value: '${count(BoxState.available)}',
                  color: Colors.greenAccent,
                ),
                _buildKpiTile(
                  icon: Icons.play_circle_outline,
                  label: 'Aktiv',
                  value: '${count(BoxState.active)}',
                  color: Colors.redAccent,
                ),
                _buildKpiTile(
                  icon: Icons.lock_clock_outlined,
                  label: 'Reserviert',
                  value: '${count(BoxState.reserved)}',
                  color: Colors.blueAccent,
                ),
                _buildKpiTile(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Reinigung',
                  value: '${count(BoxState.cleaning)}',
                  color: Colors.orangeAccent,
                ),
                _buildKpiTile(
                  icon: Icons.do_not_disturb_alt_outlined,
                  label: 'Ausser Betrieb',
                  value: '${count(BoxState.outOfService)}',
                  color: Colors.grey,
                ),
                _buildKpiTile(
                  icon: Icons.timelapse_outlined,
                  label: 'Sessions aktiv',
                  value: '$activeSessions',
                  color: Colors.tealAccent,
                ),
                _buildKpiTile(
                  icon: Icons.history,
                  label: 'Sessions 24h',
                  value: '$sessions24h',
                  color: Colors.cyanAccent,
                ),
                _buildKpiTile(
                  icon: Icons.euro,
                  label: 'Umsatz heute',
                  value: washRevenueToday == null
                      ? '-'
                      : _formatEuro(washRevenueToday),
                  color: Colors.lightGreenAccent,
                ),
                _buildKpiTile(
                  icon: Icons.payments_outlined,
                  label: 'Umsatz 24h',
                  value: washRevenue24h == null
                      ? '-'
                      : _formatEuro(washRevenue24h),
                  color: Colors.lightGreenAccent,
                ),
                _buildKpiTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Top-up heute',
                  value: monitoring == null
                      ? '-'
                      : _formatEuro(monitoring.topUpTodayEur),
                  color: Colors.lightBlueAccent,
                ),
                _buildKpiTile(
                  icon: Icons.warning_amber_outlined,
                  label: 'Reinigung faellig',
                  value: '$dueNow',
                  color: dueNow > 0 ? Colors.redAccent : Colors.greenAccent,
                ),
                _buildKpiTile(
                  icon: Icons.schedule_outlined,
                  label: 'Reinigung bald',
                  value: '$dueSoon',
                  color: dueSoon > 0 ? Colors.orangeAccent : Colors.greenAccent,
                ),
                _buildKpiTile(
                  icon: Icons.error_outline,
                  label: 'Sync-Fehler',
                  value: '$syncIssueCount',
                  color: syncIssueCount > 0
                      ? Colors.orangeAccent
                      : Colors.greenAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  BoxTimelineEvent? _latestTimelineEventForBox(
    BoxService boxService,
    int boxNumber,
  ) {
    final events = boxService.timelineForBox(boxNumber);
    if (events.isEmpty) {
      return null;
    }
    return events.first;
  }

  BoxSyncIssue? _latestIssueForBox(BoxService boxService, int boxNumber) {
    for (final issue in boxService.recentSyncIssues(limit: 40)) {
      if (issue.boxNumber == boxNumber) {
        return issue;
      }
    }
    return null;
  }

  WashSession? _latestSessionForBox(BoxService boxService, int boxNumber) {
    for (final session in boxService.backendRecentSessions) {
      if (session.boxNumber == boxNumber) {
        return session;
      }
    }
    return null;
  }

  Widget _buildBoxRuntimeInsightsCard({
    required BoxService boxService,
    required bool canAccess,
  }) {
    if (!canAccess) {
      return const SizedBox.shrink();
    }
    final boxes = List.of(boxService.boxes)
      ..sort((a, b) => a.number.compareTo(b.number));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.view_list_outlined),
                SizedBox(width: 8),
                Text(
                  'Box-Details kompakt',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (boxes.isEmpty)
              const Text('Keine Boxdaten verfuegbar.')
            else
              Column(
                children: boxes.map((box) {
                  final lastEvent = _latestTimelineEventForBox(
                    boxService,
                    box.number,
                  );
                  final lastSession = _latestSessionForBox(
                    boxService,
                    box.number,
                  );
                  final lastIssue = _latestIssueForBox(boxService, box.number);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Box ${box.number} • Status: ${box.state.label}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastEvent == null
                              ? 'Letzte Aktion: -'
                              : 'Letzte Aktion: ${lastEvent.title} (${_formatIssueAge(lastEvent.timestamp)})',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          lastSession == null
                              ? 'Letzte Session: -'
                              : 'Letzte Session: ${_formatDateTime(lastSession.startedAt)}'
                                    '${lastSession.endedAt == null ? '' : ' bis ${_formatDateTime(lastSession.endedAt!)}'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          lastIssue == null
                              ? 'Letzter Fehler: -'
                              : 'Letzter Fehler: ${_issueSourceLabel(lastIssue.source)} (${_formatIssueAge(lastIssue.timestamp)})',
                          style: TextStyle(
                            color: lastIssue == null
                                ? Colors.white70
                                : Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final boxService = context.watch<BoxService>();
    final canAccess = auth.hasOperatorAccess;
    final canEditThresholds = auth.profileRole == AccountRole.owner;

    return Scaffold(
      appBar: AppBar(title: const Text('Betreiber Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: canAccess ? Colors.white10 : Colors.red.shade900,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    canAccess ? Icons.verified_user : Icons.lock_outline,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      canAccess
                          ? 'Rolle: ${_roleLabel(auth.profileRole)}'
                          : 'Kein Zugriff: Nur Betreiber/Inhaber.',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildKpiOverviewCard(boxService: boxService, canAccess: canAccess),
          const SizedBox(height: 8),
          _buildOperatorAlertsCard(
            boxService: boxService,
            canAccess: canAccess,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('System Monitoring'),
              subtitle: const Text(
                'Live-Status fuer Boxen, Sessions und Reservierungen',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: canAccess,
              onTap: canAccess
                  ? () => Navigator.pushNamed(context, '/monitoring')
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: _isApplyingQuickFix
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.build_circle_outlined),
              title: const Text('Quick-Fix jetzt'),
              subtitle: const Text('Stale Reservierungen und haengende Boxen'),
              enabled: canAccess && !_isApplyingQuickFix,
              onTap: (canAccess && !_isApplyingQuickFix) ? _runQuickFix : null,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: _isRefreshingCleaningPlan
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              title: const Text('Status neu laden'),
              subtitle: const Text(
                'Boxen, Sessions und Fehlerstatus sofort neu synchronisieren',
              ),
              enabled: canAccess && !_isRefreshingCleaningPlan,
              onTap: (canAccess && !_isRefreshingCleaningPlan)
                  ? () => _refreshCleaningPlanData(showFeedback: true)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          _buildCleaningPlanCard(
            boxService: boxService,
            canAccess: canAccess,
            canEditThresholds: canEditThresholds,
          ),
          const SizedBox(height: 8),
          _buildThresholdAuditCard(canAccess: canAccess),
          const SizedBox(height: 8),
          _buildCleaningHistoryCard(canAccess: canAccess),
          const SizedBox(height: 8),
          _buildBoxRuntimeInsightsCard(
            boxService: boxService,
            canAccess: canAccess,
          ),
          const SizedBox(height: 8),
          _buildOperatorActionLogCard(
            canAccess: canAccess,
            boxService: boxService,
          ),
          const SizedBox(height: 8),
          _buildRecentErrorsCard(boxService: boxService, canAccess: canAccess),
        ],
      ),
    );
  }
}

class _BoxCleaningPlan {
  final int boxNumber;
  final DateTime? lastCleaningAt;
  final int washesSinceLastCleaning;
  final int washesUntilNextCleaning;
  final bool dueNow;
  final bool fromBackend;

  const _BoxCleaningPlan({
    required this.boxNumber,
    required this.lastCleaningAt,
    required this.washesSinceLastCleaning,
    required this.washesUntilNextCleaning,
    required this.dueNow,
    required this.fromBackend,
  });
}

enum _OperatorAlertSeverity { critical, warning, info }

class _OperatorAlertItem {
  final _OperatorAlertSeverity severity;
  final String title;
  final String description;
  final String? actionLabel;
  final Future<void> Function()? onTap;

  const _OperatorAlertItem({
    required this.severity,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onTap,
  });
}

class _LongActiveBoxInfo {
  final int boxNumber;
  final Duration age;

  const _LongActiveBoxInfo({required this.boxNumber, required this.age});
}

class _ThresholdDialogInput {
  final int cleaningIntervalWashes;
  final int longActiveMinutes;

  const _ThresholdDialogInput({
    required this.cleaningIntervalWashes,
    required this.longActiveMinutes,
  });
}
