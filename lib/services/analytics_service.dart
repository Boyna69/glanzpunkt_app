import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, String> properties;

  const AnalyticsEvent({
    required this.name,
    required this.timestamp,
    required this.properties,
  });
}

class AnalyticsService extends ChangeNotifier {
  static const String _prefEvents = 'analytics.events_v1';
  static const int _maxEvents = 200;

  final List<AnalyticsEvent> _events = <AnalyticsEvent>[];

  List<AnalyticsEvent> recentEvents({int limit = 30}) {
    if (_events.length <= limit) {
      return List<AnalyticsEvent>.unmodifiable(_events);
    }
    return List<AnalyticsEvent>.unmodifiable(_events.take(limit));
  }

  AnalyticsService() {
    _restore();
  }

  void track(String name, {Map<String, String>? properties}) {
    _events.insert(
      0,
      AnalyticsEvent(
        name: name,
        timestamp: DateTime.now(),
        properties: Map<String, String>.unmodifiable(properties ?? {}),
      ),
    );
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    notifyListeners();
    _persist();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefEvents);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      _events.clear();
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final name = item['name'];
        final timestampRaw = item['timestamp'];
        final propsRaw = item['properties'];
        if (name is! String || timestampRaw is! String) {
          continue;
        }
        final timestamp = DateTime.tryParse(timestampRaw);
        if (timestamp == null) {
          continue;
        }
        final properties = <String, String>{};
        if (propsRaw is Map) {
          propsRaw.forEach((key, value) {
            if (key is String && value is String) {
              properties[key] = value;
            }
          });
        }
        _events.add(
          AnalyticsEvent(
            name: name,
            timestamp: timestamp,
            properties: Map<String, String>.unmodifiable(properties),
          ),
        );
      }
      _events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (_events.length > _maxEvents) {
        _events.removeRange(_maxEvents, _events.length);
      }
      notifyListeners();
    } catch (_) {
      // Ignore malformed analytics payload.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _events.map((event) {
      return <String, dynamic>{
        'name': event.name,
        'timestamp': event.timestamp.toIso8601String(),
        'properties': event.properties,
      };
    }).toList();
    await prefs.setString(_prefEvents, jsonEncode(encoded));
  }
}
