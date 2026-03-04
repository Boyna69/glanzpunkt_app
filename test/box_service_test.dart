import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/box.dart';
import 'package:glanzpunkt_app/services/analytics_service.dart';
import 'package:glanzpunkt_app/services/box_service.dart';
import 'package:glanzpunkt_app/services/wash_backend_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStatusGateway extends MockWashBackendGateway {
  @override
  Future<BoxStatusResponse> getBoxStatus(int boxNumber) {
    throw const BackendGatewayException(
      code: BackendErrorCode.unknown,
      message: 'status unavailable',
    );
  }
}

class _CleaningStatusGateway extends MockWashBackendGateway {
  @override
  Future<BoxStatusResponse> getBoxStatus(int boxNumber) async {
    return BoxStatusResponse(
      boxNumber: boxNumber,
      state: BoxState.cleaning,
      remainingMinutes: 1,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('forceSyncAllBoxes updates lastSuccessfulSyncAt', () async {
    final service = BoxService();

    expect(service.lastSuccessfulSyncAt, isNull);
    await service.forceSyncAllBoxes();
    expect(service.lastSuccessfulSyncAt, isNotNull);

    service.dispose();
  });

  test('startWashFlow writes timeline events', () async {
    final service = BoxService();
    final before = service.timelineForBox(1).length;

    await service.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );

    final afterEvents = service.timelineForBox(1);
    expect(afterEvents.length, greaterThan(before));
    expect(afterEvents.first.title, 'Session aktiv');

    service.dispose();
  });

  test('clearLastSyncError resets sync error panel state', () async {
    final service = BoxService(backend: _FailingStatusGateway());
    await service.forceSyncAllBoxes();

    expect(service.lastSyncErrorMessage, isNotNull);
    service.clearLastSyncError();
    expect(service.lastSyncErrorMessage, isNull);

    service.dispose();
  });

  test('realtime update applies backend status to box', () async {
    final updates = StreamController<BoxStatusResponse>.broadcast();
    final service = BoxService(realtimeUpdates: updates.stream);

    updates.add(
      BoxStatusResponse(
        boxNumber: 1,
        state: BoxState.active,
        remainingMinutes: 4,
        remainingSeconds: 240,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final box = service.getBoxByNumber(1);
    expect(box, isNotNull);
    expect(box!.state, BoxState.active);
    expect(box.remainingMinutes, 4);
    expect(box.remainingSeconds, 240);
    expect(service.lastSuccessfulSyncAt, isNotNull);
    expect(service.lastSyncErrorMessage, isNull);

    await updates.close();
    service.dispose();
  });

  test('realtime update writes timeline event when state changes', () async {
    final updates = StreamController<BoxStatusResponse>.broadcast();
    final service = BoxService(realtimeUpdates: updates.stream);

    updates.add(
      BoxStatusResponse(
        boxNumber: 1,
        state: BoxState.cleaning,
        remainingMinutes: 2,
        remainingSeconds: 120,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final events = service.timelineForBox(1);
    expect(events.isNotEmpty, isTrue);
    expect(events.first.title, 'Realtime-Update');
    expect(events.first.details, contains('Verfuegbar'));
    expect(events.first.details, contains('Reinigung'));

    await updates.close();
    service.dispose();
  });

  test('realtime stream error is exposed as sync error', () async {
    final updates = StreamController<BoxStatusResponse>.broadcast();
    final service = BoxService(realtimeUpdates: updates.stream);

    updates.addError('realtime failed');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(service.lastSyncErrorMessage, contains('realtime failed'));
    final issues = service.recentSyncIssues(limit: 1);
    expect(issues, isNotEmpty);
    expect(issues.first.source, 'realtime');
    expect(issues.first.message, contains('realtime failed'));

    await updates.close();
    service.dispose();
  });

  test(
    'stopActiveSession sets box state to cleaning and writes timeline',
    () async {
      final service = BoxService();

      await service.startWashFlow(
        boxNumber: 1,
        euroAmount: 5,
        identificationMethod: BoxIdentificationMethod.manual,
      );
      await service.stopActiveSession(1);

      final box = service.getBoxByNumber(1);
      expect(box, isNotNull);
      expect(box!.state, BoxState.cleaning);
      expect(box.remainingMinutes, 2);
      expect(service.timelineForBox(1).first.title, 'Session manuell gestoppt');

      service.dispose();
    },
  );

  test('recentTimelineEvents returns newest entries across boxes', () async {
    final service = BoxService();

    await service.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );
    await service.stopActiveSession(1);

    final events = service.recentTimelineEvents(limit: 3);
    expect(events, isNotEmpty);
    expect(events.length <= 3, isTrue);
    expect(events.first.boxNumber, 1);

    service.dispose();
  });

  test('refreshBoxStatus can update box into cleaning state', () async {
    final service = BoxService(backend: _CleaningStatusGateway());

    await service.refreshBoxStatus(1);
    final box = service.getBoxByNumber(1);
    expect(box, isNotNull);
    expect(box!.state, BoxState.cleaning);
    expect(box.remainingMinutes, 1);

    service.dispose();
  });

  test(
    'startBlockReasonForBox returns reason for cleaning and active',
    () async {
      final service = BoxService();

      expect(service.startBlockReasonForBox(1), isNull);
      expect(service.startBlockReasonForBox(2), contains('Benutzung'));
      expect(service.startBlockReasonForBox(3), contains('Reinigung'));
      expect(service.startBlockReasonForBox(999), contains('nicht gefunden'));

      service.dispose();
    },
  );

  test(
    'estimatedMinutesUntilAvailable returns expected values by state',
    () async {
      final service = BoxService();

      expect(service.estimatedMinutesUntilAvailable(1), 0);
      expect(service.estimatedMinutesUntilAvailable(2), 3);
      expect(service.estimatedMinutesUntilAvailable(3), 2);
      expect(service.estimatedMinutesUntilAvailable(999), isNull);

      service.dispose();
    },
  );

  test('startRewardWashFlow starts a 10 minute active session', () async {
    final service = BoxService();

    await service.startRewardWashFlow(
      boxNumber: 1,
      identificationMethod: BoxIdentificationMethod.manual,
    );

    final box = service.getBoxByNumber(1);
    expect(box, isNotNull);
    expect(box!.state, BoxState.active);
    expect(box.remainingMinutes, BoxService.rewardRuntimeMinutes);
    expect(service.timelineForBox(1).first.title, 'Reward-Session aktiv');

    service.dispose();
  });

  test('startWashFlow rejects non-available boxes', () async {
    final service = BoxService();

    await expectLater(
      () => service.startWashFlow(
        boxNumber: 2,
        euroAmount: 5,
        identificationMethod: BoxIdentificationMethod.manual,
      ),
      throwsA(isA<StateError>()),
    );

    final box = service.getBoxByNumber(2);
    expect(box, isNotNull);
    expect(box!.state, BoxState.active);
    service.dispose();
  });

  test('stopActiveSession rejects when no session is active', () async {
    final service = BoxService();

    await expectLater(
      () => service.stopActiveSession(1),
      throwsA(isA<BackendGatewayException>()),
    );

    service.dispose();
  });

  test('records telemetry for wash start success and failure', () async {
    final analytics = AnalyticsService();
    final service = BoxService(analytics: analytics);

    await service.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );
    await expectLater(
      () => service.startWashFlow(
        boxNumber: 4,
        euroAmount: 5,
        identificationMethod: BoxIdentificationMethod.qr,
        qrSignature: 'invalid',
      ),
      throwsA(isA<BackendGatewayException>()),
    );

    final names = analytics.recentEvents(limit: 20).map((e) => e.name).toList();
    expect(names.contains('wash_start_success'), isTrue);
    expect(names.contains('wash_start_failed'), isTrue);

    service.dispose();
  });

  test('syncRecentSessions loads backend session history', () async {
    final service = BoxService();
    await service.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );
    await service.syncRecentSessions();

    expect(service.backendRecentSessions, isNotEmpty);
    expect(service.lastHistorySyncAt, isNotNull);
    expect(service.lastHistorySyncErrorMessage, isNull);

    service.dispose();
  });

  test('rememberStartSelection persists values to local storage', () async {
    final first = BoxService();
    await first.rememberStartSelection(
      boxNumber: 4,
      amountEuro: 10,
      identificationMethod: BoxIdentificationMethod.qr,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('wash.last_box_number'), 4);
    expect(prefs.getInt('wash.last_amount'), 10);
    expect(prefs.getString('wash.last_identification'), 'qr');
    first.dispose();
  });

  test('timeline events are persisted to local storage', () async {
    final service = BoxService();
    await service.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wash.timeline_v1');

    expect(raw, isNotNull);
    expect(raw!, contains('Session aktiv'));
    service.dispose();
  });

  test('restores persisted timeline after service restart', () async {
    final first = BoxService();
    await first.startWashFlow(
      boxNumber: 1,
      euroAmount: 5,
      identificationMethod: BoxIdentificationMethod.manual,
    );
    first.dispose();

    final restored = BoxService();
    for (var i = 0; i < 100; i++) {
      final recent = restored.recentTimelineEvents(limit: 10);
      if (recent.any((e) => e.title == 'Session aktiv')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final recent = restored.recentTimelineEvents(limit: 10);
    expect(recent.any((e) => e.title == 'Session aktiv'), isTrue);
    restored.dispose();
  });

  test('restores timeline with 7 day retention applied', () async {
    final now = DateTime.now();
    final oldTimestamp = now.subtract(const Duration(days: 8));
    final freshTimestamp = now.subtract(const Duration(hours: 2));

    SharedPreferences.setMockInitialValues({
      'wash.timeline_v1': jsonEncode([
        {
          'boxNumber': 1,
          'timestamp': oldTimestamp.toIso8601String(),
          'title': 'Zu alt',
          'details': null,
        },
        {
          'boxNumber': 1,
          'timestamp': freshTimestamp.toIso8601String(),
          'title': 'Frisch',
          'details': null,
        },
      ]),
    });

    final service = BoxService();
    for (var i = 0; i < 100; i++) {
      final events = service.timelineForBox(1);
      if (events.any((e) => e.title == 'Frisch')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final events = service.timelineForBox(1);
    expect(events.any((e) => e.title == 'Frisch'), isTrue);
    expect(events.any((e) => e.title == 'Zu alt'), isFalse);
    service.dispose();
  });

  test(
    'clearTimelineForBox removes and persists box timeline entries',
    () async {
      final service = BoxService();
      await service.startWashFlow(
        boxNumber: 1,
        euroAmount: 5,
        identificationMethod: BoxIdentificationMethod.manual,
      );
      expect(service.timelineForBox(1), isNotEmpty);

      await service.clearTimelineForBox(1);
      expect(service.timelineForBox(1), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('wash.timeline_v1');
      expect(raw, isNotNull);
      expect(raw!, isNot(contains('"boxNumber":1')));
      service.dispose();
    },
  );
}
