enum ApiEnvironment { dev, stage, prod }

class AppConfig {
  static const bool useMockBackend = bool.fromEnvironment(
    'USE_MOCK_BACKEND',
    defaultValue: false,
  );

  static const ApiEnvironment defaultEnvironment = ApiEnvironment.dev;

  static const String devBackendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL_DEV',
    defaultValue: 'https://ucnvzrpcjkpaltuylvbv.supabase.co',
  );
  static const String stageBackendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL_STAGE',
    defaultValue: 'https://stage-api.glanzpunkt.app',
  );
  static const String prodBackendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL_PROD',
    defaultValue: 'https://api.glanzpunkt.app',
  );

  static const String supabaseProjectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ucnvzrpcjkpaltuylvbv.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_V_ZgLZBRZqgUmseBvp0vMg_lB4oKBKy',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVjbnZ6cnBjamtwYWx0dXlsdmJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1OTA3MDksImV4cCI6MjA4NzE2NjcwOX0.mClCEPe0P6NeUZB4quEWK1cHYdYrYZnt9RU1psVbQxY',
  );

  static const String legalPrivacyUrl = String.fromEnvironment(
    'LEGAL_PRIVACY_URL',
    defaultValue: 'https://www.glanzpunkt-wahlstedt.de/datenschutz',
  );

  static const String legalImprintUrl = String.fromEnvironment(
    'LEGAL_IMPRINT_URL',
    defaultValue: 'https://www.glanzpunkt-wahlstedt.de/impressum',
  );

  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@glanzpunkt-wahlstedt.de',
  );

  static const bool customerTopUpEnabled = bool.fromEnvironment(
    'CUSTOMER_TOP_UP_ENABLED',
    defaultValue: true,
  );

  static String get supabaseApiKey {
    if (supabasePublishableKey.isNotEmpty) {
      return supabasePublishableKey;
    }
    if (supabaseAnonKey.isNotEmpty) {
      return supabaseAnonKey;
    }
    return '';
  }

  static String get supabaseApiKeySource {
    if (supabasePublishableKey.isNotEmpty) {
      return 'publishable';
    }
    if (supabaseAnonKey.isNotEmpty) {
      return 'anon (legacy)';
    }
    return 'missing';
  }

  static String get maskedSupabaseApiKey {
    final key = supabaseApiKey;
    if (key.isEmpty) {
      return '(missing)';
    }
    if (key.length <= 12) {
      return '${key.substring(0, 3)}...';
    }
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }

  static String baseUrlForEnvironment(ApiEnvironment environment) {
    switch (environment) {
      case ApiEnvironment.dev:
        return devBackendBaseUrl;
      case ApiEnvironment.stage:
        return stageBackendBaseUrl;
      case ApiEnvironment.prod:
        return prodBackendBaseUrl;
    }
  }
}
