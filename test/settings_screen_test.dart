import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glanzpunkt_app/screens/settings_screen.dart';
import 'package:glanzpunkt_app/services/analytics_service.dart';
import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/services/environment_service.dart';

Future<void> _pumpSettings(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<EnvironmentService>(
          create: (_) => EnvironmentService(),
        ),
        ChangeNotifierProvider<AnalyticsService>(
          create: (_) => AnalyticsService(),
        ),
      ],
      child: MaterialApp(
        home: const SettingsScreen(),
        routes: {
          '/operator-dashboard': (_) =>
              const Scaffold(body: Text('OP_DASHBOARD')),
          '/uat-inbox': (_) => const Scaffold(body: Text('UAT_INBOX_ROUTE')),
          '/wallet': (_) => const Scaffold(body: Text('WALLET_ROUTE')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('operator sees UAT inbox entry and can open it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'operator@glanzpunkt.de',
      'auth.profile_role': 'operator',
    });
    final auth = AuthService();
    await auth.ready;

    await _pumpSettings(tester, auth: auth);

    expect(find.text('UAT Inbox'), findsOneWidget);
    await tester.tap(find.text('UAT Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('UAT_INBOX_ROUTE'), findsOneWidget);
  });

  testWidgets('customer does not see UAT inbox entry', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'kunde@glanzpunkt.de',
      'auth.profile_role': 'customer',
    });
    final auth = AuthService();
    await auth.ready;

    await _pumpSettings(tester, auth: auth);

    expect(find.text('UAT Inbox'), findsNothing);
  });
}
