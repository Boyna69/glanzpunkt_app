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
  final int ticketId;
  final String id;
  final UatInboxSeverity severity;
  final String area;
  final String summary;
  final UatInboxStatus status;
  final String owner;
  final String targetBuild;
  final DateTime createdAt;

  const UatInboxItem({
    required this.ticketId,
    required this.id,
    required this.severity,
    required this.area,
    required this.summary,
    required this.status,
    required this.owner,
    required this.targetBuild,
    required this.createdAt,
  });

  UatInboxItem copyWith({
    UatInboxSeverity? severity,
    UatInboxStatus? status,
    String? owner,
    String? targetBuild,
  }) {
    return UatInboxItem(
      ticketId: ticketId,
      id: id,
      severity: severity ?? this.severity,
      area: area,
      summary: summary,
      status: status ?? this.status,
      owner: owner ?? this.owner,
      targetBuild: targetBuild ?? this.targetBuild,
      createdAt: createdAt,
    );
  }
}

class _UatTicketTimelineEvent {
  final int id;
  final String actionName;
  final String actionStatus;
  final String actor;
  final String source;
  final String? note;
  final DateTime createdAt;

  const _UatTicketTimelineEvent({
    required this.id,
    required this.actionName,
    required this.actionStatus,
    required this.actor,
    required this.source,
    required this.note,
    required this.createdAt,
  });
}

class UatInboxScreen extends StatefulWidget {
  final OpsMaintenanceService? maintenanceService;

  const UatInboxScreen({super.key, this.maintenanceService});

  @override
  State<UatInboxScreen> createState() => _UatInboxScreenState();
}

class _UatInboxScreenState extends State<UatInboxScreen> {
  static const String _defaultTargetBuild = 'current';
  static const String _ownerFilterUnassignedKey = '__unassigned__';

  late final OpsMaintenanceService _opsMaintenance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isCreatingEntry = false;
  bool _usingFallbackFeed = false;
  bool _showOnlyOpen = false;
  String? _warning;
  UatInboxStatus? _statusFilter;
  UatInboxSeverity? _severityFilter;
  String? _ownerFilter;
  List<UatInboxItem> _items = const <UatInboxItem>[];
  List<OpsOperatorActionItem> _rawRows = const <OpsOperatorActionItem>[];

  @override
  void initState() {
    super.initState();
    _opsMaintenance = widget.maintenanceService ?? _createOpsService();
    _searchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadInbox();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  OpsMaintenanceService _createOpsService() {
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
    return OpsMaintenanceService(httpClient: client);
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
        _rawRows = const <OpsOperatorActionItem>[];
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
        maxRows: 60,
        searchQuery: 'uat',
      );
      var usingFallback = false;
      if (rows.isEmpty) {
        rows = await _opsMaintenance.fetchOperatorActions(
          baseUrl: baseUrl,
          jwt: jwt,
          maxRows: 60,
        );
        usingFallback = true;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _rawRows = rows;
        _items = _buildUatItems(rows);
        _usingFallbackFeed = usingFallback;
        _warning = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <UatInboxItem>[];
        _rawRows = const <OpsOperatorActionItem>[];
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

  List<UatInboxItem> _filteredItems() {
    var rows = _items;
    if (_showOnlyOpen) {
      rows = rows.where((item) => _isOpenStatus(item.status)).toList();
    }
    if (_statusFilter != null) {
      rows = rows.where((item) => item.status == _statusFilter).toList();
    }
    if (_severityFilter != null) {
      rows = rows.where((item) => item.severity == _severityFilter).toList();
    }
    if (_ownerFilter != null) {
      rows = rows
          .where((item) => _matchesOwnerFilter(item, _ownerFilter!))
          .toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((item) {
        final haystack =
            '${item.id} ${item.summary} ${item.area} ${item.owner} '
                    '${item.targetBuild} ${_statusLabel(item.status)} '
                    '${_severityLabel(item.severity)}'
                .toLowerCase();
        return haystack.contains(query);
      }).toList();
    }
    return rows;
  }

  bool _matchesOwnerFilter(UatInboxItem item, String ownerFilter) {
    final normalizedOwnerFilter = ownerFilter.trim().toLowerCase();
    final normalizedOwner = item.owner.trim().toLowerCase();
    if (normalizedOwnerFilter == _ownerFilterUnassignedKey) {
      return normalizedOwner.isEmpty || normalizedOwner == '-';
    }
    return normalizedOwner == normalizedOwnerFilter;
  }

  List<String> _availableOwners() {
    final owners =
        _items
            .map((item) => item.owner.trim())
            .where((owner) => owner.isNotEmpty && owner != '-')
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return owners;
  }

  bool _isOpenStatus(UatInboxStatus status) {
    return status == UatInboxStatus.open ||
        status == UatInboxStatus.inProgress ||
        status == UatInboxStatus.retest;
  }

  (String, String)? _readOperatorSession() {
    final auth = context.read<AuthService>();
    final jwt = auth.backendJwt;
    if (!auth.hasOperatorAccess || jwt == null || jwt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nur mit gueltiger Betreiber-Session moeglich.'),
        ),
      );
      return null;
    }
    final baseUrl = context.read<EnvironmentService>().activeBaseUrl;
    return (baseUrl, jwt);
  }

