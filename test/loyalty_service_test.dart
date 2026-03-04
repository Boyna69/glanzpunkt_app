import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/wash_session.dart';
import 'package:glanzpunkt_app/services/loyalty_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordCompletedWashPurchase increments and persists', () async {
    final service = LoyaltyService();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.completed, 0);
    await service.recordCompletedWashPurchase();
    expect(service.completed, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('loyalty.completed'), 1);
  });

  test('restores persisted progress', () async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 4});

    final service = LoyaltyService();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.completed, 4);
    expect(service.remainingUntilReward, 6);
  });

  test('rolls over into reward slot when goal is exceeded', () async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 10});
    final service = LoyaltyService();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await service.recordCompletedWashPurchase();
    expect(service.completed, 1);
    expect(service.rewardSlots, 1);
  });

  test('redeemReward resets completed back to zero', () async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 10});
    final service = LoyaltyService();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.hasRewardAvailable, isTrue);
    await service.redeemReward(boxNumber: 4);
    expect(service.completed, 0);
    expect(service.hasRewardAvailable, isFalse);
    expect(service.redemptions, isNotEmpty);
    expect(service.redemptions.first.boxNumber, 4);
  });

  test(
    'deprecated local session ingest counts completed paid sessions once',
    () async {
      final service = LoyaltyService();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await service.ingestCompletedSessionsDeprecated([
        WashSession(
          sessionId: 's1',
          boxNumber: 1,
          status: 'completed',
          startedAt: DateTime.parse('2026-02-22T10:00:00Z'),
          endedAt: DateTime.parse('2026-02-22T10:10:00Z'),
          amountEuro: 5,
        ),
        WashSession(
          sessionId: 's2',
          boxNumber: 2,
          status: 'active',
          startedAt: DateTime.parse('2026-02-22T10:20:00Z'),
          amountEuro: 5,
        ),
        WashSession(
          sessionId: 's3',
          boxNumber: 3,
          status: 'completed',
          startedAt: DateTime.parse('2026-02-22T10:30:00Z'),
          endedAt: DateTime.parse('2026-02-22T10:40:00Z'),
          amountEuro: 0,
        ),
      ]);

      expect(service.completed, 1);

      await service.ingestCompletedSessionsDeprecated([
        WashSession(
          sessionId: 's1',
          boxNumber: 1,
          status: 'completed',
          startedAt: DateTime.parse('2026-02-22T10:00:00Z'),
          endedAt: DateTime.parse('2026-02-22T10:10:00Z'),
          amountEuro: 5,
        ),
      ]);

      expect(service.completed, 1);
    },
  );
}
