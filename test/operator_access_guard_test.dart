import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/widgets/operator_access_guard.dart';

void main() {
  testWidgets('blocks access for customer role', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'kunde@glanzpunkt.de',
      'auth.profile_role': 'customer',
    });
    final auth = AuthService();
    await auth.ready;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: const MaterialApp(
          home: OperatorAccessGuard(
            title: 'System Monitoring',
            child: Scaffold(body: Center(child: Text('OP_CONTENT'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kein Zugriff'), findsOneWidget);
    expect(find.textContaining('Nur Betreiber/Inhaber'), findsOneWidget);
    expect(find.text('OP_CONTENT'), findsNothing);
  });

  testWidgets('allows access for operator role', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.logged_in': true,
      'auth.is_guest': false,
      'auth.email': 'operator@glanzpunkt.de',
      'auth.profile_role': 'operator',
    });
    final auth = AuthService();
    await auth.ready;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: const MaterialApp(
          home: OperatorAccessGuard(
            title: 'System Monitoring',
            child: Scaffold(body: Center(child: Text('OP_CONTENT'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OP_CONTENT'), findsOneWidget);
    expect(find.text('Kein Zugriff'), findsNothing);
  });
}