  Future<void> _openSetTicketStatusDialog(UatInboxItem item) async {
    final session = _readOperatorSession();
    if (session == null) {
      return;
    }

    var selectedStatus = item.status;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Status setzen (${item.id})'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<UatInboxStatus>(
                  key: ValueKey('uat_set_status_${item.ticketId}'),
                  initialValue: selectedStatus,
                  items: UatInboxStatus.values.map((status) {
                    return DropdownMenuItem<UatInboxStatus>(
                      value: status,
                      child: Text(_statusLabel(status)),
                    );
                  }).toList(),
                  decoration: const InputDecoration(
                    labelText: 'Neuer Status',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() {
                      selectedStatus = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  key: ValueKey('uat_set_status_note_${item.ticketId}'),
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notiz (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _opsMaintenance.setUatTicketStatus(
        baseUrl: session.$1,
        jwt: session.$2,
        ticketId: item.ticketId,
        uatStatus: _toOpsUatStatus(selectedStatus),
        note: noteController.text.trim(),
      );
      await _reloadInbox();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status fuer ${item.id} aktualisiert.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Status konnte nicht gesetzt werden: $e'),
        ),
      );
    }
  }

  Future<void> _openAssignOwnerDialog(UatInboxItem item) async {
    final session = _readOperatorSession();
    if (session == null) {
      return;
    }

    final ownerController = TextEditingController(
      text: item.owner == '-' ? '' : item.owner,
    );
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Owner setzen (${item.id})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: ValueKey('uat_set_owner_email_${item.ticketId}'),
                controller: ownerController,
                decoration: const InputDecoration(
                  labelText: 'Owner E-Mail',
                  hintText: 'leer lassen = Owner entfernen',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: ValueKey('uat_set_owner_note_${item.ticketId}'),
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final ownerEmail = ownerController.text.trim();
      await _opsMaintenance.assignUatTicketOwner(
        baseUrl: session.$1,
        jwt: session.$2,
        ticketId: item.ticketId,
        ownerEmail: ownerEmail.isEmpty ? null : ownerEmail,
        note: noteController.text.trim(),
      );
      await _reloadInbox();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Owner fuer ${item.id} aktualisiert.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Owner konnte nicht gesetzt werden: $e'),
        ),
      );
    }
  }

  Future<void> _openCreateUatEntryDialog() async {
    if (_isCreatingEntry || !mounted) {
      return;
    }
    final session = _readOperatorSession();
    if (session == null) {
      return;
    }
    final baseUrl = session.$1;
    final jwt = session.$2;
    final summaryController = TextEditingController();
    final areaController = TextEditingController(text: 'operator_dashboard');
    final buildController = TextEditingController(text: _defaultTargetBuild);
    final boxIdController = TextEditingController();
    var selectedStatus = UatInboxStatus.open;
    var selectedSeverity = UatInboxSeverity.medium;
    String? validationError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('UAT-Eintrag erfassen'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('uat_create_summary'),
                    controller: summaryController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Kurzbeschreibung',
                      hintText: 'z. B. TopUp-Fehler bei Kunde B',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('uat_create_area'),
                    controller: areaController,
                    decoration: const InputDecoration(
                      labelText: 'Bereich',
                      hintText: 'z. B. wallet, operator_dashboard',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('uat_create_target_build'),
                    controller: buildController,
                    decoration: const InputDecoration(
                      labelText: 'Target Build',
                      hintText: 'z. B. 1.0.3+4',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('uat_create_box_id'),
                    controller: boxIdController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Box-ID (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UatInboxStatus>(
                    key: const ValueKey('uat_create_status'),
                    initialValue: selectedStatus,
                    items: UatInboxStatus.values.map((status) {
                      return DropdownMenuItem<UatInboxStatus>(
                        value: status,
                        child: Text(_statusLabel(status)),
                      );
                    }).toList(),
                    decoration: const InputDecoration(
                      labelText: 'UAT-Status',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedStatus = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UatInboxSeverity>(
                    key: const ValueKey('uat_create_severity'),
                    initialValue: selectedSeverity,
                    items: UatInboxSeverity.values.map((severity) {
                      return DropdownMenuItem<UatInboxSeverity>(
                        value: severity,
                        child: Text(_severityLabel(severity)),
                      );
                    }).toList(),
                    decoration: const InputDecoration(
                      labelText: 'Severity',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedSeverity = value;
                      });
                    },
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                key: const ValueKey('uat_create_save'),
                onPressed: () {
                  final summary = summaryController.text.trim();
                  if (summary.isEmpty) {
                    setDialogState(() {
                      validationError = 'Kurzbeschreibung ist erforderlich.';
                    });
                    return;
                  }
                  final boxRaw = boxIdController.text.trim();
                  if (boxRaw.isNotEmpty && int.tryParse(boxRaw) == null) {
                    setDialogState(() {
                      validationError = 'Box-ID muss eine Zahl sein.';
                    });
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    final summary = summaryController.text.trim();
    final area = areaController.text.trim();
    final targetBuild = buildController.text.trim();
    final boxId = int.tryParse(boxIdController.text.trim());

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isCreatingEntry = true;
    });

    try {
      await _opsMaintenance.logUatAction(
        baseUrl: baseUrl,
        jwt: jwt,
        actionName: 'uat_manual_report',
        actionStatus: _actionStatusForUatStatus(selectedStatus),
        summary: summary,
        area: area.isEmpty ? 'operator_dashboard' : area,
        uatStatus: _toOpsUatStatus(selectedStatus),
        severity: _toOpsUatSeverity(selectedSeverity),
        boxId: boxId,
        targetBuild: targetBuild.isEmpty ? _defaultTargetBuild : targetBuild,
        details: const <String, dynamic>{'source_screen': 'uat_inbox'},
      );
      await _reloadInbox();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('UAT-Eintrag gespeichert.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('UAT-Eintrag konnte nicht gespeichert werden: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingEntry = false;
        });
      }
    }
  }

  String _actionStatusForUatStatus(UatInboxStatus status) {
    switch (status) {
      case UatInboxStatus.open:
        return 'failed';
      case UatInboxStatus.inProgress:
      case UatInboxStatus.retest:
        return 'partial';
      case UatInboxStatus.fixed:
      case UatInboxStatus.closed:
        return 'success';
    }
  }

  OpsUatStatus _toOpsUatStatus(UatInboxStatus status) {
    switch (status) {
      case UatInboxStatus.open:
        return OpsUatStatus.open;
      case UatInboxStatus.inProgress:
        return OpsUatStatus.inProgress;
      case UatInboxStatus.fixed:
        return OpsUatStatus.fixed;
      case UatInboxStatus.retest:
        return OpsUatStatus.retest;
      case UatInboxStatus.closed:
        return OpsUatStatus.closed;
    }
  }

  OpsUatSeverity _toOpsUatSeverity(UatInboxSeverity severity) {
    switch (severity) {
      case UatInboxSeverity.critical:
        return OpsUatSeverity.critical;
      case UatInboxSeverity.high:
        return OpsUatSeverity.high;
      case UatInboxSeverity.medium:
        return OpsUatSeverity.medium;
      case UatInboxSeverity.low:
        return OpsUatSeverity.low;
    }
  }

  bool _isUatTicketUpdateAction(String actionName) {
    final normalized = _normalize(actionName);
    return normalized == 'uat_ticket_status_updated' ||
        normalized == 'uat_ticket_owner_assigned' ||
        normalized == 'uat_ticket_owner_cleared';
  }

  int? _extractTicketIdFromDetails(Map<String, dynamic> details) {
    final raw = details['ticket_id'];
    if (raw is num) {
      final id = raw.toInt();
      return id > 0 ? id : null;
    }
    if (raw is String) {
      final id = int.tryParse(raw.trim());
      if (id != null && id > 0) {
        return id;
      }
    }
    return null;
  }

  List<UatInboxItem> _buildUatItems(List<OpsOperatorActionItem> rows) {
    final statusOverrides = <int, UatInboxStatus>{};
    final ownerOverrides = <int, String>{};

    for (final action in rows) {
      if (!_isUatTicketUpdateAction(action.actionName)) {
        continue;
      }
      final ticketId = _extractTicketIdFromDetails(action.details);
      if (ticketId == null) {
        continue;
      }

      final normalizedActionName = _normalize(action.actionName);
      if (!statusOverrides.containsKey(ticketId) &&
          normalizedActionName == 'uat_ticket_status_updated') {
        final rawStatus = _firstText(action.details, <String>[
          'uat_status',
          'status',
        ]);
        if (rawStatus != null) {
          statusOverrides[ticketId] = _mapStatus(
            rawStatus,
            action.actionStatus,
          );
        }
      }

      if (!ownerOverrides.containsKey(ticketId)) {
        if (normalizedActionName == 'uat_ticket_owner_cleared') {
          ownerOverrides[ticketId] = '-';
        } else if (normalizedActionName == 'uat_ticket_owner_assigned') {
          ownerOverrides[ticketId] =
              _firstText(action.details, <String>['owner_email', 'owner']) ??
              '-';
        }
      }
    }

    final items = <UatInboxItem>[];
    for (final action in rows) {
      if (_isUatTicketUpdateAction(action.actionName)) {
        continue;
      }
      final baseItem = _mapFromOperatorAction(action);
      items.add(
        baseItem.copyWith(
          status: statusOverrides[action.id] ?? baseItem.status,
          owner: ownerOverrides[action.id] ?? baseItem.owner,
        ),
      );
    }
    items.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) {
        return byTime;
      }
      return b.ticketId.compareTo(a.ticketId);
    });
    return items;
  }

  List<_UatTicketTimelineEvent> _buildTimelineEvents(int ticketId) {
    final events = <_UatTicketTimelineEvent>[];
    for (final row in _rawRows) {
      final rowTicketId = _extractTicketIdFromDetails(row.details) ?? row.id;
      if (rowTicketId != ticketId) {
        continue;
      }
      final actor = (row.actorEmail?.trim().isNotEmpty ?? false)
          ? row.actorEmail!.trim()
          : row.actorId;
      events.add(
        _UatTicketTimelineEvent(
          id: row.id,
          actionName: row.actionName,
          actionStatus: row.actionStatus,
          actor: actor,
          source: row.source,
          note: _firstText(row.details, <String>[
            'note',
            'summary',
            'message',
            'description',
          ]),
          createdAt: row.createdAt,
        ),
      );
    }
    events.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) {
        return byTime;
      }
      return b.id.compareTo(a.id);
    });
    return events;
  }

  Future<void> _openTicketDetails(UatInboxItem item) async {
    final timeline = _buildTimelineEvents(item.ticketId);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.id,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.summary,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Schliessen',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Bereich ${item.area}')),
                      Chip(label: Text('Owner ${item.owner}')),
                      Chip(label: Text('Build ${item.targetBuild}')),
                      Chip(label: Text('Status ${_statusLabel(item.status)}')),
                      Chip(
                        label: Text(
                          'Severity ${_severityLabel(item.severity)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Future.microtask(
                            () => _openSetTicketStatusDialog(item),
                          );
                        },
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Status setzen'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Future.microtask(() => _openAssignOwnerDialog(item));
                        },
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Owner setzen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Verlauf',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (timeline.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.history_toggle_off),
                        title: Text('Keine Verlaufseintraege gefunden'),
                      ),
                    ),
                  ...timeline.map((event) {
                    return Card(
                      child: ListTile(
                        title: Text(_humanize(event.actionName)),
                        subtitle: Text(
                          'Status: ${event.actionStatus}\n'
                          'Akteur: ${event.actor}\n'
                          'Quelle: ${event.source}\n'
                          'Zeit: ${event.createdAt.toLocal().toIso8601String()}'
                          '${event.note == null ? '' : '\nNotiz: ${event.note}'}',
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      },
    );
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
      ticketId: action.id,
      id: 'UAT-${action.id}',
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

  Widget _buildStatusBadge(UatInboxStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: _statusColor(status)),
      ),
    );
  }

  Widget _buildSeverityBadge(UatInboxSeverity severity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _severityColor(severity).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _severityLabel(severity),
        style: TextStyle(color: _severityColor(severity)),
      ),
    );
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
    final currentOperatorEmail = context.select<AuthService, String>(
      (auth) => auth.email.trim(),
    );
    final availableOwners = _availableOwners();
    final normalizedCurrentOperatorEmail = currentOperatorEmail.toLowerCase();
    final visibleItems = _filteredItems();
    return Scaffold(
      appBar: AppBar(
        title: const Text('UAT Inbox'),
        actions: [
          IconButton(
            tooltip: 'UAT-Eintrag erfassen',
            onPressed: _isCreatingEntry ? null : _openCreateUatEntryDialog,
            icon: const Icon(Icons.add_task_outlined),
          ),
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
                      Chip(label: Text('total ${_items.length}')),
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
                      Chip(label: Text('visible ${visibleItems.length}')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.search),
                  title: TextField(
                    key: const ValueKey('uat_search_field'),
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Suche in ID, Summary, Area, Owner ...',
                      border: InputBorder.none,
                    ),
                  ),
                  trailing: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Suche leeren',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              Card(
                child: SwitchListTile(
                  value: _showOnlyOpen,
                  onChanged: (value) {
                    setState(() {
                      _showOnlyOpen = value;
                    });
                  },
                  title: const Text('Nur offene Punkte'),
                  subtitle: const Text('open, in_progress, retest'),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status-Filter'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('all'),
                            selected: _statusFilter == null,
                            onSelected: (_) {
                              setState(() {
                                _statusFilter = null;
                              });
                            },
                          ),
                          ...UatInboxStatus.values.map((status) {
                            return ChoiceChip(
                              label: Text(_statusLabel(status)),
                              selected: _statusFilter == status,
                              onSelected: (_) {
                                setState(() {
                                  _statusFilter = status;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Severity-Filter'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('all'),
                            selected: _severityFilter == null,
                            onSelected: (_) {
                              setState(() {
                                _severityFilter = null;
                              });
                            },
                          ),
                          ...UatInboxSeverity.values.map((severity) {
                            return ChoiceChip(
                              key: ValueKey('uat_severity_${severity.name}'),
                              label: Text(_severityLabel(severity)),
                              selected: _severityFilter == severity,
                              onSelected: (_) {
                                setState(() {
                                  _severityFilter = severity;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Owner-Filter'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            key: const ValueKey('uat_owner_all'),
                            label: const Text('all'),
                            selected: _ownerFilter == null,
                            onSelected: (_) {
                              setState(() {
                                _ownerFilter = null;
                              });
                            },
                          ),
                          if (normalizedCurrentOperatorEmail.isNotEmpty)
                            ChoiceChip(
                              key: const ValueKey('uat_owner_mine'),
                              label: const Text('mine'),
                              selected:
                                  _ownerFilter != null &&
                                  _ownerFilter!.toLowerCase() ==
                                      normalizedCurrentOperatorEmail,
                              onSelected: (_) {
                                setState(() {
                                  _ownerFilter = currentOperatorEmail;
                                });
                              },
                            ),
                          ChoiceChip(
                            key: const ValueKey('uat_owner_unassigned'),
                            label: const Text('unassigned'),
                            selected: _ownerFilter == _ownerFilterUnassignedKey,
                            onSelected: (_) {
                              setState(() {
                                _ownerFilter = _ownerFilterUnassignedKey;
                              });
                            },
                          ),
                          ...availableOwners.map((owner) {
                            return ChoiceChip(
                              key: ValueKey('uat_owner_${owner.toLowerCase()}'),
                              label: Text(owner),
                              selected:
                                  _ownerFilter != null &&
                                  _ownerFilter!.toLowerCase() ==
                                      owner.toLowerCase(),
                              onSelected: (_) {
                                setState(() {
                                  _ownerFilter = owner;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
              if (visibleItems.isEmpty)
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
              ...visibleItems.map((item) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _openTicketDetails(item),
                    title: Text('${item.id} - ${item.summary}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bereich: ${item.area}\n'
                          'Owner: ${item.owner} | Build: ${item.targetBuild}\n'
                          'Zeit: ${item.createdAt.toLocal().toIso8601String()}',
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildStatusBadge(item.status),
                            _buildSeverityBadge(item.severity),
                          ],
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      key: ValueKey('uat_ticket_actions_${item.ticketId}'),
                      tooltip: 'Ticket-Aktionen',
                      onSelected: (value) {
                        if (value == 'set_status') {
                          _openSetTicketStatusDialog(item);
                          return;
                        }
                        if (value == 'set_owner') {
                          _openAssignOwnerDialog(item);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'set_status',
                          child: Text('Status setzen'),
                        ),
                        PopupMenuItem<String>(
                          value: 'set_owner',
                          child: Text('Owner setzen'),
                        ),
                      ],
                      child: const Icon(Icons.more_vert),
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
