import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/scheduler.dart';

import 'trace.dart';

void installEvidenceFrames() {
  if (!evidenceEnabled ||
      !const bool.fromEnvironment('NOTEFLOW_EVIDENCE_FRAMES')) {
    return;
  }
  int batch = 0;
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> frames) {
    final int currentBatch = ++batch;
    for (final FrameTiming frame in frames) {
      evidenceTrace('frame', <String, Object?>{
        'batch': currentBatch,
        'phase_at_delivery': evidencePhase,
        'build_us': frame.buildDuration.inMicroseconds,
        'raster_us': frame.rasterDuration.inMicroseconds,
        'total_us': frame.totalSpan.inMicroseconds,
        'vsync_start_us': frame.timestampInMicroseconds(FramePhase.vsyncStart),
        'build_start_us': frame.timestampInMicroseconds(FramePhase.buildStart),
        'raster_finish_us': frame.timestampInMicroseconds(
          FramePhase.rasterFinish,
        ),
      });
    }
  });
}
