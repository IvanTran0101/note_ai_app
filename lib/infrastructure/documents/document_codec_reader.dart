import 'dart:convert';

import '../sync/local_sync_codec_exception.dart';

/// Strict bounded parsing. Errors never include note text, URLs or equations.
final class DocumentCodecReader {
  int blocks = 0, cells = 0, runs = 0, bytes = 0;
  final Set<Object> _ancestors = Set.identity();

  void inspect(Object? value, [int depth = 0]) {
    if (depth > 36 || bytes > 180000) fail();
    if (value is String) {
      if (value.length > 180000) fail();
      bytes += utf8.encode(jsonEncode(value)).length;
    } else if (value is Map || value is List) {
      if (!_ancestors.add(value!)) fail();
      if (value is Map) {
        if (value.length > 16) fail();
        for (final entry in value.entries) {
          if (entry.key is! String) fail();
          inspect(entry.key, depth + 1);
          inspect(entry.value, depth + 1);
          bytes += 1;
        }
        if (value.isNotEmpty) bytes += value.length - 1;
      } else {
        final list = value as List;
        if (list.length > 4096) fail();
        for (final item in list) {
          inspect(item, depth + 1);
        }
        if (list.isNotEmpty) bytes += list.length - 1;
      }
      _ancestors.remove(value);
      bytes += 2;
    } else if (value == null || value is bool || value is num) {
      if (value is num && !value.isFinite) fail();
      bytes += jsonEncode(value).length;
    } else {
      fail();
    }
    if (bytes > 180000) fail();
  }

  Map<String, Object?> object(
    Object? raw,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    if (raw is! Map || raw.keys.any((k) => k is! String)) fail();
    final map = Map<String, Object?>.from(raw);
    if (!map.keys.toSet().containsAll(required) ||
        map.keys.any((k) => !required.contains(k) && !optional.contains(k))) {
      fail();
    }
    return map;
  }

  List<Object?> list(Object? value, int maximum) {
    if (value is! List || value.length > maximum) fail();
    return List<Object?>.from(value);
  }

  String string(Object? value) {
    if (value is! String) fail();
    return value;
  }

  bool boolean(Object? value) {
    if (value is! bool) fail();
    return value;
  }

  int integer(Object? value) {
    if (value is! int) fail();
    return value;
  }

  Never fail() => throw const LocalSyncCodecException(
    'Invalid or oversized rich document.',
    path: 'document',
  );
}
