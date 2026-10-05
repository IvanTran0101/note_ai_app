import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../../application/attachments/attachment_media.dart';

final class AttachmentMediaSurface extends StatefulWidget {
  const AttachmentMediaSurface({
    super.key,
    required this.handle,
    required this.mime,
    required this.size,
    required this.read,
  });
  final AttachmentMediaHandle handle;
  final String mime;
  final int size;
  final Stream<List<int>> Function(int, int) read;
  @override
  State<AttachmentMediaSurface> createState() => _AttachmentMediaSurfaceState();
}

final class _AttachmentMediaSurfaceState extends State<AttachmentMediaSurface> {
  VideoPlayerController? _video;
  PdfDocumentRefCustom? _pdf;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.mime == 'application/pdf') {
      _pdf = PdfDocumentRefCustom(
        fileSize: widget.size,
        sourceName: widget.handle.uri.toString(),
        maxSizeToCacheOnMemory: 0,
        useProgressiveLoading: true,
        read: _read,
      );
    } else {
      final video = VideoPlayerController.networkUrl(widget.handle.uri!);
      _video = video;
      video
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object _) {
            if (mounted) {
              setState(
                () => _error = 'Video preview unavailable. Reopen after unlocking or reconnecting.',
              );
            }
          });
    }
  }

  Future<int> _read(Uint8List buffer, int position, int size) async {
    if (!mounted ||
        position < 0 ||
        size < 0 ||
        position + size > widget.size ||
        size > buffer.length) {
      throw StateError('Invalid PDF range');
    }
    var written = 0;
    while (written < size) {
      final end = min(position + size, position + written + 256 * 1024);
      await for (final chunk in widget.read(position + written, end)) {
        try {
          if (!mounted || written + chunk.length > size) {
            throw StateError('PDF closed');
          }
          buffer.setRange(written, written + chunk.length, chunk);
          written += chunk.length;
        } finally {
          chunk.fillRange(0, chunk.length, 0);
        }
      }
      if (position + written != end) throw StateError('Incomplete PDF range');
    }
    return written;
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text(_error!);
    final pdf = _pdf;
    if (pdf != null) {
      return PdfViewer(
        pdf,
        params: PdfViewerParams(
          maxImageBytesCachedOnMemory: 16 * 1024 * 1024,
          forceEnableTextSemantics: true,
          linkHandlerParams: PdfLinkHandlerParams(onLinkTap: (_) {}),
          buildContextMenu: (_, _) => const SizedBox.shrink(),
        ),
      );
    }
    final video = _video!;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: video,
      builder: (context, value, _) {
        if (value.hasError) {
          return const Text(
            'Video access unavailable. Reopen after unlocking or reconnecting.',
          );
        }
        if (!value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(video),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                  onPressed: () =>
                      value.isPlaying ? video.pause() : video.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    value: min(
                      value.position.inMilliseconds.toDouble(),
                      value.duration.inMilliseconds.toDouble(),
                    ),
                    max: max(1, value.duration.inMilliseconds.toDouble()),
                    onChanged: (p) =>
                        video.seekTo(Duration(milliseconds: p.round())),
                  ),
                ),
                Text(
                  '${value.position.inSeconds}s / ${value.duration.inSeconds}s',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
