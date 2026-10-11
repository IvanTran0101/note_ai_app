import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/infrastructure/users/profile_avatar_picker.dart';

/// Rules coverage for the avatar chooser: what is refused before any request or
/// frame allocation, that a cancelled pick is not an error, and that the bytes
/// handed to the profile boundary are always a metadata-free PNG inside the
/// size, dimension, and media-type bounds.
///
/// The chooser itself is injected, so no platform dialog runs here; the payload
/// rules are exercised through the same entry point the picker uses.

/// A 2x2 JPEG carrying an EXIF/Photoshop APP1 segment, so metadata stripping is
/// exercised on a real container rather than a synthetic header.
const String _jpegBase64 =
    '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKAC'
    'AAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZ'
    'jwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIB'
    'AwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNE'
    'RUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfI'
    'ycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIB'
    'AgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpD'
    'REVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXG'
    'x8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgK'
    'CgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ'
    'EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+X6KKK/Ez/UA/9k=';

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// A synthetic 1024x512 lossy photo (busy content, 137 KiB) used to exercise the
/// byte-bound re-encode path without embedding a large base64 literal.
const String _photoFixturePath =
    'test/presentation/profile/fixtures/avatar_photo.jpg';

Matcher _invalid() => throwsA(
  isA<ProfileFailure>().having(
    (ProfileFailure failure) => failure.code,
    'code',
    ProfileFailureCode.invalid,
  ),
);

/// Counts reads so "rejected before reading" is observable, not assumed.
final class _CountingXFile extends XFile {
  _CountingXFile(super.bytes)
    : super.fromData(name: 'avatar.png', mimeType: 'image/png');

  int openReadCalls = 0;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    openReadCalls++;
    return super.openRead(start, end);
  }
}

void main() {
  // Image codecs need the engine; plain `test` keeps real async so decode and
  // encode callbacks complete without a fake clock.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileAvatarPicker.pick', () {
    test('returns null on cancel and never touches the payload', () async {
      var selections = 0;
      final ProfileAvatarPicker picker = ProfileAvatarPicker(
        selectFile: () async {
          selections++;
          return null;
        },
      );

      expect(await picker.pick(), isNull);
      expect(selections, 1);
    });

    test('returns re-encoded PNG bytes for a selected image', () async {
      final Uint8List source = await _rawPng(8, 4);
      final ProfileAvatarPicker picker = ProfileAvatarPicker(
        selectFile: () async => XFile.fromData(
          source,
          name: 'avatar.png',
          mimeType: ProfileAvatarRules.pngMime,
        ),
      );

      final Uint8List? picked = await picker.pick();

      expect(picked, isNotNull);
      expect(_hasPngSignature(picked!), isTrue);
      expect(picked.length, lessThanOrEqualTo(ProfileAvatarRules.maxBytes));
      expect(await _dimensions(picked), (8, 4));
    });

    test('refuses an oversized pick from its length alone', () async {
      final _CountingXFile oversized = _CountingXFile(
        Uint8List(ProfileAvatarRules.maxBytes + 1),
      );
      final ProfileAvatarPicker picker = ProfileAvatarPicker(
        selectFile: () async => oversized,
      );

      await expectLater(picker.pick(), _invalid());
      expect(oversized.openReadCalls, 0);
    });
  });

  group('prepareProfileAvatarBytes rules', () {
    test('refuses GIF and SVG containers a codec could still decode', () async {
      final Uint8List gif = Uint8List.fromList(<int>[
        ...ascii.encode('GIF89a'),
        ...List<int>.filled(32, 0),
      ]);
      final Uint8List svg = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
      );

      await expectLater(prepareProfileAvatarBytes(gif), _invalid());
      await expectLater(prepareProfileAvatarBytes(svg), _invalid());
    });

    test('refuses an empty payload', () async {
      await expectLater(prepareProfileAvatarBytes(Uint8List(0)), _invalid());
    });

    test('refuses a payload past the byte bound before decoding it', () async {
      final Uint8List oversized = Uint8List(ProfileAvatarRules.maxBytes + 1)
        ..setRange(0, _pngSignature.length, _pngSignature);

      await expectLater(prepareProfileAvatarBytes(oversized), _invalid());
    });

    test('refuses an image whose declared edges exceed the bound', () async {
      final Uint8List wide = await _rawPng(3000, 8);

      expect(await _dimensions(wide), (3000, 8));
      await expectLater(prepareProfileAvatarBytes(wide), _invalid());
    });

    test('accepts a JPEG pick and returns a PNG payload', () async {
      final Uint8List jpeg = base64Decode(_jpegBase64);

      final Uint8List prepared = await prepareProfileAvatarBytes(jpeg);

      expect(_hasPngSignature(prepared), isTrue);
      expect(prepared.length, lessThanOrEqualTo(ProfileAvatarRules.maxBytes));
      expect(await _dimensions(prepared), (2, 2));
    });

    test('strips the original metadata from the returned payload', () async {
      const String marker = 'NoteFlowAvatarMetadataMarker';
      final Uint8List source = _withTextChunk(await _rawPng(8, 8), marker);

      expect(ascii.decode(source, allowInvalid: true), contains(marker));
      expect(_chunkTypes(source), contains('tEXt'));

      final Uint8List prepared = await prepareProfileAvatarBytes(source);

      expect(
        ascii.decode(prepared, allowInvalid: true),
        isNot(contains(marker)),
      );
      expect(_chunkTypes(prepared), isNot(contains('tEXt')));
      expect(await _dimensions(prepared), (8, 8));
    });

    test('keeps a photo inside the byte bound without distorting it', () async {
      // A real lossy photo under the byte bound whose PNG re-encode is not: the
      // payload has to be re-encoded smaller to fit.
      final Uint8List photo = await XFile(_photoFixturePath).readAsBytes();
      expect(photo.length, lessThanOrEqualTo(ProfileAvatarRules.maxBytes));
      expect(await _dimensions(photo), (1024, 512));

      final Uint8List prepared = await prepareProfileAvatarBytes(photo);
      final (int width, int height) = await _dimensions(prepared);

      expect(prepared.length, lessThanOrEqualTo(ProfileAvatarRules.maxBytes));
      expect(width, lessThanOrEqualTo(maxAvatarDimension));
      expect(height, lessThanOrEqualTo(maxAvatarDimension));
      expect(width, height * 2);
    }, skip: kIsWeb);
  });
}

