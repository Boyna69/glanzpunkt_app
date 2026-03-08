import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_service.dart';
import '../services/backend_http_client.dart';
import '../services/environment_service.dart';
import '../services/ops_maintenance_service.dart';

enum UatInboxStatus { open, inProgress, fixed, retest, closed }

enum UatInboxSeverity { critical, high, medium, low }

class UatInboxItem {
  final String id;
  final UatInboxSeverity severity;
  final String area;
  final String summary;
  final UatInboxStatus status;
  final String owner;
  final String targetBuild;
  final DateTime createdAt;

  const UatInboxItem({
    required this.id,
    required this.severity,
    required this.area,
    required this.summary,
    required this.status,
    required this.owner,
    required this.targetBuild,
    required this.createdAt,
  });
}

class UatInboxScreen extends StatefulWidget {
  const UatInboxScreen({super.key});

  @override
  State<UatInboxScreen> createState() => _UatInboxScreenState();
}

class _UatInboxScreenState extends State<UatInboxScreen> {
  late final OpsMaintenanceService _opsMaintenance;
  bool _isLoading = false;
  bool _usingFallbackFeed = false;
  String? _warning;
  List<UatInboxItem> _items = const <UatInboxItem>[];

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
      _reloadInbox();
    });
  }

  Future<void> _reloadInbox() async {
    if (!mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      setState(() {
        _isLoading = false;
        _usingFallbackFeed = false;
        _items = const <UatInboxItem>[];
        _warning = 'UAT Inbox ist nur mit Betreiber-Session verfuegbar.';
      });
      return;
    }

    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
    setState(() {
      _isLoading = true;
      _warning = null;
    });

    try {
      var rows = await _opsMaintenance.fetchOperatorActions(
        baseUrl: baseUrl,
        jwt: jwt,
        maxRows: 40,
        searchQuery: 'uat',
      );
      var usingFallback = false;
      if (rows.isEmpty) {
        rows = await _opsMaintenance.fetchOperatorActions(
          baseUrl: baseUrl,
          jwt: jwt,
          maxRows: 40,
        );
        usingFallback = true;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _items = rows.map(_mapFromOperatorAction).toList();
        _usingFallbackFeed = usingFallback;
        _warning = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <UatInboxItem>[];
        _usingFallbackFeed = false;
        _warning = 'UAT Inbox konnte nicht geladen werden. ($e)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  UatInboxItem _mapFromOperatorAction(OpsOperatorActionItem action) {
    final details = action.details;
    final statusFromDetails = _firstText(details, <String>[
      'uat_status',
      'status',
    ]);
    final severityFromDetails = _firstText(details, <String>[
      'severity',
      'priority',
    ]);
    final targetBuild =
        _firstText(details, <String>['target_build', 'build', 'release']) ??
        '-';

    final summary =
        _firstText(details, <String>[
          'summary',
          'title',
          'note',
          'message',
          'description',
        ]) ??
        '${_humanize(action.actionName)} (${action.actionStatus})';

    final area =
        _firstText(details, <String>['area', 'module']) ??
        (action.boxId != null
            ? 'Box ${action.boxId}'
            : _humanize(action.actionName));

    final owner = (action.actorEmail?.trim().isNotEmpty ?? false)
        ? action.actorEmail!.trim()
        : action.actorId;

    return UatInboxItem(
      id: 'LOG-${action.id}',
      severity: _mapSeverity(
        status: action.actionStatus,
        severity: severityFromDetails,
      ),
      area: area,
      summary: summary,
      status: _mapStatus(statusFromDetails, action.actionStatus),
      owner: owner,
      targetBuild: targetBuild,
      createdAt: action.createdAt,
    );
  }

  UatInboxStatus _mapStatus(String? rawStatus, String actionStatus) {
    final normalized = _normalize(rawStatus);
    switch (normalized) {
      case 'open':
        return UatInboxStatus.open;
      case 'in_progress':
      case 'inprogress':
        return UatInboxStatus.inProgress;
      case 'fixed':
        return UatInboxStatus.fixed;
      case 'retest':
        return UatInboxStatus.retest;
      case 'closed':
        return UatInboxStatus.closed;
    }

    final normalizedActionStatus = _normalize(actionStatus);
    if (normalizedActionStatus == 'success') {
      return UatInboxStatus.closed;
    }
    if (normalizedActionStatus == 'partial' ||
        normalizedActionStatus == 'warning') {
      return UatInboxStatus.inProgress;
    }
    return UatInboxStatus.open;
  }

  UatInboxSeverity _mapSeverity({
    required String status,
    required String? severity,
  }) {
    final normalized = _normalize(severity);
    switch (normalized) {
      case 'critical':
      case 'p0':
        return UatInboxSeverity.critical;
      case 'high':
      case 'p1':
        return UatInboxSeverity.high;
      case 'medium':
      case 'p2':
        return UatInboxSeverity.medium;
      case 'low':
      case 'p3':
        return UatInboxSeverity.low;
    }

    final normalizedStatus = _normalize(status);
    if (normalizedStatus == 'failed' ||
        normalizedStatus == 'error' ||
        normalizedStatus == 'forbidden' ||
        normalizedStatus == 'timeout') {
      return UatInboxSeverity.high;
    }
    if (normalizedStatus == 'partial' || normalizedStatus == 'warning') {
      return UatInboxSeverity.medium;
    }
    return UatInboxSeverity.low;
  }

  String? _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
    }
    return null;
  }

  String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _humanize(String raw) {
    final normalized = raw.trim().replaceAll('_', ' ').replaceAll('-', ' ');
    if (normalized.isEmpty) {
      return '-';
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _statusLabel(UatInboxStatus status) {
    switch (status) {
      case UatInboxStatus.open:
        return 'open';
      case UatInboxStatus.inProgress:
        return 'in_progress';
      case UatInboxStatus.fixed:
        return 'fixed';
      case UatInboxStatus.retest:
        return 'retest';
      case UatInboxStatus.closed:
        return 'closed';
    }
  }

  Color _statusColor(UatInboxStatus status) {
    switch (status) {
      case UatInboxStatus.open:
        return Colors.orange.shade400;
      case UatInboxStatus.inProgress:
        return Colors.blue.shade300;
      case UatInboxStatus.fixed:
        return Colors.green.shade400;
      case UatInboxStatus.retest:
        return Colors.purple.shade300;
      case UatInboxStatus.closed:
        return Colors.grey.shade400;
    }
  }

  String _severityLabel(UatInboxSeverity severity) {
    switch (severity) {
      case UatInboxSeverity.critical:
        return 'critical';
      case UatInboxSeverity.high:
        return 'high';
      case UatInboxSeverity.medium:
        return 'medium';
      case UatInboxSeverity.low:
        return 'low';
    }
  }

  Color _severityColor(UatInboxSeverity severity) {
    switch (severity) {
      case UatInboxSeverity.critical:
        return Colors.red.shade500;
      case UatInboxSeverity.high:
        return Colors.red.shade300;
      case UatInboxSeverity.medium:
        return Colors.amber.shade400;
      case UatInboxSeverity.low:
        return Colors.lightGreen.shade400;
    }
  }

  int _countByStatus(UatInboxStatus status) {
    return _items.where((item) => item.status == status).length;
  }

  Future<void> _copyTemplateRow(BuildContext context) async {
    const template =
        '| UAT-XXX | high | customer/operator | area | kurzbeschreibung | '
        'ja/nein | open | owner | target-build |';
    await Clipboard.setData(const ClipboardData(text: template));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Triage-Template in Zwischenablage kopiert.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UAT Inbox'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _isLoading ? null : _reloadInbox,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadInbox,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_isLoading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_warning != null)
                Card(
                  color: Colors.red.shade900.withValues(alpha: 0.35),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('UAT Inbox nicht verfuegbar'),
                    subtitle: Text(_warning!),
                    trailing: TextButton(
                      onPressed: _reloadInbox,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              if (_usingFallbackFeed && _warning == null)
                Card(
                  color: Colors.orange.shade900.withValues(alpha: 0.25),
                  child: const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Fallback aktiv'),
                    subtitle: Text(
                      'Keine "uat"-markierten Eintraege gefunden. '
                      'Es werden die letzten Betreiberaktionen angezeigt.',
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          'open ${_countByStatus(UatInboxStatus.open)}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'in_progress ${_countByStatus(UatInboxStatus.inProgress)}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'retest ${_countByStatus(UatInboxStatus.retest)}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'closed ${_countByStatus(UatInboxStatus.closed)}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: const Text('Neue Triage-Zeile kopieren'),
                  subtitle: const Text(
                    'Template fuer /docs/internal_uat_triage_board.md',
                  ),
                  onTap: () => _copyTemplateRow(context),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Aktuelle Punkte',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: const Text('Keine UAT-Eintraege vorhanden'),
                    subtitle: const Text(
                      'Lege Eintraege ueber den UAT-Logging-Helper an '
                      '(Details mit uat_status/severity).',
                    ),
                  ),
                ),
              ..._items.map((item) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text('${item.id} - ${item.summary}'),
                    subtitle: Text(
                      'Bereich: ${item.area}\n'
                      'Owner: ${item.owner} | Build: ${item.targetBuild}\n'
                      'Zeit: ${item.createdAt.toLocal().toIso8601String()}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(
                              item.status,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(item.status),
                            style: TextStyle(color: _statusColor(item.status)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _severityColor(
                              item.severity,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _severityLabel(item.severity),
                            style: TextStyle(
                              color: _severityColor(item.severity),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
