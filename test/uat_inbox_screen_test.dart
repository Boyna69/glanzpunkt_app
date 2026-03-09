import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/screens/uat_inbox_screen.dart';
import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/services/environment_service.dart';
import 'package:glanzpunkt_app/services/ops_maintenance_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOpsMaintenanceService extends OpsMaintenanceService {
  _FakeOpsMaintenanceService({required this.rows});

  List<OpsOperatorActionItem> rows;
  final List<Map<String, dynamic>> loggedUatActions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> statusUpdates = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> ownerAssignments = <Map<String, dynamic>>[];
  int fetchCallCount = 0;

  @override
  Future<List<OpsOperatorActionItem>> fetchOperatorActions({
    required String baseUrl,
    required String jwt,
    int maxRows = 50,
    int offsetRows = 0,
    String? filterStatus,
    int? filterBoxId,
    String? searchQuery,
    DateTime? fromAt,
    DateTime? untilAt,
  }) async {
    fetchCallCount += 1;
    return List<OpsOperatorActionItem>.from(rows);
  }

  @override
  Future<void> logUatAction({
    required String baseUrl,
    required String jwt,
    required String actionName,
    required String actionStatus,
    required String summary,
    required String area,
    OpsUatStatus uatStatus = OpsUatStatus.open,
    OpsUatSeverity severity = OpsUatSeverity.medium,
    int? boxId,
    String targetBuild = 'current',
    Map<String, dynamic>? details,
    String source = 'app',
  }) async {
    loggedUatActions.add(<String, dynamic>{
      'base_url': baseUrl,
      'jwt': jwt,
      'action_name': actionName,
      'action_status': actionStatus,
      'summary': summary,
      'area': area,
      'uat_status': uatStatus.name,
      'severity': severity.name,
      'box_id': boxId,
      'target_build': targetBuild,
      'details': details ?? const <String, dynamic>{},
      'source': source,
    });

    final nextId = rows.isEmpty ? 1 : rows.first.id + 1;
    rows = <OpsOperatorActionItem>[
      OpsOperatorActionItem(
        id: nextId,
        actorId: 'operator-1',
        actorEmail: 'ops@glanzpunkt.de',
        actionName: actionName,
        actionStatus: actionStatus,
        boxId: boxId,
        source: source,
        details: <String, dynamic>{
          'summary': summary,
          'area': area,
          'uat_status': uatStatus == OpsUatStatus.inProgress
              ? 'in_progress'
              : uatStatus.name,
          'severity': severity.name,
          'target_build': targetBuild,
        },
        createdAt: DateTime(2026, 3, 9, 12, 0, 0),
      ),
      ...rows,
    ];
  }

  @override
  Future<void> setUatTicketStatus({
    required String baseUrl,
    required String jwt,
    required int ticketId,
    required OpsUatStatus uatStatus,
    String? note,
  }) async {
    statusUpdates.add(<String, dynamic>{
      'base_url': baseUrl,
      'jwt': jwt,
      'ticket_id': ticketId,
      'uat_status': uatStatus.name,
      'note': note,
    });
    final nextId = rows.isEmpty ? 1 : rows.first.id + 1;
    rows = <OpsOperatorActionItem>[
      OpsOperatorActionItem(
        id: nextId,
        actorId: 'operator-1',
        actorEmail: 'ops@glanzpunkt.de',
        actionName: 'uat_ticket_status_updated',
        actionStatus: 'partial',
        boxId: null,
        source: 'app',
        details: <String, dynamic>{
          'ticket_id': ticketId,
          'uat_status': uatStatus == OpsUatStatus.inProgress
              ? 'in_progress'
              : uatStatus.name,
        },
        createdAt: DateTime(2026, 3, 9, 12, 5, 0),
      ),
      ...rows,
    ];
  }

  @override
  Future<void> assignUatTicketOwner({
    required String baseUrl,
    required String jwt,
    required int ticketId,
    String? ownerEmail,
    String? note,
  }) async {
    ownerAssignments.add(<String, dynamic>{
      'base_url': baseUrl,
      'jwt': jwt,
      'ticket_id': ticketId,
      'owner_email': ownerEmail,
      'note': note,
    });
    final nextId = rows.isEmpty ? 1 : rows.first.id + 1;
    rows = <OpsOperatorActionItem>[
      OpsOperatorActionItem(
        id: nextId,
        actorId: 'operator-1',
        actorEmail: 'ops@glanzpunkt.de',
        actionName: ownerEmail == null
            ? 'uat_ticket_owner_cleared'
            : 'uat_ticket_owner_assigned',
        actionStatus: 'success',
        boxId: null,
        source: 'app',
        details: <String, dynamic>{
          'ticket_id': ticketId,
          'owner_email': ownerEmail,
        },
        createdAt: DateTime(2026, 3, 9, 12, 6, 0),
      ),
      ...rows,
    ];
  }
}

OpsOperatorActionItem _action({
  required int id,
  required String actionStatus,
  required String summary,
  required String area,
  required String uatStatus,
  required String severity,
  String actorEmail = 'ops@glanzpunkt.de',
  DateTime? createdAt,
}) {
  return OpsOperatorActionItem(
    id: id,
    actorId: 'operator-1',
    actorEmail: actorEmail,
    actionName: 'uat_manual_report',
    actionStatus: actionStatus,
    boxId: null,
    source: 'app',
    details: <String, dynamic>{
      'summary': summary,
      'area': area,
      'uat_status': uatStatus,
      'severity': severity,
      'target_build': '1.0.0+1',
    },
    createdAt: createdAt ?? DateTime(2026, 3, 9, 10, 0, 0),
  );
}

