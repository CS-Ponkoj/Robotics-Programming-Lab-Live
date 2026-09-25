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
  });

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
  );

  Map<String, TextStyle> get styles => {
        'root': TextStyle(color: foreground, backgroundColor: background),
        for (final token in ['comment', 'quote', 'meta', 'deletion'])
          token: TextStyle(color: comment, fontStyle: FontStyle.italic),
        for (final token in ['keyword', 'selector-tag', 'section'])
          token: TextStyle(color: keyword, fontWeight: FontWeight.w600),
        for (final token in ['string', 'regexp', 'link', 'addition', 'doctag'])
          token: TextStyle(color: string),
        for (final token in [
          'number',
          'literal',
          'variable',
          'template-variable'
        ])
          token: TextStyle(color: number),
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
          token: TextStyle(color: symbol),
        for (final token in ['attribute', 'name', 'params', 'subst', 'bullet'])
          token: TextStyle(color: foreground),
        'emphasis': TextStyle(color: foreground, fontStyle: FontStyle.italic),
        'strong': TextStyle(color: foreground, fontWeight: FontWeight.bold),
      };
}
