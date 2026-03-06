import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import 'backend_http_client.dart';

enum AccountRole { customer, operator, owner }

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  static const String _prefLoggedIn = 'auth.logged_in';
  static const String _prefIsGuest = 'auth.is_guest';
  static const String _prefEmail = 'auth.email';
  static const String _prefBackendUserId = 'auth.backend_user_id';
  static const String _prefBackendJwt = 'auth.backend_jwt';
  static const String _prefProfileExists = 'auth.profile_exists';
  static const String _prefProfileEmail = 'auth.profile_email';
  static const String _prefProfileBalanceEuro = 'auth.profile_balance_euro';
  static const String _prefProfileRole = 'auth.profile_role';
  final BackendHttpClient _httpClient;
  final String Function() _supabaseUrlProvider;
  final String Function() _supabaseApiKeyProvider;

  bool _loggedIn = false;
  bool _isGuest = false;
  String _email = '';
  String? _backendUserId;
  String? _backendJwt;
  bool _profileExists = false;
  String? _profileEmail;
  double _profileBalanceEuro = 0;
  AccountRole _profileRole = AccountRole.customer;
  final Completer<void> _readyCompleter = Completer<void>();

  bool get isLoggedIn => _loggedIn;
  bool get isGuest => _isGuest;
  bool get hasAccount => _loggedIn && !_isGuest;
  String get email => _email;
  String get displayName => _isGuest ? 'Gast' : _email;
  String? get backendUserId => _backendUserId;
  String? get backendJwt => _backendJwt;
  bool get profileExists => _profileExists;
  String? get profileEmail => _profileEmail;
  double get profileBalanceEuro => _profileBalanceEuro;
  AccountRole get profileRole => _profileRole;
  bool get isCustomerAccount => _profileRole == AccountRole.customer;
  bool get canTopUpBalance =>
      isTopUpAllowedForContext(hasAccount: hasAccount, role: _profileRole);
  bool get hasOperatorAccess =>
      _profileRole == AccountRole.operator || _profileRole == AccountRole.owner;
  Future<void> get ready => _readyCompleter.future;
  bool get _hasSupabaseConfig =>
      _supabaseUrlProvider().isNotEmpty && _supabaseApiKeyProvider().isNotEmpty;

  static bool isTopUpAllowedForContext({
    required bool hasAccount,
    required AccountRole role,
    bool? customerTopUpEnabled,
  }) {
    if (!hasAccount) {
      return false;
    }
    if (role == AccountRole.customer) {
      return customerTopUpEnabled ?? AppConfig.customerTopUpEnabled;
    }
    return true;
  }

  AuthService({
    BackendHttpClient? httpClient,
    String Function()? supabaseUrlProvider,
    String Function()? supabaseApiKeyProvider,
  }) : _httpClient = httpClient ?? createBackendHttpClient(),
       _supabaseUrlProvider = supabaseUrlProvider ?? _emptyValue,
       _supabaseApiKeyProvider = supabaseApiKeyProvider ?? _emptyValue {
    _restoreSession();
  }

  Future<void> login(String email, String password) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Bitte E-Mail und Passwort eingeben.');
    }
    if (!_hasSupabaseConfig) {
      _setAuthenticatedAccount(
        email: normalizedEmail,
        userId: _backendUserId,
        jwt: _backendJwt,
      );
      await _persistSession();
      return;
    }

    try {
      final uri = Uri.parse(
        '${_supabaseUrlProvider()}/auth/v1/token?grant_type=password',
      );
      final response = await _httpClient.postJson(uri, {
        'email': normalizedEmail,
        'password': password,
      }, headers: _supabaseHeaders());
      final body = _asMap(response.body);
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw AuthException(
          _extractSupabaseError(body, 'Login fehlgeschlagen.'),
        );
      }
      final user = _asMap(body['user']);
      final userId = user['id'] as String?;
      final jwt = body['access_token'] as String?;
      final responseEmail =
          (user['email'] as String?)?.trim().isNotEmpty == true
          ? (user['email'] as String).trim()
          : normalizedEmail;
      if (userId == null || userId.isEmpty || jwt == null || jwt.isEmpty) {
        throw const AuthException('Supabase Login-Response ist unvollständig.');
      }
      _setAuthenticatedAccount(email: responseEmail, userId: userId, jwt: jwt);
      await _loadProfileAndBalanceOrThrow(userId: userId, jwt: jwt);
      await _persistSession();
    } on BackendHttpException catch (e) {
      throw AuthException(_mapHttpErrorToMessage(e));
    }
  }

  Future<void> updateBackendIdentity({String? userId, String? jwt}) async {
    _backendUserId = userId;
    _backendJwt = jwt;
    notifyListeners();
    if (_backendUserId != null &&
        _backendUserId!.isNotEmpty &&
        _backendJwt != null &&
        _backendJwt!.isNotEmpty &&
        _hasSupabaseConfig) {
      await _loadProfileAndBalanceOrThrow(
        userId: _backendUserId!,
        jwt: _backendJwt!,
      );
    }
    await _persistSession();
  }

  Future<void> refreshProfileAndBalance() async {
    if (!_loggedIn || _isGuest) {
      return;
    }
    final userId = _backendUserId;
    final jwt = _backendJwt;
    if (userId == null || userId.isEmpty || jwt == null || jwt.isEmpty) {
      return;
    }
    if (!_hasSupabaseConfig) {
      return;
    }
    await _loadProfileAndBalanceOrThrow(userId: userId, jwt: jwt);
    await _persistSession();
  }

  Future<double> topUpBalance({required int amountEuro}) async {
    if (amountEuro <= 0) {
      throw const AuthException('Ungueltiger Aufladebetrag.');
    }
    if (!_loggedIn || _isGuest) {
      throw const AuthException('Aufladen nur mit Konto moeglich.');
    }
    if (!canTopUpBalance) {
      throw const AuthException('Kunden-Aufladung ist aktuell deaktiviert.');
    }
    final jwt = _backendJwt;
    if (jwt == null || jwt.isEmpty) {
      throw const AuthException('Keine gueltige Session vorhanden.');
    }
    if (!_hasSupabaseConfig) {
      _profileBalanceEuro += amountEuro;
      notifyListeners();
      await _persistSession();
      return _profileBalanceEuro;
    }

    try {
      final uri = Uri.parse('${_supabaseUrlProvider()}/rest/v1/rpc/top_up');
      final response = await _httpClient.postJson(
        uri,
        <String, dynamic>{'amount': amountEuro},
        headers: <String, String>{
          'apikey': _supabaseApiKeyProvider(),
          'Authorization': 'Bearer $jwt',
        },
      );
      final body = _asMap(response.body);
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw AuthException(
          _mapTopUpErrorFromBody(
            body,
            statusCode: response.statusCode,
            fallback: 'Aufladen fehlgeschlagen.',
          ),
        );
      }

      final parsedBalance =
          body['balance'] ??
          body['new_balance'] ??
          body['balance_eur'] ??
          body['credit_eur'];
      if (parsedBalance is num) {
        _profileBalanceEuro = parsedBalance.toDouble();
      } else {
        _profileBalanceEuro += amountEuro;
      }
      notifyListeners();
      await _persistSession();
      return _profileBalanceEuro;
    } on BackendHttpException catch (e) {
      throw AuthException(_mapHttpErrorToMessage(e));
    }
  }

  Future<void> loginAsGuest() async {
    _loggedIn = true;
    _isGuest = true;
    _email = '';
    _backendUserId = null;
    _backendJwt = null;
    _profileExists = false;
    _profileEmail = null;
    _profileBalanceEuro = 0;
    _profileRole = AccountRole.customer;
    notifyListeners();
    await _persistSession();
  }

  Future<void> upgradeGuestToAccount(String email, String password) async {
    if (!_loggedIn || !_isGuest) {
      throw StateError('Aktuell ist keine Gastsession aktiv.');
    }
    await register(email, password);
  }

  Future<void> register(String email, String password) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Bitte E-Mail und Passwort eingeben.');
    }
    if (!_hasSupabaseConfig) {
      _setAuthenticatedAccount(
        email: normalizedEmail,
        userId: _backendUserId,
        jwt: _backendJwt,
      );
      await _persistSession();
      return;
    }

    try {
      final uri = Uri.parse('${_supabaseUrlProvider()}/auth/v1/signup');
      final response = await _httpClient.postJson(uri, {
        'email': normalizedEmail,
        'password': password,
      }, headers: _supabaseHeaders());
      final body = _asMap(response.body);
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw AuthException(
          _extractSupabaseError(body, 'Registrierung fehlgeschlagen.'),
        );
      }
      final user = _asMap(body['user']);
      final userId = user['id'] as String?;
      final responseEmail =
          (user['email'] as String?)?.trim().isNotEmpty == true
          ? (user['email'] as String).trim()
          : normalizedEmail;
      final jwt = body['access_token'] as String? ?? body['token'] as String?;
      if (jwt == null || jwt.isEmpty) {
        await login(normalizedEmail, password);
        return;
      }
      if (userId == null || userId.isEmpty) {
        throw const AuthException(
          'Supabase Registrierungs-Response ist unvollständig.',
        );
      }
      _setAuthenticatedAccount(email: responseEmail, userId: userId, jwt: jwt);
      await _loadProfileAndBalanceOrThrow(userId: userId, jwt: jwt);
      await _persistSession();
    } on BackendHttpException catch (e) {
      throw AuthException(_mapHttpErrorToMessage(e));
    }
  }

  Future<void> logout() async {
    _loggedIn = false;
    _isGuest = false;
    _email = '';
    _backendUserId = null;
    _backendJwt = null;
    _profileExists = false;
    _profileEmail = null;
    _profileBalanceEuro = 0;
    _profileRole = AccountRole.customer;
    notifyListeners();
    await _persistSession();
  }

  Future<void> deleteAccount() async {
    if (!_loggedIn || _isGuest) {
      throw const AuthException('Konto-Loeschung nur mit Konto moeglich.');
    }
    final jwt = _backendJwt;
    if (jwt == null || jwt.isEmpty) {
      throw const AuthException('Keine gueltige Session vorhanden.');
    }

    if (!_hasSupabaseConfig) {
      await logout();
      return;
    }

    try {
      final uri = Uri.parse(
        '${_supabaseUrlProvider()}/functions/v1/delete-account',
      );
      final response = await _httpClient.postJson(
        uri,
        const <String, dynamic>{},
        headers: <String, String>{
          'apikey': _supabaseApiKeyProvider(),
          'Authorization': 'Bearer $jwt',
        },
      );
      final body = _asMap(response.body);
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw AuthException(
          _extractSupabaseError(body, 'Konto-Loeschung fehlgeschlagen.'),
        );
      }
      await logout();
    } on BackendHttpException catch (e) {
      throw AuthException(_mapHttpErrorToMessage(e));
    }
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loggedIn = prefs.getBool(_prefLoggedIn) ?? false;
      _isGuest = prefs.getBool(_prefIsGuest) ?? false;
      _email = prefs.getString(_prefEmail) ?? '';
      _backendUserId = prefs.getString(_prefBackendUserId);
      _backendJwt = prefs.getString(_prefBackendJwt);
      _profileExists = prefs.getBool(_prefProfileExists) ?? false;
      _profileEmail = prefs.getString(_prefProfileEmail);
      _profileBalanceEuro = prefs.getDouble(_prefProfileBalanceEuro) ?? 0;
      _profileRole = _parseRole(prefs.getString(_prefProfileRole));
      notifyListeners();
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLoggedIn, _loggedIn);
    await prefs.setBool(_prefIsGuest, _isGuest);
    await prefs.setString(_prefEmail, _email);
    if (_backendUserId == null || _backendUserId!.isEmpty) {
      await prefs.remove(_prefBackendUserId);
    } else {
      await prefs.setString(_prefBackendUserId, _backendUserId!);
    }
    if (_backendJwt == null || _backendJwt!.isEmpty) {
      await prefs.remove(_prefBackendJwt);
    } else {
      await prefs.setString(_prefBackendJwt, _backendJwt!);
    }
    await prefs.setBool(_prefProfileExists, _profileExists);
    if (_profileEmail == null || _profileEmail!.isEmpty) {
      await prefs.remove(_prefProfileEmail);
    } else {
      await prefs.setString(_prefProfileEmail, _profileEmail!);
    }
    await prefs.setDouble(_prefProfileBalanceEuro, _profileBalanceEuro);
    await prefs.setString(_prefProfileRole, _profileRole.name);
  }

  void _setAuthenticatedAccount({
    required String email,
    String? userId,
    String? jwt,
  }) {
    _loggedIn = true;
    _isGuest = false;
    _email = email;
    _backendUserId = userId;
    _backendJwt = jwt;
    _profileExists = false;
    _profileEmail = null;
    _profileBalanceEuro = 0;
    _profileRole = AccountRole.customer;
    notifyListeners();
  }

  Future<void> _loadProfileAndBalanceOrThrow({
    required String userId,
    required String jwt,
  }) async {
    final encodedUserFilter = 'eq.$userId';
    final uri = Uri.parse(
      '${_supabaseUrlProvider()}/rest/v1/profiles'
      '?id=$encodedUserFilter'
      '&select=*'
      '&limit=1',
    );
    final response = await _httpClient.getJson(
      uri,
      headers: <String, String>{
        'apikey': _supabaseApiKeyProvider(),
        'Authorization': 'Bearer $jwt',
      },
    );
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AuthException(
        'Profil konnte nicht geladen werden (HTTP ${response.statusCode}).',
      );
    }
    if (response.body is! List) {
      throw const AuthException('Ungueltige Profil-Antwort vom Backend.');
    }
    final items = response.body as List;
    if (items.isEmpty || items.first is! Map) {
      throw const AuthException(
        'Kein Profil gefunden. Bitte Support kontaktieren.',
      );
    }
    final profile = Map<String, dynamic>.from(items.first as Map);
    final profileId = profile['id'] as String?;
    if (profileId == null || profileId != userId) {
      throw const AuthException('Profil-Validierung fehlgeschlagen.');
    }
    _profileExists = true;
    final email = profile['email'];
    _profileEmail = email is String && email.trim().isNotEmpty
        ? email.trim()
        : _email;
    _profileBalanceEuro = _readBalanceEuro(profile);
    final roleRaw = profile['role'] as String?;
    _profileRole = _parseRole(roleRaw);
    notifyListeners();
  }

  double _readBalanceEuro(Map<String, dynamic> profile) {
    final directEuro =
        profile['balance_eur'] ?? profile['balance'] ?? profile['credit_eur'];
    if (directEuro is num) {
      return directEuro.toDouble();
    }
    final cents = profile['balance_cents'] ?? profile['credit_cents'];
    if (cents is num) {
      return cents.toDouble() / 100.0;
    }
    return 0;
  }

  AccountRole _parseRole(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'owner':
        return AccountRole.owner;
      case 'operator':
        return AccountRole.operator;
      default:
        return AccountRole.customer;
    }
  }

  Map<String, String> _supabaseHeaders() {
    final key = _supabaseApiKeyProvider();
    return <String, String>{'apikey': key, 'Authorization': 'Bearer $key'};
  }

  String _extractSupabaseError(Map<String, dynamic> body, String fallback) {
    final message = body['msg'] ?? body['message'] ?? body['error_description'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    final error = body['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    return fallback;
  }

  String _mapTopUpErrorFromBody(
    Map<String, dynamic> body, {
    required int statusCode,
    required String fallback,
  }) {
    final raw = _extractSupabaseError(body, fallback).toLowerCase();
    final code = (body['code'] as String?)?.toLowerCase() ?? '';
    if (statusCode == 401 || raw.contains('unauthorized')) {
      return 'Sitzung abgelaufen. Bitte neu einloggen.';
    }
    if (statusCode == 403 || raw.contains('forbidden') || code == '42501') {
      return 'Aufladen ist fuer dieses Konto nicht erlaubt.';
    }
    if (raw.contains('invalid_amount') || raw.contains('ungueltig')) {
      return 'Ungueltiger Aufladebetrag.';
    }
    if (statusCode >= 500 ||
        raw.contains('backend_unavailable') ||
        raw.contains('timeout')) {
      return 'Backend aktuell nicht erreichbar. Bitte spaeter erneut versuchen.';
    }
    return 'Aufladen fehlgeschlagen. Bitte erneut versuchen.';
  }

  String _mapHttpErrorToMessage(BackendHttpException exception) {
    switch (exception.kind) {
      case BackendHttpErrorKind.timeout:
        return 'Zeitueberschreitung beim Auth-Request.';
      case BackendHttpErrorKind.network:
        return 'Netzwerkfehler. Bitte Verbindung pruefen.';
      case BackendHttpErrorKind.invalidResponse:
        return 'Ungueltige Antwort vom Auth-Service.';
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static String _emptyValue() => '';
}
