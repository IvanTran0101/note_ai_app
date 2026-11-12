/// Picks one avatar image and converts it into the single uploadable payload
/// the profile boundary accepts.
///
/// The adapter is deliberately narrow: one PNG/JPEG file, at most
/// [ProfileAvatarRules.maxBytes] on disk, at most [maxAvatarDimension] on each
/// edge, and always returned as a freshly encoded PNG. Re-encoding through the
/// Flutter SDK is what strips the original file's metadata (EXIF, GPS, text
/// chunks) before anything is staged, and it is why the caller always uploads
/// [ProfileAvatarRules.pngMime].
///
/// Bounds are checked in cheapest-first order — byte length, then media-type
/// header, then the declared dimensions of the encoded header — so an oversized
/// or unsupported pick never allocates a decoded frame. A pick that cannot be
/// turned into a payload within the byte budget fails with
/// [ProfileFailureCode.invalid]; a cancelled pick is `null` and makes no request.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/services.dart' show PlatformException;

import '../../domain/users/profile_avatar_gateway.dart';
import '../../domain/users/profile_failure.dart';

/// Longest accepted avatar edge, in pixels.
const int maxAvatarDimension = 2048;

const ProfileFailure _invalid = ProfileFailure(ProfileFailureCode.invalid);
const ProfileFailure _unavailable = ProfileFailure(
  ProfileFailureCode.unavailable,
);

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

/// Smallest edge the downscale-and-re-encode loop will try.
const int _minAvatarDimension = 64;

/// How many times one pick may be re-encoded while fitting the byte budget.
const int _maxEncodeAttempts = 5;

/// Opens the platform file chooser and returns uploadable avatar bytes.
///
/// Uses the already-installed `file_selector` adapter on every platform; the
/// camera is intentionally out of scope for v1.
final class ProfileAvatarPicker {
  /// Creates the picker, optionally over a replacement file chooser.
  ProfileAvatarPicker({Future<files.XFile?> Function()? selectFile})
    : _selectFile = selectFile ?? _openAvatarFile;

  final Future<files.XFile?> Function() _selectFile;

  /// Returns the prepared PNG bytes, or `null` when the user cancelled.
  ///
  /// Throws a [ProfileFailure] when the pick cannot be uploaded: `invalid` for
  /// an unsupported, corrupt, or oversized image, `unavailable` when the
  /// platform chooser itself failed.
  Future<Uint8List?> pick() async {
    final files.XFile? file;
    try {
      file = await _selectFile();
    } on PlatformException {
      throw _unavailable;
    }
    if (file == null) {
      // Cancelling is not an error and must not reach the profile API.
      return null;
    }
    return prepareProfileAvatarBytes(await _readBounded(file));
  }
}

Future<files.XFile?> _openAvatarFile() {
  return files.openFile(
    acceptedTypeGroups: <files.XTypeGroup>[
      files.XTypeGroup(
        label: 'Avatar',
        extensions: <String>['png', 'jpg', 'jpeg'],
        mimeTypes: <String>[
          ProfileAvatarRules.pngMime,
          ProfileAvatarRules.jpegMime,
        ],
      ),
    ],
  );
}

/// Reads at most [ProfileAvatarRules.maxBytes] from [file], rejecting earlier
/// when the declared length is already too large.
///
/// The requested slice is bounded on purpose: on Web `XFile.openRead` turns the
/// requested range into one ArrayBuffer, so an unbounded read of a large pick
/// would allocate it whole before any validation could run.
Future<Uint8List> _readBounded(files.XFile file) async {
  final int length = await file.length();
  if (length <= 0 || length > ProfileAvatarRules.maxBytes) {
    throw _invalid;
  }
  final BytesBuilder builder = BytesBuilder(copy: true);
  await for (final Uint8List chunk in file.openRead(0, length)) {
    builder.add(chunk);
    if (builder.length > ProfileAvatarRules.maxBytes) {
      throw _invalid;
    }
  }
  final Uint8List bytes = builder.takeBytes();
  if (bytes.isEmpty || bytes.length > ProfileAvatarRules.maxBytes) {
    throw _invalid;
  }
  return bytes;
}

/// Validates one selected image and returns it as a metadata-free PNG.
///
/// Exposed separately from the chooser so the rules are verifiable without a
/// platform file dialog.
Future<Uint8List> prepareProfileAvatarBytes(Uint8List raw) async {
  if (raw.isEmpty || raw.length > ProfileAvatarRules.maxBytes) {
    throw _invalid;
  }
  if (!_hasPngOrJpegHeader(raw)) {
    // GIF/SVG/other containers are rejected here, even when a codec could
    // decode them, before any frame is allocated.
    throw _invalid;
  }

  final (width, height) = _headerDimensions(raw);
  if (width <= 0 ||
      height <= 0 ||
      width > maxAvatarDimension ||
      height > maxAvatarDimension) {
    throw _invalid;
  }
  int targetWidth = width;
  int targetHeight = height;
  for (int attempt = 0; attempt < _maxEncodeAttempts; attempt++) {
    final encoded = await _encodePng(raw, targetWidth);
    if (encoded.length <= ProfileAvatarRules.maxBytes) return encoded;
    targetWidth = (targetWidth / 2).ceil();
    targetHeight = (targetHeight / 2).ceil();
    if (targetWidth < _minAvatarDimension || targetHeight < _minAvatarDimension) {
      break;
    }
  }
  throw _invalid;
}

// ImageDescriptor dimensions are unavailable on Web; inspect the encoded header before decoding.
(int, int) _headerDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes[0] == 0x89) {
    if (bytes.length < 33 ||
        data.getUint32(8) != 13 ||
        String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
      throw _invalid;
    }
    return (data.getUint32(16), data.getUint32(20));
  }
  if (bytes.length < 4 || bytes[bytes.length - 2] != 0xff || bytes.last != 0xd9) {
    throw _invalid;
  }
  int offset = 2;
  (int, int)? size;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xff) throw _invalid;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) throw _invalid;
    final marker = bytes[offset++];
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) throw _invalid;
    final length = data.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) throw _invalid;
    if (marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc) {
      if (length < 8 || size != null) throw _invalid;
      size = (data.getUint16(offset + 5), data.getUint16(offset + 3));
    }
    if (marker == 0xda) return size ?? (throw _invalid);
    offset += length;
  }
  throw _invalid;
}

/// Decodes the image at the requested width and re-encodes it as PNG.
///
/// Only the width is targeted: the codec keeps the original aspect ratio, and
/// because the source is never upscaled the height stays inside the bound too.
Future<Uint8List> _encodePng(Uint8List raw, int targetWidth) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(
      raw,
      targetWidth: targetWidth,
      allowUpscaling: false,
    );
  } on Object {
    throw _invalid;
  }
  try {
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } on Object {
      throw _invalid;
    }
    try {
      if (frame.image.width > maxAvatarDimension ||
          frame.image.height > maxAvatarDimension) {
        throw _invalid;
      }
      final ByteData? png = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (png == null) {
        throw _invalid;
      }
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } on Object {
      throw _invalid;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

bool _hasPngOrJpegHeader(Uint8List bytes) {
  if (bytes.length >= _pngSignature.length) {
    bool isPng = true;
    for (int index = 0; index < _pngSignature.length; index++) {
      if (bytes[index] != _pngSignature[index]) {
        isPng = false;
        break;
      }
    }
    if (isPng) {
      return true;
    }
  }
  return bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
}
