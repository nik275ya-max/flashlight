import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Measures the RMS loudness of a local audio file and caches the result.
///
/// On Android the analysis runs in a native background thread through the
/// `com.magictech.flashlight/background` method channel. Other platforms have
/// no decoder available and [analyze] returns null; callers should fall back
/// to full volume in that case.
class LoudnessService {
  // ignore: prefer_initializing_formals
  LoudnessService({MethodChannel? channel}) : _channel = channel;

  static const _cacheKey = 'loudnessCache';

  final MethodChannel? _channel;
  Map<String, double> _cache = const {};

  /// All loudness values currently cached, keyed by file path (dBFS).
  Map<String, double> get cache => Map.unmodifiable(_cache);

  /// Loads the persisted cache. Call once during app initialization.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cache = decoded.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        );
      } catch (_) {
        _cache = const {};
      }
    }
  }

  /// Returns the cached loudness for [path], or null when not analyzed yet.
  double? loudnessOf(String path) => _cache[path];

  /// Analyzes [path] and stores the result. Returns the RMS in dBFS, or null
  /// when analysis is unavailable (non-Android, unsupported format, file
  /// missing). A previously cached value is reused unless [force] is true.
  Future<double?> analyze(String path, {bool force = false}) async {
    if (!force && _cache.containsKey(path)) return _cache[path];
    final channel = _channel;
    if (channel == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final result = await channel
          .invokeMethod<Map>('analyzeLoudness', {'path': path})
          .timeout(const Duration(seconds: 30));
      final rmsDb = (result?['rmsDb'] as num?)?.toDouble();
      if (rmsDb != null) {
        _cache = {..._cache, path: rmsDb};
        await _persist();
      }
      return rmsDb;
    } on PlatformException {
      return null;
    } on TimeoutException {
      // Native analysis took too long (e.g. a very large file or a decoder
      // stall); treat as unknown so playback falls back to full volume.
      return null;
    }
  }

  /// Drops the cached value for [path].
  Future<void> forget(String path) async {
    if (!_cache.containsKey(path)) return;
    _cache = Map.of(_cache)..remove(path);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_cache));
  }
}
