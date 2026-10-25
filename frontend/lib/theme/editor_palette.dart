import 'package:flutter/material.dart';

/// Readable colors for the Python editor in either editor mode.
class EditorPalette {
  const EditorPalette({
    required this.background,
    required this.foreground,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.symbol,
    required this.lineNumber,
    required this.selection,
    this.thickenStrokes = false,
  });

  /// Courier New's thin strokes look grey on a light background; a
  /// half-pixel shadow in the same color makes them read as solid text.
  final bool thickenStrokes;

  TextStyle _style(Color color,
          {FontStyle? fontStyle, FontWeight? fontWeight}) =>
      TextStyle(
        color: color,
        fontStyle: fontStyle,
        fontWeight: fontWeight,
        shadows: thickenStrokes
            ? [Shadow(color: color, offset: const Offset(0.5, 0))]
            : null,
      );

  final Color background;
  final Color foreground;
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;
  final Color symbol;
  final Color lineNumber;
  final Color selection;

  static const dark = EditorPalette(
    background: Color(0xFF20252B),
    foreground: Color(0xFFE8EEF4),
    comment: Color(0xFFAEBCC8),
    keyword: Color(0xFFFFBE80),
    string: Color(0xFFA6E3A1),
    number: Color(0xFF8FD4FF),
    symbol: Color(0xFFD9BAFF),
    lineNumber: Color(0xFFAAB8C5),
    selection: Color(0xFF425A70),
  );

  static const light = EditorPalette(
    background: Color(0xFFF8FAFC),
    foreground: Color(0xFF1D2730),
    comment: Color(0xFF445566),
    keyword: Color(0xFF6C3B8F),
    string: Color(0xFF17663F),
    number: Color(0xFF126083),
    symbol: Color(0xFF734B97),
    lineNumber: Color(0xFF4C5E70),
    selection: Color(0xFFC7DDF0),
    thickenStrokes: true,
  );

  Map<String, TextStyle> get styles => {
        'root': _style(foreground).copyWith(backgroundColor: background),
        for (final token in ['comment', 'quote', 'meta', 'deletion'])
          token: _style(comment, fontStyle: FontStyle.italic),
        for (final token in ['keyword', 'selector-tag', 'section'])
          token: _style(keyword, fontWeight: FontWeight.w600),
        for (final token in ['string', 'regexp', 'link', 'addition', 'doctag'])
          token: _style(string),
        for (final token in [
          'number',
          'literal',
          'variable',
          'template-variable'
        ])
          token: _style(number),
        for (final token in [
          'title',
          'type',
          'built_in',
          'builtin-name',
          'symbol',
          'selector-id',
          'selector-attr',
          'selector-pseudo',
          'template-tag',
          'code',
          'selector-class',
        ])
          token: _style(symbol),
        for (final token in ['attribute', 'name', 'params', 'subst', 'bullet'])
          token: _style(foreground),
        'emphasis': _style(foreground, fontStyle: FontStyle.italic),
        'strong': _style(foreground, fontWeight: FontWeight.bold),
      };
}