bool _hasPngSignature(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) {
    return false;
  }
  for (int index = 0; index < _pngSignature.length; index++) {
    if (bytes[index] != _pngSignature[index]) {
      return false;
    }
  }
  return true;
}

Future<(int, int)> _dimensions(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      return (frame.image.width, frame.image.height);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _rawPng(int width, int height) {
  return _encodePng(_solidRgba(width, height), width, height);
}

Uint8List _solidRgba(int width, int height) {
  final Uint8List rgba = Uint8List(width * height * 4);
  for (int index = 0; index < width * height; index++) {
    rgba[index * 4] = 200;
    rgba[index * 4 + 1] = 40;
    rgba[index * 4 + 2] = 40;
    rgba[index * 4 + 3] = 255;
  }
  return rgba;
}

Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    rgba,
  );
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  final ui.FrameInfo frame = await codec.getNextFrame();
  try {
    final ByteData? png = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// Inserts one `tEXt` chunk after `IHDR`, the way an editor writes a comment.
Uint8List _withTextChunk(Uint8List png, String text) {
  final Uint8List ihdrEnd = png.sublist(0, 33);
  return Uint8List.fromList(<int>[
    ...ihdrEnd,
    ..._textChunk('Comment', text),
    ...png.sublist(33),
  ]);
}

Uint8List _textChunk(String keyword, String text) {
  final List<int> type = ascii.encode('tEXt');
  final List<int> data = <int>[
    ...ascii.encode(keyword),
    0,
    ...ascii.encode(text),
  ];
  final BytesBuilder builder = BytesBuilder(copy: true)
    ..add(_be32(data.length))
    ..add(type)
    ..add(data)
    ..add(_be32(_crc32(<int>[...type, ...data])));
  return builder.takeBytes();
}

List<int> _be32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

int _readBe32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

List<String> _chunkTypes(Uint8List png) {
  final List<String> types = <String>[];
  int offset = _pngSignature.length;
  while (offset + 8 <= png.length) {
    final int length = _readBe32(png, offset);
    types.add(ascii.decode(png.sublist(offset + 4, offset + 8)));
    offset += 12 + length;
  }
  return types;
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
