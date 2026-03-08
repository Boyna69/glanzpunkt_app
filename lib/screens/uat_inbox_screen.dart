import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const UatInboxItem({
    required this.id,
    required this.severity,
    required this.area,
    required this.summary,
    required this.status,
    required this.owner,
    required this.targetBuild,
  });
}

class UatInboxScreen extends StatelessWidget {
  const UatInboxScreen({super.key});

  static const List<UatInboxItem> _items = <UatInboxItem>[
    UatInboxItem(
      id: 'UAT-001',
      severity: UatInboxSeverity.high,
      area: 'Feedback Intake',
      summary: 'Externe Tester-Rueckmeldungen einsammeln und priorisieren.',
      status: UatInboxStatus.inProgress,
      owner: 'Product',
      targetBuild: '1.0.2+3',
    ),
    UatInboxItem(
      id: 'UAT-002',
      severity: UatInboxSeverity.medium,
      area: 'Customer Flow',
      summary:
          'Gemeldete Zahlungs-/TopUp-Fehler in den Triage-Board aufnehmen.',
      status: UatInboxStatus.open,
      owner: 'Dev',
      targetBuild: 'next',
    ),
    UatInboxItem(
      id: 'UAT-003',
      severity: UatInboxSeverity.medium,
      area: 'Operator Flow',
      summary: 'Betreiber-Regressionen nach Fix gesammelt retesten.',
      status: UatInboxStatus.open,
      owner: 'QA',
      targetBuild: 'next',
    ),
    UatInboxItem(
      id: 'UAT-004',
      severity: UatInboxSeverity.low,
      area: 'Release Prep',
      summary: 'Finalen Smoke-Run fuer Customer/Operator vor RC ausfuehren.',
      status: UatInboxStatus.open,
      owner: 'QA',
      targetBuild: 'next',
    ),
  ];

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
      appBar: AppBar(title: const Text('UAT Inbox')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text('open ${_countByStatus(UatInboxStatus.open)}'),
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
          ..._items.map((item) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text('${item.id} - ${item.summary}'),
                subtitle: Text(
                  'Bereich: ${item.area}\nOwner: ${item.owner} | Build: ${item.targetBuild}',
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
                        color: _statusColor(item.status).withValues(alpha: 0.2),
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
                        style: TextStyle(color: _severityColor(item.severity)),
                      ),
                    ),
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
