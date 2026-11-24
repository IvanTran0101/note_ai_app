import 'dart:convert';
import 'dart:typed_data';

import '../../application/attachments/attachment_input.dart';

/// Bytes, not a renamed extension or a browser-supplied MIME, determine type.
abstract final class AttachmentByteValidation {
  static Future<void> validate(AttachmentInput input) async {
    final header = await _read(
      input,
      0,
      input.sizeBytes < 32 ? input.sizeBytes : 32,
    );
    bool starts(List<int> magic) =>
        header.length >= magic.length &&
        List.generate(
          magic.length,
          (i) => header[i] == magic[i],
        ).every((v) => v);
    final valid = switch (input.mimeType) {
      'image/jpeg' => starts([0xff, 0xd8, 0xff]),
      'image/png' => starts([137, 80, 78, 71, 13, 10, 26, 10]),
      'image/webp' =>
        header.length >= 16 &&
            ascii.decode(header.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(header.sublist(8, 12), allowInvalid: true) == 'WEBP',
      'application/pdf' => starts([37, 80, 68, 70, 45]),
      'text/plain' || 'text/csv' => await _validateText(input),
      'video/mp4' => await _Mp4Validation(input).validate(),
      _ => false,
    };
    if (!valid) {
      throw const FormatException(
        'Attachment bytes do not match the allowed format.',
      );
    }
  }

  static Future<bool> _validateText(AttachmentInput input) async {
    try {
      var bytes = 0;
      final counted = input.openRead().map((chunk) {
        bytes += chunk.length;
        if (bytes > input.sizeBytes || chunk.contains(0)) {
          throw const FormatException();
        }
        return chunk;
      });
      await for (final _ in counted.transform(const Utf8Decoder())) {}
      return bytes == input.sizeBytes;
    } on FormatException {
      return false;
    }
  }

  static Future<Uint8List> _read(
    AttachmentInput input,
    int start,
    int end,
  ) async {
    if (start < 0 ||
        end < start ||
        end > input.sizeBytes ||
        end - start > 1024 * 1024) {
      throw const FormatException('Invalid media structure.');
    }
    final builder = BytesBuilder(copy: true);
    await for (final chunk in input.openRead(start, end)) {
      if (builder.length + chunk.length > end - start) {
        throw const FormatException('Invalid media range.');
      }
      builder.add(chunk);
    }
    if (builder.length != end - start) {
      throw const FormatException('Truncated media.');
    }
    return builder.takeBytes();
  }
}

typedef _Box = ({String type, int body, int end});

/// Bounded ISO-BMFF traversal. MP4 labels alone do not prove H.264/AAC.
final class _Mp4Validation {
  _Mp4Validation(this.input);
  final AttachmentInput input;
  var remainingBoxes = 2048;
  Future<Uint8List> read(int start, int end) =>
      AttachmentByteValidation._read(input, start, end);
  int uint32(Uint8List value, int offset) =>
      ByteData.sublistView(value).getUint32(offset);
  String tag(Uint8List value, int offset) =>
      ascii.decode(value.sublist(offset, offset + 4), allowInvalid: true);

  Future<List<_Box>> boxes(int start, int end) async {
    final result = <_Box>[];
    while (start < end) {
      if (--remainingBoxes < 0 || end - start < 8) {
        throw const FormatException('Invalid MP4 structure.');
      }
      final header = await read(start, start + 8);
      var size = uint32(header, 0);
      var headerSize = 8;
      if (size == 1) {
        if (end - start < 16) throw const FormatException();
        final extended = await read(start + 8, start + 16);
        if (uint32(extended, 0) != 0) throw const FormatException();
        size = uint32(extended, 4);
        headerSize = 16;
      } else if (size == 0) {
        size = end - start;
      }
      if (size < headerSize || start + size > end) {
        throw const FormatException();
      }
      result.add((
        type: tag(header, 4),
        body: start + headerSize,
        end: start + size,
      ));
      start += size;
    }
    return result;
  }

  _Box one(List<_Box> values, String type) =>
      values.singleWhere((v) => v.type == type);
  Future<List<_Box>> children(_Box box) => boxes(box.body, box.end);

  Future<bool> validate() async {
    try {
      final root = await boxes(0, input.sizeBytes);
      final ftyp = one(root, 'ftyp');
      if (ftyp.end - ftyp.body < 8) return false;
      final movie = await children(one(root, 'moov'));
      var videoTracks = 0;
      for (final track in movie.where((b) => b.type == 'trak')) {
        final media = await children(one(await children(track), 'mdia'));
        final handler = one(media, 'hdlr');
        if (handler.end - handler.body < 12) return false;
        final handlerData = await read(handler.body, handler.body + 12);
        final kind = tag(handlerData, 8);
        if (kind != 'vide' && kind != 'soun') return false;
        final table = one(await children(one(media, 'minf')), 'stbl');
        final description = one(await children(table), 'stsd');
        if (description.end - description.body < 8) return false;
        final entriesHeader = await read(
          description.body,
          description.body + 8,
        );
        final entries = await boxes(description.body + 8, description.end);
        if (entries.isEmpty || entries.length != uint32(entriesHeader, 4)) {
          return false;
        }
        for (final entry in entries) {
          if (kind == 'vide') {
            if (entry.type != 'avc1' && entry.type != 'avc3') return false;
            if (entry.end - entry.body < 78) return false;
            final config = one(await boxes(entry.body + 78, entry.end), 'avcC');
            if (config.end - config.body < 7 ||
                (await read(config.body, config.body + 1)).single != 1) {
              return false;
            }
          } else {
            if (entry.type != 'mp4a' || entry.end - entry.body < 28) {
              return false;
            }
            final esds = one(await boxes(entry.body + 28, entry.end), 'esds');
            if (esds.end - esds.body > 1024) return false;
            if (!_aac(await read(esds.body, esds.end))) return false;
          }
        }
        if (kind == 'vide') videoTracks++;
      }
      return videoTracks > 0;
    } on Object {
      return false;
    }
  }

  bool _aac(Uint8List bytes) {
    // FullBox + ES_Descriptor + DecoderConfigDescriptor + DecoderSpecificInfo.
    var offset = 4;
    int descriptor(int expectedTag) {
      if (offset >= bytes.length || bytes[offset++] != expectedTag) {
        throw const FormatException();
      }
      var size = 0;
      for (var count = 0; count < 4; count++) {
        if (offset >= bytes.length) throw const FormatException();
        final b = bytes[offset++];
        size = (size << 7) | (b & 127);
        if (b & 128 == 0) {
          if (offset + size > bytes.length) throw const FormatException();
          return offset + size;
        }
      }
      throw const FormatException();
    }

    final esEnd = descriptor(3);
    if (offset + 3 > esEnd) return false;
    final flags = bytes[offset + 2];
    offset += 3;
    if (flags & 128 != 0) offset += 2;
    if (flags & 64 != 0) {
      if (offset >= esEnd) return false;
      offset += 1 + bytes[offset];
    }
    if (flags & 32 != 0) offset += 2;
    final configEnd = descriptor(4);
    if (configEnd > esEnd || offset + 13 > configEnd || bytes[offset] != 0x40) {
      return false;
    }
    offset += 13;
    final specificEnd = descriptor(5);
    if (specificEnd > configEnd || specificEnd - offset < 2) return false;
    final audioType = bytes[offset] >> 3;
    return audioType == 2 || audioType == 5 || audioType == 29;
  }
}
