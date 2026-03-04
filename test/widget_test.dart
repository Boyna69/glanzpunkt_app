// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glanzpunkt_app/main.dart';
import 'package:glanzpunkt_app/screens/box_detail_screen.dart';
import 'package:glanzpunkt_app/screens/home_screen.dart';
import 'package:glanzpunkt_app/screens/loyalty_screen.dart';
import 'package:glanzpunkt_app/screens/start_wash_screen.dart';
import 'package:glanzpunkt_app/services/analytics_service.dart';
import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/services/box_service.dart';
import 'package:glanzpunkt_app/services/loyalty_service.dart';
import 'package:glanzpunkt_app/services/wash_backend_gateway.dart';

class _FakeAccountAuthService extends AuthService {
  @override
  bool get isLoggedIn => true;

  @override
  bool get isGuest => false;

  @override
  bool get hasAccount => true;

  @override
  String get email => 'kunde@glanzpunkt.de';

  @override
  double get profileBalanceEuro => 50;

  @override
  Future<void> refreshProfileAndBalance() async {}
}

class _ReserveFailingGateway extends MockWashBackendGateway {
  final BackendGatewayException error;
  int reserveCalls = 0;

  _ReserveFailingGateway(this.error);

  @override
  Future<ReserveBoxResponse> reserveBox(ReserveBoxRequest request) async {
    reserveCalls += 1;
    throw error;
  }
}

