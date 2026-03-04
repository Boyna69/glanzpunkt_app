import 'package:flutter/foundation.dart';

import '../models/wallet_transaction.dart';
import 'backend_http_client.dart';

class WalletService extends ChangeNotifier {
  final BackendHttpClient _httpClient;
  final String Function() _baseUrlProvider;
  final String Function() _supabaseApiKeyProvider;
  final String? Function() _jwtProvider;

  final List<WalletTransaction> _transactions = <WalletTransaction>[];
  bool _isLoading = false;
  String? _lastErrorMessage;
  DateTime? _lastSyncedAt;

  List<WalletTransaction> get transactions =>
      List<WalletTransaction>.unmodifiable(_transactions);
  bool get isLoading => _isLoading;
  String? get lastErrorMessage => _lastErrorMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  List<WalletTransaction> get topUps => _transactions
      .where((tx) => tx.kind == WalletTransactionKind.topUp)
      .toList();

  List<WalletTransaction> get charges => _transactions
      .where((tx) => tx.kind == WalletTransactionKind.charge)
      .toList();

  WalletService({
    BackendHttpClient? httpClient,
    String Function()? baseUrlProvider,
    String Function()? supabaseApiKeyProvider,
    String? Function()? jwtProvider,
  }) : _httpClient = httpClient ?? createBackendHttpClient(),
       _baseUrlProvider = baseUrlProvider ?? _emptyValue,
       _supabaseApiKeyProvider = supabaseApiKeyProvider ?? _emptyValue,
       _jwtProvider = jwtProvider ?? _emptyNullableValue;

  Future<void> refresh({int limit = 80}) async {
    final jwt = _jwtProvider();
    if (jwt == null || jwt.isEmpty) {
      _transactions.clear();
      _lastErrorMessage = null;
      _lastSyncedAt = null;
      _notifySafely();
      return;
    }

    _isLoading = true;
    _notifySafely();
    try {
      final uri = Uri.parse(
        '${_baseUrlProvider()}/rest/v1/transactions'
        '?select=id,amount,created_at,description,type,kind'
        '&order=created_at.desc'
        '&limit=$limit',
      );
      final response = await _httpClient.getJson(
        uri,
        headers: <String, String>{
          'apikey': _supabaseApiKeyProvider(),
          'Authorization': 'Bearer $jwt',
        },
      );

      if (response.statusCode < 200 || response.statusCode > 299) {
        final message = response.body is Map
            ? (response.body as Map)['message'] as String?
            : null;
        throw StateError(
          message ??
              'Transaktionen konnten nicht geladen werden (HTTP ${response.statusCode}).',
        );
      }
      if (response.body is! List) {
        throw const BackendHttpException(
          kind: BackendHttpErrorKind.invalidResponse,
          message: 'Transaktionen: erwartete Liste.',
        );
      }

      final items = <WalletTransaction>[];
      for (final entry in response.body as List) {
        if (entry is! Map) {
          continue;
        }
        final row = Map<String, dynamic>.from(entry);
        final idRaw = row['id'];
        final amountRaw = row['amount'];
        final createdAtRaw = row['created_at'];
        if (idRaw == null || amountRaw is! num || createdAtRaw is! String) {
          continue;
        }
        final createdAt = DateTime.tryParse(createdAtRaw);
        if (createdAt == null) {
          continue;
        }
        final amount = amountRaw.toDouble();
        final kindRaw = row['kind'] ?? row['type'];
        items.add(
          WalletTransaction(
            id: idRaw.toString(),
            amount: amount,
            createdAt: createdAt,
            kind: _resolveKind(amount: amount, raw: kindRaw),
            description: row['description'] as String?,
          ),
        );
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _transactions
        ..clear()
        ..addAll(items);
      _lastSyncedAt = DateTime.now();
      _lastErrorMessage = null;
    } catch (e) {
      _lastErrorMessage = '$e';
    } finally {
      _isLoading = false;
      _notifySafely();
    }
  }

  WalletTransactionKind _resolveKind({
    required double amount,
    required Object? raw,
  }) {
    final normalized = (raw?.toString() ?? '').trim().toLowerCase();
    if (normalized.contains('top') ||
        normalized.contains('deposit') ||
        normalized.contains('credit')) {
      return WalletTransactionKind.topUp;
    }
    if (normalized.contains('charge') ||
        normalized.contains('debit') ||
        normalized.contains('wash')) {
      return WalletTransactionKind.charge;
    }
    if (amount > 0) {
      return WalletTransactionKind.topUp;
    }
    if (amount < 0) {
      return WalletTransactionKind.charge;
    }
    return WalletTransactionKind.unknown;
  }

  void clearError() {
    _lastErrorMessage = null;
    _notifySafely();
  }

  void _notifySafely() {
    if (!hasListeners) {
      return;
    }
    notifyListeners();
  }

  static String _emptyValue() => '';
  static String? _emptyNullableValue() => null;
}
