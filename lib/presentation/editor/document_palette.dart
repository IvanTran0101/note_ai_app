import 'package:flutter/material.dart';

import '../../domain/notes/note_document.dart';

/// Semantic colors are persisted; actual theme colors remain Presentation.
abstract final class DocumentPalette {
  static const _light = [
    0xff62615d,
    0xff794933,
    0xff8f4c05,
    0xff7a5b13,
    0xff296145,
    0xff245f83,
    0xff6f468e,
    0xff8d406c,
    0xff9b3933,
  ];
  static const _dark = [
    0xffb6b3af,
    0xffd6b096,
    0xffefb17d,
    0xffe5c886,
    0xff97cdb0,
    0xff99c9e5,
    0xffccafe2,
    0xffe7accb,
    0xfff0aca5,
  ];
  static Color text(DocumentColor color, Brightness brightness) =>
      Color((brightness == Brightness.dark ? _dark : _light)[color.index]);
  static Color highlight(DocumentColor color, Brightness brightness) => text(
    color,
    brightness,
  ).withValues(alpha: .14);
}
