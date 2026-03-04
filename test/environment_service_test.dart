import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/core/app_config.dart';
import 'package:glanzpunkt_app/services/environment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('selectEnvironment persists and restores value', () async {
    final first = EnvironmentService();
    await first.selectEnvironment(ApiEnvironment.stage);
    expect(first.environment, ApiEnvironment.stage);

    final second = EnvironmentService();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(second.environment, ApiEnvironment.stage);
  });
}
