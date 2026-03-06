import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/services/auth_service.dart';
import 'package:glanzpunkt_app/services/backend_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSupabaseAuthClient implements BackendHttpClient {
  bool returnMissingProfile = false;
  String profileRole = 'customer';
  bool deleteAccountCalled = false;
  double profileBalance = 17.5;
  int? topUpStatusCodeOverride;
  Map<String, dynamic>? topUpErrorBodyOverride;

  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.endsWith('/rest/v1/profiles')) {
      if (returnMissingProfile) {
        return const BackendHttpResponse(statusCode: 200, body: []);
      }
      final requestedUserId = uri.queryParameters['id']?.replaceFirst(
        'eq.',
        '',
      );
      final profileId = requestedUserId == null || requestedUserId.isEmpty
          ? 'user-uuid-1'
          : requestedUserId;
      final profileEmail = profileId == 'user-uuid-2'
          ? 'neu@example.com'
          : 'kunde@example.com';
      return BackendHttpResponse(
        statusCode: 200,
        body: [
          {
            'id': profileId,
            'email': profileEmail,
            'balance_eur': profileBalance,
            'role': profileRole,
          },
        ],
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.endsWith('/auth/v1/token')) {
      return const BackendHttpResponse(
        statusCode: 200,
        body: {
          'access_token': 'jwt-token',
          'user': {'id': 'user-uuid-1', 'email': 'kunde@example.com'},
        },
      );
    }
    if (uri.path.endsWith('/auth/v1/signup')) {
      return const BackendHttpResponse(
        statusCode: 200,
        body: {
          'access_token': 'jwt-signup',
          'user': {'id': 'user-uuid-2', 'email': 'neu@example.com'},
        },
      );
    }
    if (uri.path.endsWith('/functions/v1/delete-account')) {
      deleteAccountCalled = true;
      return const BackendHttpResponse(
        statusCode: 200,
        body: {'deleted': true},
      );
    }
    if (uri.path.endsWith('/rest/v1/rpc/top_up')) {
      if (topUpStatusCodeOverride != null) {
        return BackendHttpResponse(
          statusCode: topUpStatusCodeOverride!,
          body:
              topUpErrorBodyOverride ??
              const {'code': 'unknown', 'message': 'unknown'},
        );
      }
      final amountValue = payload['amount'];
      final amount = amountValue is num ? amountValue.toDouble() : 0;
      profileBalance += amount;
      return BackendHttpResponse(
        statusCode: 200,
        body: {'amount': amount.toInt(), 'balance': profileBalance},
      );
    }
    throw UnimplementedError();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'top-up policy helper enforces customer flag and keeps operator access',
    () {
      expect(
        AuthService.isTopUpAllowedForContext(
          hasAccount: false,
          role: AccountRole.customer,
          customerTopUpEnabled: true,
        ),
        isFalse,
      );
      expect(
        AuthService.isTopUpAllowedForContext(
          hasAccount: true,
          role: AccountRole.customer,
          customerTopUpEnabled: false,
        ),
        isFalse,
      );
      expect(
        AuthService.isTopUpAllowedForContext(
          hasAccount: true,
          role: AccountRole.operator,
          customerTopUpEnabled: false,
        ),
        isTrue,
      );
      expect(
        AuthService.isTopUpAllowedForContext(
          hasAccount: true,
          role: AccountRole.owner,
          customerTopUpEnabled: false,
        ),
        isTrue,
      );
    },
  );

  test('loginAsGuest sets guest state and displayName', () async {
    final auth = AuthService();
    await auth.ready;

    await auth.loginAsGuest();

    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isTrue);
    expect(auth.hasAccount, isFalse);
    expect(auth.displayName, 'Gast');
  });

  test('login with credentials sets hasAccount=true', () async {
    final auth = AuthService();
    await auth.ready;

    await auth.login('kunde@example.com', 'secret');

    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isFalse);
    expect(auth.hasAccount, isTrue);
    expect(auth.displayName, 'kunde@example.com');
  });

  test('upgradeGuestToAccount converts guest to account user', () async {
    final auth = AuthService();
    await auth.ready;
    await auth.loginAsGuest();

    await auth.upgradeGuestToAccount('kunde@example.com', 'secret');

    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isFalse);
    expect(auth.hasAccount, isTrue);
    expect(auth.displayName, 'kunde@example.com');
  });

  test('upgradeGuestToAccount throws when no guest session exists', () async {
    final auth = AuthService();
    await auth.ready;

    expect(
      () => auth.upgradeGuestToAccount('kunde@example.com', 'secret'),
      throwsStateError,
    );
  });

  test('restores persisted guest session on next service instance', () async {
    final auth = AuthService();
    await auth.ready;
    await auth.loginAsGuest();

    final restored = AuthService();
    await restored.ready;
    expect(restored.isLoggedIn, isTrue);
    expect(restored.isGuest, isTrue);
    expect(restored.displayName, 'Gast');
  });

  test('supabase login stores uuid and jwt', () async {
    final client = _FakeSupabaseAuthClient();
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;

    await auth.login('kunde@example.com', 'secret');

    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isFalse);
    expect(auth.backendUserId, 'user-uuid-1');
    expect(auth.backendJwt, 'jwt-token');
    expect(auth.profileExists, isTrue);
    expect(auth.profileEmail, 'kunde@example.com');
    expect(auth.profileBalanceEuro, 17.5);
    expect(auth.profileRole, AccountRole.customer);
    expect(auth.hasOperatorAccess, isFalse);
  });

  test('supabase register stores uuid and jwt', () async {
    final client = _FakeSupabaseAuthClient();
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;

    await auth.register('neu@example.com', 'secret');

    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isFalse);
    expect(auth.backendUserId, 'user-uuid-2');
    expect(auth.backendJwt, 'jwt-signup');
  });

  test('supabase login fails when profile is missing', () async {
    final client = _FakeSupabaseAuthClient()..returnMissingProfile = true;
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;

    await expectLater(
      () => auth.login('kunde@example.com', 'secret'),
      throwsA(isA<AuthException>()),
    );
  });

  test('supabase login loads operator role and persists it', () async {
    final client = _FakeSupabaseAuthClient()..profileRole = 'operator';
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;

    await auth.login('kunde@example.com', 'secret');
    expect(auth.profileRole, AccountRole.operator);
    expect(auth.hasOperatorAccess, isTrue);

    final restored = AuthService();
    await restored.ready;
    expect(restored.profileRole, AccountRole.operator);
    expect(restored.hasOperatorAccess, isTrue);
  });

  test('deleteAccount removes active account session', () async {
    final client = _FakeSupabaseAuthClient();
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;
    await auth.login('kunde@example.com', 'secret');

    await auth.deleteAccount();

    expect(client.deleteAccountCalled, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.hasAccount, isFalse);
    expect(auth.backendJwt, isNull);
    expect(auth.backendUserId, isNull);
  });

  test('topUpBalance allows authenticated customer account', () async {
    final client = _FakeSupabaseAuthClient();
    final auth = AuthService(
      httpClient: client,
      supabaseUrlProvider: () => 'https://example.supabase.co',
      supabaseApiKeyProvider: () => 'publishable-key',
    );
    await auth.ready;
    await auth.login('kunde@example.com', 'secret');

    final nextBalance = await auth.topUpBalance(amountEuro: 5);

    expect(nextBalance, 22.5);
    expect(auth.profileBalanceEuro, 22.5);
  });

  test(
    'topUpBalance maps forbidden backend error to friendly message',
    () async {
      final client = _FakeSupabaseAuthClient()
        ..topUpStatusCodeOverride = 403
        ..topUpErrorBodyOverride = const {
          'code': '42501',
          'message': 'forbidden',
        };
      final auth = AuthService(
        httpClient: client,
        supabaseUrlProvider: () => 'https://example.supabase.co',
        supabaseApiKeyProvider: () => 'publishable-key',
      );
      await auth.ready;
      await auth.login('kunde@example.com', 'secret');

      await expectLater(
        () => auth.topUpBalance(amountEuro: 5),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Aufladen ist fuer dieses Konto nicht erlaubt.',
          ),
        ),
      );
    },
  );
}
