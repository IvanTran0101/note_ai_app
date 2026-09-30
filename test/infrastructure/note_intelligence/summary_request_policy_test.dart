import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

final class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle(this.source);
  final String source;
  String? requestedKey;

  @override
  Future<ByteData> load(String key) async {
    requestedKey = key;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String source = File(SummaryRequestPolicy.assetPath).readAsStringSync();
  final SummaryRequestPolicy policy = SummaryRequestPolicy.fromJson(source);
  final Map<String, dynamic> golden = jsonDecode(
    File('test/fixtures/summary_policy_golden.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('normalization stays linear for long interior whitespace', () {
    final String input = 'a${' ' * 300000}b';
    expect(SummaryRequestPolicy.normalizeInput('  $input  '), input);
  });

  test('shared policy retains contract v0.3 defaults', () {
    expect(policy.consentVersion, 'summary-cloud-v1');
    expect(policy.maxInputEstimate, 16000);
    expect(policy.framingHeadroom, 256);
    expect(policy.maxBodyBytesUtf8, 262144);
    expect(policy.maxChunks, 4);
    expect(policy.maxGenerationCalls, 5);
    for (final SummaryStage stage in SummaryStage.values) {
      expect(
        policy.maxOutputTokens(stage),
        stage == SummaryStage.section ? 128 : 256,
      );
    }
  });

  for (final dynamic entry in golden['cases'] as List<dynamic>) {
    final Map<String, dynamic> sample = entry as Map<String, dynamic>;
    test('backend parity: ${sample['id']}', () {
      final SummaryStage stage = SummaryStage.values.byName(
        sample['stage'] as String,
      );
      final Map<String, dynamic>? repeat =
          sample['repeatInput'] as Map<String, dynamic>?;
      final List<String> inputs = repeat == null
          ? (sample['inputs'] as List<dynamic>).cast<String>()
          : <String>[
              List<String>.filled(
                repeat['count'] as int,
                repeat['unit'] as String,
              ).join(),
            ];
      if (sample.containsKey('expectedMessagesJson')) {
        expect(
          policy.messagesJson(stage, inputs),
          sample['expectedMessagesJson'],
        );
      }
      expect(
        policy.estimateInputTokens(stage, inputs),
        sample['expectedEstimate'],
      );
      expect(policy.fitsInput(stage, inputs), sample['expectedFits']);
    });
  }

  test('Flutter asset loader uses the registered policy path', () async {
    final _MemoryBundle bundle = _MemoryBundle(source);
    final SummaryRequestPolicy loaded = await SummaryRequestPolicy.load(
      bundle: bundle,
    );
    expect(bundle.requestedKey, SummaryRequestPolicy.assetPath);
    expect(
      loaded.estimateInputTokens(SummaryStage.direct, <String>['x']),
      policy.estimateInputTokens(SummaryStage.direct, <String>['x']),
    );
  });

  test('actual bundled asset is loadable', () async {
    final SummaryRequestPolicy loaded = await SummaryRequestPolicy.load();
    expect(loaded.maxInputEstimate, policy.maxInputEstimate);
  });

  test('bad policy fails closed', () {
    for (final void Function(Map<String, dynamic>) change
        in <void Function(Map<String, dynamic>)>[
          (data) => data['schemaVersion'] = 2,
          (data) => data['maxInputEstimate'] = true,
          (data) => data['framingHeadroom'] = -1,
          (data) => data['maxGenerationCalls'] = 4,
          (data) => data['providerKey'] = 'synthetic-forbidden-field',
          (data) => (data['stages'] as Map<String, dynamic>).remove('merge'),
          (data) =>
              ((data['stages'] as Map<String, dynamic>)['section']
                      as Map<String, dynamic>)['maxOutputTokens'] =
                  0,
        ]) {
      final Map<String, dynamic> data =
          jsonDecode(source) as Map<String, dynamic>;
      change(data);
      expect(
        () => SummaryRequestPolicy.fromJson(jsonEncode(data)),
        throwsFormatException,
      );
    }
    expect(() => SummaryRequestPolicy.fromJson('[]'), throwsFormatException);
  });

  test('stage cardinality and empty inputs are rejected without reflecting content', () {
    expect(
      () => policy.buildMessages(SummaryStage.direct, <String>[]),
      throwsArgumentError,
    );
    expect(
      () => policy.buildMessages(SummaryStage.section, <String>['a', 'b']),
      throwsArgumentError,
    );
    expect(
      () => policy.buildMessages(SummaryStage.merge, <String>['a']),
      throwsArgumentError,
    );
    expect(
      () => policy.buildMessages(SummaryStage.merge, <String>[
        'a',
        'b',
        'c',
        'd',
        'e',
      ]),
      throwsArgumentError,
    );
    expect(
      () => policy.buildMessages(SummaryStage.direct, <String>['\uFEFF\u00A0']),
      throwsArgumentError,
    );
    expect(
      policy.buildMessages(SummaryStage.direct, <String>[
        '\u0085',
      ]).last['content'],
      contains('\u0085'),
    );
  });
}