Future<void> _pumpUatInbox(
  WidgetTester tester, {
  required AuthService auth,
  required OpsMaintenanceService maintenanceService,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<EnvironmentService>(
          create: (_) => EnvironmentService(),
        ),
      ],
      child: MaterialApp(
        home: UatInboxScreen(maintenanceService: maintenanceService),
      ),
    ),
  );
}

void main() {
  testWidgets('shows and filters UAT inbox items', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'ops@glanzpunkt.de',
      'auth.profile_role': 'operator',
      'auth.backend_jwt': 'jwt-operator',
      'auth.backend_user_id': 'operator-1',
    });
    final auth = AuthService();
    await auth.ready;
    expect(auth.hasOperatorAccess, isTrue);
    expect(auth.backendJwt, 'jwt-operator');

    final service = _FakeOpsMaintenanceService(
      rows: <OpsOperatorActionItem>[
        _action(
          id: 2,
          actionStatus: 'success',
          summary: 'Timer drift fixed',
          area: 'countdown',
          uatStatus: 'closed',
          severity: 'low',
        ),
        _action(
          id: 1,
          actionStatus: 'failed',
          summary: 'TopUp fails for customer B',
          area: 'wallet',
          uatStatus: 'open',
          severity: 'high',
        ),
      ],
    );

    await _pumpUatInbox(tester, auth: auth, maintenanceService: service);
    await tester.pumpAndSettle();

    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('visible 2'), findsOneWidget);

    await tester.tap(find.text('Nur offene Punkte'));
    await tester.pumpAndSettle();

    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('visible 1'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('uat_search_field')),
      'wallet',
    );
    await tester.pumpAndSettle();

    expect(find.text('visible 1'), findsOneWidget);
    expect(service.fetchCallCount, greaterThan(0));
  });

  testWidgets('creates manual UAT entry and logs standardized payload', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'ops@glanzpunkt.de',
      'auth.profile_role': 'operator',
      'auth.backend_jwt': 'jwt-operator',
      'auth.backend_user_id': 'operator-1',
    });
    final auth = AuthService();
    await auth.ready;
    expect(auth.hasOperatorAccess, isTrue);
    expect(auth.backendJwt, 'jwt-operator');

    final service = _FakeOpsMaintenanceService(rows: <OpsOperatorActionItem>[]);

    await _pumpUatInbox(tester, auth: auth, maintenanceService: service);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('UAT-Eintrag erfassen'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('uat_create_summary')),
      'App freeze after payment',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('uat_create_area')),
      'wallet',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('uat_create_target_build')),
      '1.0.9+12',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('uat_create_box_id')),
      '3',
    );

    await tester.tap(find.byKey(const ValueKey<String>('uat_create_save')));
    await tester.pumpAndSettle();

    expect(service.loggedUatActions.length, 1);
    final payload = service.loggedUatActions.single;
    expect(payload['summary'], 'App freeze after payment');
    expect(payload['area'], 'wallet');
    expect(payload['target_build'], '1.0.9+12');
    expect(payload['box_id'], 3);
    expect(payload['uat_status'], OpsUatStatus.open.name);
    expect(payload['severity'], OpsUatSeverity.medium.name);
  });

  testWidgets('filters by owner and opens ticket detail timeline', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'ops@glanzpunkt.de',
      'auth.profile_role': 'operator',
      'auth.backend_jwt': 'jwt-operator',
      'auth.backend_user_id': 'operator-1',
    });
    final auth = AuthService();
    await auth.ready;

    final service = _FakeOpsMaintenanceService(
      rows: <OpsOperatorActionItem>[
        OpsOperatorActionItem(
          id: 12,
          actorId: 'operator-1',
          actorEmail: 'ops@glanzpunkt.de',
          actionName: 'uat_ticket_status_updated',
          actionStatus: 'partial',
          boxId: 1,
          source: 'app',
          details: const <String, dynamic>{
            'ticket_id': 10,
            'uat_status': 'in_progress',
            'note': 'work started',
          },
          createdAt: DateTime(2026, 3, 9, 12, 5, 0),
        ),
        _action(
          id: 11,
          actionStatus: 'failed',
          summary: 'Operator chart not refreshing',
          area: 'operator_dashboard',
          uatStatus: 'open',
          severity: 'medium',
          actorEmail: 'bob@glanzpunkt.de',
        ),
        _action(
          id: 10,
          actionStatus: 'failed',
          summary: 'Payment crash',
          area: 'wallet',
          uatStatus: 'open',
          severity: 'high',
          actorEmail: 'alice@glanzpunkt.de',
        ),
      ],
    );

    await _pumpUatInbox(tester, auth: auth, maintenanceService: service);
    await tester.pumpAndSettle();

    expect(find.text('visible 2'), findsOneWidget);

    final aliceOwnerChip = find.widgetWithText(
      ChoiceChip,
      'alice@glanzpunkt.de',
    );
    await tester.ensureVisible(aliceOwnerChip);
    await tester.pumpAndSettle();
    await tester.tap(aliceOwnerChip);
    await tester.pumpAndSettle();

    final ticketRow = find.textContaining('UAT-10 - Payment crash');
    await tester.ensureVisible(ticketRow);
    await tester.pumpAndSettle();
    expect(ticketRow, findsOneWidget);
    await tester.tap(ticketRow);
    await tester.pumpAndSettle();

    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.textContaining('Uat ticket status updated'), findsOneWidget);
    expect(find.textContaining('work started'), findsOneWidget);
  });
}
