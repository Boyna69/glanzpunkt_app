import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/loyalty_screen.dart';
import 'screens/history_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/monitoring_screen.dart';
import 'screens/operator_dashboard_screen.dart';
import 'widgets/operator_access_guard.dart';

import 'services/auth_service.dart';
import 'services/loyalty_service.dart';
import 'services/box_service.dart';
import 'services/analytics_service.dart';
import 'services/environment_service.dart';
import 'services/storage_migration_service.dart';
import 'services/wallet_service.dart';
import 'services/wash_backend_gateway.dart';
import 'services/remote_wash_backend_gateway.dart';
import 'services/backend_http_client.dart';
import 'services/box_realtime_service.dart';
import 'core/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageMigrationService().runMigrations();
  final environmentService = EnvironmentService();
  final analyticsService = AnalyticsService();
  final authService = AuthService(
    httpClient: createBackendHttpClient(
      defaultHeaders: const <String, String>{
        'x-client-info': 'glanzpunkt_app/1.0',
      },
    ),
    supabaseUrlProvider: () => AppConfig.supabaseProjectUrl,
    supabaseApiKeyProvider: () => AppConfig.supabaseApiKey,
  );
  final supabaseApiKey = AppConfig.supabaseApiKey;
  if (!AppConfig.useMockBackend &&
      AppConfig.supabaseProjectUrl.isNotEmpty &&
      supabaseApiKey.isNotEmpty) {
    await Supabase.initialize(
      url: AppConfig.supabaseProjectUrl,
      anonKey: supabaseApiKey,
    );
  }
  final backendHeaders = <String, String>{
    if (supabaseApiKey.isNotEmpty) ...{
      'apikey': supabaseApiKey,
      'Authorization': 'Bearer $supabaseApiKey',
    },
    'x-client-info': 'glanzpunkt_app/1.0',
  };
  final WashBackendGateway washBackend = AppConfig.useMockBackend
      ? MockWashBackendGateway()
      : RemoteWashBackendGateway(
          baseUrlProvider: () => environmentService.activeBaseUrl,
          client: createBackendHttpClient(defaultHeaders: backendHeaders),
          jwtProvider: () => authService.backendJwt,
        );
  final BoxRealtimeService? boxRealtimeService = AppConfig.useMockBackend
      ? null
      : BoxRealtimeService(
          authService: authService,
          environmentService: environmentService,
          supabaseBaseUrl: AppConfig.supabaseProjectUrl,
        );
  await boxRealtimeService?.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvironmentService>.value(
          value: environmentService,
        ),
        ChangeNotifierProvider<AnalyticsService>.value(value: analyticsService),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider(
          create: (_) => WalletService(
            httpClient: createBackendHttpClient(defaultHeaders: backendHeaders),
            baseUrlProvider: () => environmentService.activeBaseUrl,
            supabaseApiKeyProvider: () => AppConfig.supabaseApiKey,
            jwtProvider: () => authService.backendJwt,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => LoyaltyService(
            httpClient: createBackendHttpClient(defaultHeaders: backendHeaders),
            baseUrlProvider: () => environmentService.activeBaseUrl,
            supabaseApiKeyProvider: () => AppConfig.supabaseApiKey,
            jwtProvider: () => authService.backendJwt,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BoxService(
            backend: washBackend,
            analytics: analyticsService,
            realtimeUpdates: boxRealtimeService?.updates,
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glanzpunkt App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A1A2F),
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),
        '/loyalty': (_) => const LoyaltyScreen(),
        '/history': (_) => const HistoryScreen(),
        '/wallet': (_) => const WalletScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/monitoring': (_) => const OperatorAccessGuard(
          title: 'System Monitoring',
          child: MonitoringScreen(),
        ),
        '/operator-dashboard': (_) => const OperatorAccessGuard(
          title: 'Betreiber Dashboard',
          child: OperatorDashboardScreen(),
        ),
      },
    );
  }
}
