import 'dart:convert';

import 'package:flutter/services.dart';

/// Backend stages; provider/model details remain outside Domain.
enum SummaryStage { direct, section, merge }

typedef _StagePolicy = ({
  int maxOutputTokens,
  String systemPrompt,
  String userPrompt,
});

/// Shared cloud Summary policy. This is an estimate, not a model tokenizer.
final class SummaryRequestPolicy {
  SummaryRequestPolicy._({
    required this.consentVersion,
    required this.maxInputEstimate,
    required this.framingHeadroom,
    required this.maxBodyBytesUtf8,
    required this.maxChunks,
    required this.maxGenerationCalls,
    required Map<SummaryStage, _StagePolicy> stages,
  }) : _stages = Map<SummaryStage, _StagePolicy>.unmodifiable(stages);

  static const String assetPath = 'assets/summary_policy.json';

  /// Native Flutter asset loading works on Web and native targets.
  static Future<SummaryRequestPolicy> load({AssetBundle? bundle}) async =>
      SummaryRequestPolicy.fromJson(
        await (bundle ?? rootBundle).loadString(assetPath),
      );

  factory SummaryRequestPolicy.fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    final Map<String, dynamic> data = _record(decoded);
    _keys(data, const <String>{
      'schemaVersion',
      'consentVersion',
      'maxInputEstimate',
      'framingHeadroom',
      'maxBodyBytesUtf8',
      'maxChunks',
      'maxGenerationCalls',
      'stages',
    });
    if (_integer(data['schemaVersion']) != 1) {
      throw const FormatException('Unsupported Summary policy version');
    }
    final String consent = _text(data['consentVersion']);
    final int input = _integer(data['maxInputEstimate']);
    final int reserve = _integer(data['framingHeadroom'], minimum: 0);
    final int body = _integer(data['maxBodyBytesUtf8']);
    final int chunks = _integer(data['maxChunks'], minimum: 2);
    final int calls = _integer(data['maxGenerationCalls']);
    if (input <= reserve || calls != chunks + 1) {
      throw const FormatException('Invalid Summary policy budget');
    }
    final Map<String, dynamic> rawStages = _record(data['stages']);
    _keys(rawStages, SummaryStage.values.map((stage) => stage.name).toSet());
    final Map<SummaryStage, _StagePolicy> stages =
        <SummaryStage, _StagePolicy>{};
    for (final SummaryStage stage in SummaryStage.values) {
      final Map<String, dynamic> raw = _record(rawStages[stage.name]);
      _keys(raw, const <String>{
        'maxOutputTokens',
        'systemPrompt',
        'userPrompt',
      });
      stages[stage] = (
        maxOutputTokens: _integer(raw['maxOutputTokens']),
        systemPrompt: _text(raw['systemPrompt']),
        userPrompt: _text(raw['userPrompt']),
      );
    }
    return SummaryRequestPolicy._(
      consentVersion: consent,
      maxInputEstimate: input,
      framingHeadroom: reserve,
      maxBodyBytesUtf8: body,
      maxChunks: chunks,
      maxGenerationCalls: calls,
      stages: stages,
    );
  }

  final String consentVersion;
  final int maxInputEstimate;
  final int framingHeadroom;
  final int maxBodyBytesUtf8;
  final int maxChunks;
  final int maxGenerationCalls;
  final Map<SummaryStage, _StagePolicy> _stages;

  int maxOutputTokens(SummaryStage stage) => _stages[stage]!.maxOutputTokens;

  List<Map<String, String>> buildMessages(
    SummaryStage stage,
    List<String> inputs,
  ) {
    final bool merge = stage == SummaryStage.merge;
    if ((!merge && inputs.length != 1) ||
        (merge && (inputs.length < 2 || inputs.length > maxChunks))) {
      throw ArgumentError('Invalid Summary input count');
    }
    final List<String> normalized = inputs.map(_jsTrim).toList(growable: false);
    if (normalized.any((input) => input.isEmpty)) {
      throw ArgumentError('Summary input is empty');
    }
    final _StagePolicy policy = _stages[stage]!;
    final String payload = jsonEncode(merge ? normalized : normalized.single);
    return <Map<String, String>>[
      <String, String>{'role': 'system', 'content': policy.systemPrompt},
      <String, String>{
        'role': 'user',
        'content': '${policy.userPrompt}\n$payload',
      },
    ];
  }

  String requestJson(SummaryStage stage, List<String> inputs) => jsonEncode(
    <String, Object?>{
      'stage': stage.name,
      'inputs': inputs,
      'consent': <String, Object?>{'accepted': true, 'version': consentVersion},
    },
  );

  String messagesJson(SummaryStage stage, List<String> inputs) =>
      jsonEncode(buildMessages(stage, inputs));

  int estimateInputTokens(SummaryStage stage, List<String> inputs) =>
      utf8.encode(messagesJson(stage, inputs)).length + framingHeadroom;

  bool fitsInput(SummaryStage stage, List<String> inputs) =>
      estimateInputTokens(stage, inputs) <= maxInputEstimate;

  /// Normalizes caller-supplied content the way this policy renders it.
  ///
  /// The remote orchestrator uses this for its own emptiness and boundary
  /// decisions so it sees exactly the text this policy estimates and the
  /// backend trims. Dart's `trim` is not a substitute: it also removes U+0085,
  /// which ECMAScript whitespace does not contain.
  static String normalizeInput(String value) => _jsTrim(value);

  static Map<String, dynamic> _record(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Summary policy object');
    }
    return value;
  }

  static void _keys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !keys.every(value.containsKey)) {
      throw const FormatException('Invalid Summary policy fields');
    }
  }

  static int _integer(Object? value, {int minimum = 1}) {
    if (value is! num ||
        !value.isFinite ||
        value < minimum ||
        value > 9007199254740991 ||
        value % 1 != 0) {
      throw const FormatException('Invalid Summary policy integer');
    }
    return value.toInt();
  }

  static String _text(Object? value) {
    if (value is! String || _jsTrim(value).isEmpty) {
      throw const FormatException('Invalid Summary policy text');
    }
    return value;
  }

  // ECMAScript trim parity: Dart also trims U+0085, but the backend does not.
  static const Set<int> _edgeWhitespace = <int>{
    0x0020,
    0x00A0,
    0x1680,
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x3000,
    0xFEFF,
  };

  static bool isInputWhitespace(int unit) =>
      (unit >= 0x0009 && unit <= 0x000D) ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      _edgeWhitespace.contains(unit);

  static String _jsTrim(String value) {
    int start = 0;
    int end = value.length;
    while (start < end && isInputWhitespace(value.codeUnitAt(start))) {
      start++;
    }
    while (end > start && isInputWhitespace(value.codeUnitAt(end - 1))) {
      end--;
    }
    return value.substring(start, end);
  }
}
