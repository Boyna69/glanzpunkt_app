import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glanzpunkt_app/screens/home_screen.dart';
import 'package:glanzpunkt_app/screens/login_screen.dart';
import 'package:glanzpunkt_app/screens/loyalty_screen.dart';
import 'package:glanzpunkt_app/screens/operator_dashboard_screen.dart';
import 'package:glanzpunkt_app/screens/register_screen.dart';
import 'package:glanzpunkt_app/screens/settings_screen.dart';
import 'package:glanzpunkt_app/screens/start_wash_screen.dart';
import 'package:glanzpunkt_app/services/analytics_service.dart';
import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/services/box_service.dart';
import 'package:glanzpunkt_app/services/environment_service.dart';
import 'package:glanzpunkt_app/services/loyalty_service.dart';

void main() {
  Future<void> pumpWithProviders(
    WidgetTester tester, {
    required Widget child,
    AuthService? authService,
  }) async {
    final auth = authService ?? AuthService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider(create: (_) => EnvironmentService()),
          ChangeNotifierProvider(create: (_) => AnalyticsService()),
          ChangeNotifierProvider(create: (_) => LoyaltyService()),
          ChangeNotifierProvider(create: (_) => BoxService()),
        ],
        child: MaterialApp(
          home: child,
          routes: {
            '/register': (_) => const RegisterScreen(),
            '/home': (_) => const HomeScreen(autoSyncOnOpen: false),
            '/loyalty': (_) => const LoyaltyScreen(),
            '/operator-dashboard': (_) => const OperatorDashboardScreen(),
            '/settings': (_) => const SettingsScreen(),
          },
        ),
      ),
    );
  }

  testWidgets('guest login button routes to home', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWithProviders(tester, child: const LoginScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Als Gast fortfahren'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Glanzpunkt Boxen - Gast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest opening loyalty gets account-required dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': true,
      'auth.email': '',
    });
    final auth = AuthService();
    await auth.ready;

    await pumpWithProviders(
      tester,
      child: const HomeScreen(autoSyncOnOpen: false),
      authService: auth,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stempelkarte'));
    await tester.pumpAndSettle();

    expect(find.text('Stempelkarte nur mit Konto'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Konto erstellen'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home start action opens start wash screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.login('kunde@glanzpunkt.de', 'pass123');

    await pumpWithProviders(
      tester,
      child: const HomeScreen(autoSyncOnOpen: false),
      authService: auth,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Waschvorgang starten'));
    await tester.pumpAndSettle();

    expect(find.byType(StartWashScreen), findsOneWidget);
    expect(find.text('Waschvorgang starten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings locks operator dashboard for customer role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.login('kunde@glanzpunkt.de', 'pass123');

    await pumpWithProviders(
      tester,
      child: const SettingsScreen(),
      authService: auth,
    );
    await tester.pumpAndSettle();

    expect(find.text('System Monitoring (gesperrt)'), findsOneWidget);
    expect(find.text('Betreiber Dashboard'), findsNothing);
  });

  testWidgets('settings opens operator dashboard for operator role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'ops@glanzpunkt.de',
      'auth.profile_role': 'operator',
    });
    final auth = AuthService();
    await auth.ready;

    await pumpWithProviders(
      tester,
      child: const SettingsScreen(),
      authService: auth,
    );
    await tester.pumpAndSettle();

    expect(find.text('Betreiber Dashboard'), findsOneWidget);

    await tester.tap(find.text('Betreiber Dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(OperatorDashboardScreen), findsOneWidget);
    expect(find.textContaining('Rolle: Betreiber'), findsOneWidget);
    final hasAlertEntry =
        find.text('Keine akuten Warnungen').evaluate().isNotEmpty ||
        find.text('Reinigung faellig').evaluate().isNotEmpty ||
        find.text('Reservierungen blockiert').evaluate().isNotEmpty ||
        find.text('Box lange aktiv').evaluate().isNotEmpty;
    expect(hasAlertEntry, isTrue);
    await tester.scrollUntilVisible(
      find.textContaining('KPI-Exportzeitraum'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('KPI-Exportzeitraum'), findsOneWidget);
    expect(find.byTooltip('KPI-Bericht teilen'), findsOneWidget);
    expect(find.byTooltip('KPI-Bericht kopieren'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Reinigungsintervall: alle 75 Waeschen'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Reinigungsintervall: alle 75 Waeschen'),
      findsOneWidget,
    );
    expect(find.text('Reinigung durchgefuehrt'), findsWidgets);
    expect(find.text('Status neu laden'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Letzte Fehler'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Operator Aktionen'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Operator Aktionen'), findsOneWidget);
    expect(
      find.text('Suche (Aktion, Box, Betreiber, Details)'),
      findsOneWidget,
    );
    expect(find.text('Letzte Fehler'), findsOneWidget);
  });

  testWidgets('settings shows backend diagnostics dialog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.ready;

    await pumpWithProviders(
      tester,
      child: const SettingsScreen(),
      authService: auth,
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend-Diagnose'), findsOneWidget);

    await tester.tap(find.text('Backend-Diagnose'));
    await tester.pumpAndSettle();

    expect(find.text('Backend-Diagnose'), findsNWidgets(2));
    expect(find.textContaining('API-Key Quelle:'), findsOneWidget);
    expect(find.textContaining('Supabase URL:'), findsOneWidget);
  });
}
