// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:developer';

const bool evidenceEnabled = bool.fromEnvironment('NOTEFLOW_EVIDENCE_TRACE');
String evidenceRunId = '';
String evidencePhase = 'idle';
int? evidenceLastSummaryUs;
String? _lastProvisioningPhase;
int _lastProvisioningTick = 0;
void evidenceTrace(String event, Map<String, Object?> fields) {
  if (!evidenceEnabled) return;
  try {
    print(
      'NF_EVIDENCE ${jsonEncode(<String, Object?>{'event': event, 'run_id': evidenceRunId, 'utc': DateTime.now().toUtc().toIso8601String(), 'timeline_us': Timeline.now, ...fields})}',
    );
  } on Object {
    /* Observation must not replace application results. */
  }
}

void evidenceProvisioning({
  required String phase,
  String? modelId,
  required int downloadedBytes,
  int? totalBytes,
}) {
  if (!evidenceEnabled) return;
  evidencePhase = phase;
  final int now = Timeline.now;
  if (_lastProvisioningPhase != phase ||
      now - _lastProvisioningTick >= 1000000 ||
      (totalBytes != null && downloadedBytes == totalBytes)) {
    _lastProvisioningPhase = phase;
    _lastProvisioningTick = now;
    evidenceTrace('provisioning', <String, Object?>{
      'phase': phase,
      'model_id': modelId,
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
    });
  }
}

void evidenceText(String kind, String text, {required int call}) {
  if (!evidenceEnabled || evidenceRunId.isEmpty) return;
  final String b64 = base64Encode(utf8.encode(text));
  const int size = 1500;
  final int parts = (b64.length + size - 1) ~/ size;
  for (int i = 0; i < parts; i++) {
    final int end = (i + 1) * size < b64.length ? (i + 1) * size : b64.length;
    evidenceTrace(kind, <String, Object?>{
      'call': call,
      'part': i,
      'parts': parts,
      'utf8_b64': b64.substring(i * size, end),
    });
  }
}
