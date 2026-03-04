import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/box.dart';
import 'environment_service.dart';
import 'auth_service.dart';
import 'wash_backend_gateway.dart';

class BoxRealtimeService {
  final AuthService _authService;
  final EnvironmentService _environmentService;
  final String _supabaseBaseUrl;

  final StreamController<BoxStatusResponse> _controller =
      StreamController<BoxStatusResponse>.broadcast();

  RealtimeChannel? _channel;
  bool _started = false;
  int _ref = 0;

  BoxRealtimeService({
    required AuthService authService,
    required EnvironmentService environmentService,
    required String supabaseBaseUrl,
  }) : _authService = authService,
       _environmentService = environmentService,
       _supabaseBaseUrl = supabaseBaseUrl;

  Stream<BoxStatusResponse> get updates => _controller.stream;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _authService.addListener(_handleAuthChanged);
    _environmentService.addListener(_handleEnvironmentChanged);
    _syncRealtimeAuth();
    _restartSubscription();
  }

  Future<void> dispose() async {
    _authService.removeListener(_handleAuthChanged);
    _environmentService.removeListener(_handleEnvironmentChanged);
    await _unsubscribe();
    await _controller.close();
  }

  void _handleAuthChanged() {
    _syncRealtimeAuth();
  }

  void _handleEnvironmentChanged() {
    _restartSubscription();
  }

  bool get _isSupabaseEnvironment {
    return _normalizeOrigin(_environmentService.activeBaseUrl) ==
        _normalizeOrigin(_supabaseBaseUrl);
  }

  String _normalizeOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portPart';
  }

  void _syncRealtimeAuth() {
    final jwt = _authService.backendJwt;
    if (jwt == null || jwt.isEmpty) {
      return;
    }
    Supabase.instance.client.realtime.setAuth(jwt);
  }

  Future<void> _restartSubscription() async {
    await _unsubscribe();
    if (!_isSupabaseEnvironment) {
      return;
    }
    _subscribe();
  }

  void _subscribe() {
    _ref += 1;
    final topic = 'public:boxes:$_ref';
    _channel = Supabase.instance.client
        .channel(topic)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'boxes',
          callback: _onPostgresChange,
        )
        .subscribe();
  }

  Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) {
      return;
    }
    await Supabase.instance.client.removeChannel(channel);
  }

  void _onPostgresChange(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record.isEmpty) {
      return;
    }
    final idRaw = record['id'];
    final stateRaw = record['status'];
    if (idRaw is! num || stateRaw is! String) {
      return;
    }
    final remainingRaw = record['remaining_seconds'];
    final remainingSeconds = remainingRaw is num ? remainingRaw.toInt() : null;
    final remainingMinutes = remainingSeconds == null
        ? null
        : (remainingSeconds / 60).ceil();

    try {
      final parsedState = _parseState(stateRaw);
      _controller.add(
        BoxStatusResponse(
          boxNumber: idRaw.toInt(),
          state: parsedState,
          remainingMinutes: remainingMinutes,
          remainingSeconds: remainingSeconds,
        ),
      );
    } catch (_) {
      // Ignore unknown statuses from backend extensions.
    }
  }

  BoxState _parseState(String raw) {
    final normalized = raw.trim();
    if (normalized == 'out_of_service') {
      return BoxState.outOfService;
    }
    if (normalized == 'occupied') {
      return BoxState.active;
    }
    for (final state in BoxState.values) {
      if (state.name == normalized) {
        return state;
      }
    }
    throw StateError('Unbekannter state: $raw');
  }
}
