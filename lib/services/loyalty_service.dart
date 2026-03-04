import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wash_session.dart';
import 'backend_http_client.dart';

class RewardRedemptionRecord {
  final int boxNumber;
  final DateTime redeemedAt;

  const RewardRedemptionRecord({
    required this.boxNumber,
    required this.redeemedAt,
  });
}

class LoyaltyService extends ChangeNotifier {
  static const String _prefCompleted = 'loyalty.completed';
  static const String _prefRewardSlots = 'loyalty.reward_slots';
  static const String _prefRedemptions = 'loyalty.redemptions_v1';
  static const String _prefProcessedSessionIds = 'loyalty.session_ids_v1';

  final BackendHttpClient _httpClient;
  final String Function() _baseUrlProvider;
  final String Function() _supabaseApiKeyProvider;
  final String? Function() _jwtProvider;

  int _completed = 0;
  int _rewardSlots = 0;
  final int goal = 10;
  final List<RewardRedemptionRecord> _redemptions = <RewardRedemptionRecord>[];
  final Set<String> _processedCompletedSessionIds = <String>{};

  int get completed => _completed;
  int get rewardSlots => _rewardSlots;
  double get progress => (_completed / goal).clamp(0, 1);
  int get remainingUntilReward {
    if (hasRewardAvailable) {
      return 0;
    }
    return (goal - _completed).clamp(0, goal);
  }

  bool get hasRewardAvailable => _rewardSlots > 0 || _completed >= goal;
  List<RewardRedemptionRecord> get redemptions =>
      List<RewardRedemptionRecord>.unmodifiable(_redemptions);

  List<RewardRedemptionRecord> recentRewardRedemptions({int limit = 5}) {
    if (_redemptions.length <= limit) {
      return redemptions;
    }
    return List<RewardRedemptionRecord>.unmodifiable(_redemptions.take(limit));
  }

  bool get hasRemoteAuthority => _hasRemoteAuth;

  LoyaltyService({
    BackendHttpClient? httpClient,
    String Function()? baseUrlProvider,
    String Function()? supabaseApiKeyProvider,
    String? Function()? jwtProvider,
  }) : _httpClient = httpClient ?? createBackendHttpClient(),
       _baseUrlProvider = baseUrlProvider ?? _emptyValue,
       _supabaseApiKeyProvider = supabaseApiKeyProvider ?? _emptyValue,
       _jwtProvider = jwtProvider ?? _emptyNullableValue {
    _restore();
  }

  Future<void> recordCompletedWashPurchase() async {
    if (_hasRemoteAuth) {
      await syncWithBackendOrThrow();
      return;
    }

    _advanceStampProgressBy(1);
    notifyListeners();
    await _persist();
  }

  Future<void> syncWithBackendOrThrow() async {
    if (!_hasRemoteAuth) {
      return;
    }
    final body = await _rpcPost(
      'loyalty_status',
      const <String, dynamic>{},
      'Stempelkarte laden',
    );
    _applyRemoteStatus(body);
    await _persist();
    notifyListeners();
  }

  Future<void> syncWithBackendIfAvailable() async {
    if (!_hasRemoteAuth) {
      return;
    }
    try {
      await syncWithBackendOrThrow();
    } on BackendHttpException {
      // Keep local cached loyalty state when backend cannot be reached.
    }
  }

  Future<void> consumeRewardAuthoritative({required int boxNumber}) async {
    if (_hasRemoteAuth) {
      await syncWithBackendOrThrow();
      return;
    }
    await redeemReward(boxNumber: boxNumber);
  }

  Future<void> ingestCompletedSessionsDeprecated(
    List<WashSession> sessions,
  ) async {
    if (_hasRemoteAuth) {
      await syncWithBackendIfAvailable();
      return;
    }

    if (sessions.isEmpty) {
      return;
    }
    var added = 0;
    for (final session in sessions) {
      if (session.sessionId.trim().isEmpty ||
          session.endedAt == null ||
          (session.amountEuro ?? 0) <= 0 ||
          _processedCompletedSessionIds.contains(session.sessionId)) {
        continue;
      }
      _processedCompletedSessionIds.add(session.sessionId);
      added += 1;
    }
    if (added <= 0) {
      return;
    }
    _advanceStampProgressBy(added);
    _trimProcessedSessionIds(maxCount: 500);
    notifyListeners();
    await _persist();
  }

  Future<void> redeemReward({required int boxNumber}) async {
    if (!hasRewardAvailable) {
      throw StateError('Keine Belohnung verfuegbar.');
    }
    if (_rewardSlots > 0) {
      _rewardSlots -= 1;
    } else if (_completed >= goal) {
      _completed = _completed % goal;
    }
    _recordRedemption(boxNumber);
    notifyListeners();
    await _persist();
    if (_hasRemoteAuth) {
      await syncWithBackendIfAvailable();
    }
  }

