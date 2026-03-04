import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/services/storage_migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('migrates legacy auth and loyalty keys', () async {
    SharedPreferences.setMockInitialValues({
      'auth.loggedIn': true,
      'loyalty.completed_washes': 7,
      'app.storage_schema_version': 1,
    });

    await StorageMigrationService().runMigrations();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getBool('auth.logged_in'), isTrue);
    expect(prefs.getInt('loyalty.completed'), 7);
    expect(prefs.getInt('app.storage_schema_version'), 2);
  });
}