void main() {
  testWidgets('shows splash branding text', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MyApp(),
      ),
    );
    expect(find.text('Glanzpunkt'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('E-Mail'), findsOneWidget);
  });

  testWidgets('home screen shows recommendation and box status labels', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: HomeScreen(autoSyncOnOpen: false)),
      ),
    );

    await tester.pumpAndSettle();

    final textValues = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();

    expect(
      textValues.any(
        (value) =>
            value.startsWith('Empfehlung:') ||
            value.startsWith('Naechste freie Box:') ||
            value == 'Aktuell ist keine Box verfuegbar.',
      ),
      isTrue,
    );

    expect(
      textValues.any(
        (value) =>
            value.contains('Jetzt verfuegbar') ||
            value.contains('In Benutzung') ||
            value.contains('Reinigung laeuft') ||
            value.contains('Aktuell reserviert') ||
            value.contains('ausser Betrieb'),
      ),
      isTrue,
    );
  });

  testWidgets('box detail shows cleaning countdown semantics', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: BoxDetailScreen(boxNumber: 3)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Reinigungszeit'), findsOneWidget);
    expect(find.textContaining('endet in 02:00'), findsOneWidget);
  });

  testWidgets('start screen shows block reason for cleaning box', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: StartWashScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'glanzpunkt://box?box=3&sig=test',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.qr_code_scanner),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Box 3: Reinigung'), findsWidgets);
  });

  testWidgets('start screen preselects best available box on open', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: StartWashScreen()),
      ),
    );

    await tester.pumpAndSettle();

    final box1Chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('start_box_chip_1')),
    );
    expect(box1Chip.selected, isTrue);
    expect(
      find.byKey(const ValueKey('start_box_recommendation')),
      findsOneWidget,
    );
    expect(find.textContaining('Ich stehe an Box 1'), findsOneWidget);
  });

  testWidgets('start screen disables non-startable box chips', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: StartWashScreen()),
      ),
    );

    await tester.pumpAndSettle();

    final box1Chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('start_box_chip_1')),
    );
    final box2Chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('start_box_chip_2')),
    );
    final box3Chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('start_box_chip_3')),
    );

    expect(box1Chip.onSelected, isNotNull);
    expect(box2Chip.onSelected, isNull);
    expect(box3Chip.onSelected, isNull);
  });

  testWidgets('start action label reflects selection and confirmation state', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: StartWashScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start_box_chip_1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('5 EUR'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('5 EUR'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ich stehe an Box 1'), findsOneWidget);
    var checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isFalse);

    await tester.tap(find.textContaining('Ich stehe an Box 1'));
    await tester.pumpAndSettle();

    checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, isTrue);
  });

  testWidgets('loyalty screen renders 10 fixed stamp slots', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 3});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: LoyaltyScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Fortschritt: 3/10'), findsOneWidget);
    expect(find.byKey(const ValueKey('loyalty_progress')), findsOneWidget);

    for (var i = 1; i <= 10; i++) {
      expect(find.byKey(ValueKey('stamp_slot_$i')), findsOneWidget);
    }
  });

  testWidgets('loyalty screen shows reward highlight when goal reached', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 10});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: LoyaltyScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reward_highlight_card')), findsOneWidget);
    expect(find.textContaining('Belohnung freigeschaltet'), findsOneWidget);
  });

  testWidgets('start screen allows reward slot toggle for account users', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'loyalty.completed': 10});
    final auth = _FakeAccountAuthService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: const MaterialApp(home: StartWashScreen()),
      ),
    );

    await tester.pumpAndSettle();

    final availableBoxChipFinder = find.byKey(
      const ValueKey('start_box_chip_1'),
    );
    await tester.scrollUntilVisible(
      availableBoxChipFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(availableBoxChipFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    final rewardTitleFinder = find.textContaining(
      'Belohnung einloesen (10 min Slot)',
    );
    await tester.scrollUntilVisible(
      rewardTitleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(rewardTitleFinder, findsOneWidget);
    final rewardSwitchFinder = find.byKey(const ValueKey('reward_slot_switch'));
    await tester.scrollUntilVisible(
      rewardSwitchFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(rewardSwitchFinder);
    final rewardSwitchBeforeTap = tester.widget<Switch>(rewardSwitchFinder);
    expect(rewardSwitchBeforeTap.onChanged, isNotNull);
    await tester.tap(rewardSwitchFinder, warnIfMissed: false);
    await tester.pumpAndSettle();

    final rewardSwitch = tester.widget<Switch>(rewardSwitchFinder);
    expect(rewardSwitch.value, isTrue);
  });

  testWidgets(
    'start screen shows inline action for insufficient balance error',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAccountAuthService();
      final gateway = _ReserveFailingGateway(
        const BackendGatewayException(
          code: BackendErrorCode.insufficientBalance,
          message: 'insufficient_balance',
          operation: 'reserve',
        ),
      );
      final boxService = BoxService(backend: gateway);
      await boxService.rememberStartSelection(boxNumber: 1, amountEuro: 5);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AnalyticsService()),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider(create: (_) => LoyaltyService()),
            ChangeNotifierProvider<BoxService>.value(value: boxService),
          ],
          child: const MaterialApp(home: StartWashScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2) Betrag waehlen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final amountChipFinder = find.widgetWithText(ChoiceChip, '5 EUR');
      if (amountChipFinder.evaluate().isNotEmpty) {
        await tester.tap(amountChipFinder.first, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      final manualConfirmFinder = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(
        manualConfirmFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(manualConfirmFinder);
      await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      final startButtonFinder = find.widgetWithIcon(
        ElevatedButton,
        Icons.play_arrow,
      );
      await tester.scrollUntilVisible(
        startButtonFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final startButtonBeforeTap = tester.widget<ElevatedButton>(
        startButtonFinder,
      );
      expect(startButtonBeforeTap.onPressed, isNotNull);
      await tester.tap(startButtonFinder);
      await tester.pumpAndSettle();

      expect(gateway.reserveCalls, greaterThan(0));

      final inlineActionFinder = find.byKey(
        const ValueKey('start_error_inline_action'),
      );
      await tester.scrollUntilVisible(
        inlineActionFinder,
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(inlineActionFinder, findsOneWidget);
      expect(find.text('+ 5 EUR aufladen'), findsOneWidget);
      boxService.dispose();
    },
  );

  testWidgets(
    'start screen shows re-login action for unauthorized backend error',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAccountAuthService();
      final gateway = _ReserveFailingGateway(
        const BackendGatewayException(
          code: BackendErrorCode.unauthorized,
          message: 'unauthorized',
          operation: 'reserve',
        ),
      );
      final boxService = BoxService(backend: gateway);
      await boxService.rememberStartSelection(boxNumber: 1, amountEuro: 5);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AnalyticsService()),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider(create: (_) => LoyaltyService()),
            ChangeNotifierProvider<BoxService>.value(value: boxService),
          ],
          child: const MaterialApp(home: StartWashScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2) Betrag waehlen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final amountChipFinder = find.widgetWithText(ChoiceChip, '5 EUR');
      if (amountChipFinder.evaluate().isNotEmpty) {
        await tester.tap(amountChipFinder.first, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      final manualConfirmFinder = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(
        manualConfirmFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(manualConfirmFinder);
      await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      final startButtonFinder = find.widgetWithIcon(
        ElevatedButton,
        Icons.play_arrow,
      );
      await tester.scrollUntilVisible(
        startButtonFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final startButtonBeforeTap = tester.widget<ElevatedButton>(
        startButtonFinder,
      );
      expect(startButtonBeforeTap.onPressed, isNotNull);
      await tester.tap(startButtonFinder);
      await tester.pumpAndSettle();

      expect(gateway.reserveCalls, greaterThan(0));

      final inlineActionFinder = find.byKey(
        const ValueKey('start_error_inline_action'),
      );
      await tester.scrollUntilVisible(
        inlineActionFinder,
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(inlineActionFinder, findsOneWidget);
      expect(find.text('Neu einloggen'), findsOneWidget);
      boxService.dispose();
    },
  );
}