  void _recordRedemption(int boxNumber) {
    _redemptions.insert(
      0,
      RewardRedemptionRecord(boxNumber: boxNumber, redeemedAt: DateTime.now()),
    );
    if (_redemptions.length > 30) {
      _redemptions.removeRange(30, _redemptions.length);
    }
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefCompleted) ?? 0;
    _completed = value.clamp(0, goal);
    _rewardSlots = (prefs.getInt(_prefRewardSlots) ?? 0).clamp(0, 999);
    _redemptions
      ..clear()
      ..addAll(_restoreRedemptionsFromPrefs(prefs));
    _processedCompletedSessionIds
      ..clear()
      ..addAll(_restoreProcessedSessionIds(prefs));
    _trimProcessedSessionIds(maxCount: 500);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCompleted, _completed);
    await prefs.setInt(_prefRewardSlots, _rewardSlots);
    final encoded = _redemptions.map((entry) {
      return <String, dynamic>{
        'boxNumber': entry.boxNumber,
        'redeemedAt': entry.redeemedAt.toIso8601String(),
      };
    }).toList();
    await prefs.setString(_prefRedemptions, jsonEncode(encoded));
    final encodedSessionIds = _processedCompletedSessionIds.toList();
    await prefs.setString(
      _prefProcessedSessionIds,
      jsonEncode(encodedSessionIds),
    );
  }

  List<RewardRedemptionRecord> _restoreRedemptionsFromPrefs(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_prefRedemptions);
    if (raw == null || raw.isEmpty) {
      return const <RewardRedemptionRecord>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <RewardRedemptionRecord>[];
      }
      final records = <RewardRedemptionRecord>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final boxNumber = item['boxNumber'];
        final redeemedAtRaw = item['redeemedAt'];
        if (boxNumber is! int || redeemedAtRaw is! String) {
          continue;
        }
        final redeemedAt = DateTime.tryParse(redeemedAtRaw);
        if (redeemedAt == null) {
          continue;
        }
        records.add(
          RewardRedemptionRecord(boxNumber: boxNumber, redeemedAt: redeemedAt),
        );
      }
      records.sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
      if (records.length > 30) {
        records.removeRange(30, records.length);
      }
      return records;
    } catch (_) {
      return const <RewardRedemptionRecord>[];
    }
  }

  bool get _hasRemoteAuth {
    final jwt = _jwtProvider();
    return _baseUrlProvider().isNotEmpty &&
        _supabaseApiKeyProvider().isNotEmpty &&
        jwt != null &&
        jwt.isNotEmpty;
  }

  Future<Map<String, dynamic>> _rpcPost(
    String fn,
    Map<String, dynamic> payload,
    String action,
  ) async {
    final uri = Uri.parse('${_baseUrlProvider()}/rest/v1/rpc/$fn');
    final response = await _httpClient.postJson(
      uri,
      payload,
      headers: _authHeaders(),
    );
    final body = _asMap(response.body);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: '${body['message'] ?? action} (HTTP ${response.statusCode})',
      );
    }
    return body;
  }

  Map<String, String> _authHeaders() {
    final jwt = _jwtProvider();
    if (jwt == null || jwt.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{
      'apikey': _supabaseApiKeyProvider(),
      'Authorization': 'Bearer $jwt',
    };
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

  void _applyRemoteStatus(Map<String, dynamic> payload) {
    final completedRaw = payload['completed'] ?? payload['completed_purchases'];
    final rewardSlotsRaw = payload['reward_slots'] ?? payload['rewardSlots'];
    if (completedRaw is num) {
      _completed = completedRaw.toInt().clamp(0, goal);
    }
    if (rewardSlotsRaw is num) {
      _rewardSlots = rewardSlotsRaw.toInt().clamp(0, 999);
    }
  }

  void _advanceStampProgressBy(int count) {
    if (count <= 0) {
      return;
    }
    _completed += count;
    if (_completed >= goal) {
      _rewardSlots += _completed ~/ goal;
      _completed = _completed % goal;
    }
  }

  List<String> _restoreProcessedSessionIds(SharedPreferences prefs) {
    final raw = prefs.getString(_prefProcessedSessionIds);
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <String>[];
      }
      final items = <String>[];
      for (final item in decoded) {
        if (item is String && item.trim().isNotEmpty) {
          items.add(item.trim());
        }
      }
      return items;
    } catch (_) {
      return const <String>[];
    }
  }

  void _trimProcessedSessionIds({required int maxCount}) {
    if (_processedCompletedSessionIds.length <= maxCount) {
      return;
    }
    final retained = _processedCompletedSessionIds.take(maxCount).toList();
    _processedCompletedSessionIds
      ..clear()
      ..addAll(retained);
  }

  static String _emptyValue() => '';
  static String? _emptyNullableValue() => null;
}
