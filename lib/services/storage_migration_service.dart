import 'package:shared_preferences/shared_preferences.dart';

class StorageMigrationService {
  static const String _prefSchemaVersion = 'app.storage_schema_version';
  static const int _currentVersion = 2;

  Future<void> runMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefSchemaVersion) ?? 1;
    if (current >= _currentVersion) {
      return;
    }

    var next = current;
    if (next < 2) {
      await _migrateV1ToV2(prefs);
      next = 2;
    }

    await prefs.setInt(_prefSchemaVersion, next);
  }

  Future<void> _migrateV1ToV2(SharedPreferences prefs) async {
    final oldLoggedIn = prefs.getBool('auth.loggedIn');
    if (oldLoggedIn != null && !prefs.containsKey('auth.logged_in')) {
      await prefs.setBool('auth.logged_in', oldLoggedIn);
    }

    final oldLoyaltyCompleted = prefs.getInt('loyalty.completed_washes');
    if (oldLoyaltyCompleted != null &&
        !prefs.containsKey('loyalty.completed')) {
      await prefs.setInt('loyalty.completed', oldLoyaltyCompleted);
    }
  }
}
