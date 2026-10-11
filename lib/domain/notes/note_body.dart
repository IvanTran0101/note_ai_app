import 'dart:convert';

/// Versioned text-only Quill document carried by the existing content string.
/// Legacy or unrecognized content stays literal, never silently discarded.
abstract final class NoteBody {
  static const String prefix = 'noteflow:rich:v1\n';

  static List<Map<String, dynamic>>? delta(String content) {
    if (!content.startsWith(prefix)) return null;
    try {
      final value = jsonDecode(content.substring(prefix.length));
      if (value is! List || value.isEmpty) return null;
      final result = <Map<String, dynamic>>[];
      for (final operation in value) {
        if (operation is! Map<String, dynamic> ||
            operation['insert'] is! String ||
            (operation['insert'] as String).isEmpty ||
            operation.keys.any(
              (key) => key != 'insert' && key != 'attributes',
            )) {
          return null;
        }
        final attributes = operation['attributes'];
        if (attributes != null &&
            (attributes is! Map<String, dynamic> ||
                attributes.entries.any(
                  (entry) => !_attribute(entry.key, entry.value),
                ))) {
          return null;
        }
        result.add({
          ...operation,
          if (attributes is Map<String, dynamic>)
            'attributes': {
              for (final entry in attributes.entries)
                entry.key: (entry.key == 'header' || entry.key == 'indent')
                    ? (entry.value as num).toInt()
                    : entry.value,
            },
        });
      }
      if (!(result.last['insert'] as String).endsWith('\n')) return null;
      return result;
    } on FormatException {
      return null;
    }
  }

  static bool _attribute(String key, dynamic value) => switch (key) {
    'bold' ||
    'italic' ||
    'underline' ||
    'strike' ||
    'code' ||
    'blockquote' ||
    'code-block' => value is bool,
    'header' =>
      value is num &&
          value.isFinite &&
          value == value.truncateToDouble() &&
          value >= 1 &&
          value <= 6,
    'indent' =>
      value is num &&
          value.isFinite &&
          value == value.truncateToDouble() &&
          value >= 0 &&
          value <= 8,
    'color' || 'background' =>
      value is String &&
          (value.length == 7 || value.length == 9) &&
          RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value),
    'size' =>
      value is String &&
          (['small', 'large', 'huge'].contains(value) ||
              (RegExp(r'^\d+(\.\d+)?$').hasMatch(value) &&
                  (double.tryParse(value) ?? 0) >= 8 &&
                  (double.tryParse(value) ?? 0) <= 96)),
    'list' => ['ordered', 'bullet', 'checked', 'unchecked'].contains(value),
    'align' => ['left', 'center', 'right', 'justify'].contains(value),
    'direction' => value == 'rtl',
    'script' => value == 'sub' || value == 'super',
    'font' => value is String && value.length <= 100,
    'link' =>
      value is String &&
          RegExp(
            r'^(http|https|mailto):',
            caseSensitive: false,
          ).hasMatch(value),
    _ => false,
  };

  static String plainText(String content) {
    final operations = delta(content);
    if (operations == null) return content;
    final text = operations.map((op) => op['insert'] as String).join();
    return text.substring(0, text.length - 1);
  }

  static String encode(List<Map<String, dynamic>> operations) {
    final text = operations.map((op) => op['insert'] as String).join();
    final plain = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    if (plain.trim().isEmpty ||
        !operations.any(
          (op) => (op['attributes'] as Map?)?.isNotEmpty ?? false,
        )) {
      return plain;
    }
    return '$prefix${jsonEncode(operations)}';
  }
}
