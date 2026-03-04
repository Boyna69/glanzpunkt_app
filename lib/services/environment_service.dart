import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

class EnvironmentService extends ChangeNotifier {
  static const String _prefEnvironment = 'app.api_environment';

  ApiEnvironment _environment = AppConfig.defaultEnvironment;

  ApiEnvironment get environment => _environment;
  String get activeBaseUrl => AppConfig.baseUrlForEnvironment(_environment);

  EnvironmentService() {
    _restore();
  }

  Future<void> selectEnvironment(ApiEnvironment next) async {
    if (!kDebugMode) {
      return;
    }
    if (_environment == next) {
      return;
    }
    _environment = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefEnvironment, next.name);
  }

  Future<void> _restore() async {
    if (!kDebugMode) {
      _environment = AppConfig.defaultEnvironment;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefEnvironment);
    if (raw == null || raw.isEmpty) {
      return;
    }
    for (final value in ApiEnvironment.values) {
      if (value.name == raw) {
        _environment = value;
        notifyListeners();
        return;
      }
    }
  }
}
