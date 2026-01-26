import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart';

({int row, int colBytes}) _pointAtUtf16(String text, int utf16Index) {
  utf16Index = utf16Index.clamp(0, text.length);
  var row = 0;
  var lineStart = 0;
  for (var i = 0; i < utf16Index; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      row++;
      lineStart = i + 1;
    }
  }
  final colBytes = utf8.encode(text.substring(lineStart, utf16Index)).length;
  return (row: row, colBytes: colBytes);
}

({int startByte, int row, int colBytes}) _byteAndPointAtUtf16(
  String text,
  int utf16Index,
) {
  final startByte = utf8.encode(text.substring(0, utf16Index)).length;
  final p = _pointAtUtf16(text, utf16Index);
  return (startByte: startByte, row: p.row, colBytes: p.colBytes);
}

void _applyInsertEdit(
  TreeSitterDocument doc, {
  required String oldText,
  required String newText,
  required int insertAtUtf16,
  required String insertedText,
}) {
  final start = _byteAndPointAtUtf16(oldText, insertAtUtf16);
  final oldEnd = start;

  final insertEndUtf16 = insertAtUtf16 + insertedText.length;
  final insertEnd = _byteAndPointAtUtf16(newText, insertEndUtf16);

  doc.edit(
    startByte: start.startByte,
    oldEndByte: start.startByte,
    newEndByte: insertEnd.startByte,
    startRow: start.row,
    startCol: start.colBytes,
    oldEndRow: oldEnd.row,
    oldEndCol: oldEnd.colBytes,
    newEndRow: insertEnd.row,
    newEndCol: insertEnd.colBytes,
  );
}

({int start, int oldEnd, int newEnd}) _diffUtf16(String oldText, String newText) {
  if (oldText == newText) return (start: 0, oldEnd: 0, newEnd: 0);

  var start = 0;
  final minLen = oldText.length < newText.length ? oldText.length : newText.length;
  while (start < minLen && oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }

  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }

  return (start: start, oldEnd: oldEnd, newEnd: newEnd);
}

void _applyDiffEdit(TreeSitterDocument doc, {required String oldText, required String newText}) {
  final d = _diffUtf16(oldText, newText);

  final start = _byteAndPointAtUtf16(oldText, d.start);
  final oldEnd = _byteAndPointAtUtf16(oldText, d.oldEnd);
  final newEnd = _byteAndPointAtUtf16(newText, d.newEnd);

  doc.edit(
    startByte: start.startByte,
    oldEndByte: oldEnd.startByte,
    newEndByte: newEnd.startByte,
    startRow: start.row,
    startCol: start.colBytes,
    oldEndRow: oldEnd.row,
    oldEndCol: oldEnd.colBytes,
    newEndRow: newEnd.row,
    newEndCol: newEnd.colBytes,
  );
}

void main() {
  test('invoke native function', () {
    expect(sum(24, 18), 42);
  });

  test('invoke async native callback', () async {
    expect(await sumAsync(24, 18), 42);
  });

  test('tree-sitter parses C', () {
    final tree = parseSExpression(
      'int add(int a, int b) { return a + b; }',
      language: TreeSitterLanguage.c,
    );
    expect(tree, isNotEmpty);
    expect(tree, contains('translation_unit'));
  });

  test('tree-sitter parses JavaScript', () {
    final tree = parseSExpression(
      'function add(a, b) { return a + b; }',
      language: TreeSitterLanguage.javascript,
    );
    expect(tree, isNotEmpty);
    expect(tree, contains('program'));
  });

  test('tree-sitter incremental doc matches full parse (js insert)', () {
    const query = r'(identifier) @variable';
    const src1 = 'function main() { return 1 + 2; }\nmain();\n';
    const insert = 'async ';
    final insertAt = src1.indexOf('function ') + 'function '.length;
    final src2 = src1.replaceRange(insertAt, insertAt, insert);

    final doc = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(doc.dispose);
    expect(doc.reparse(src1), isTrue);
    final before = doc.queryCaptures(query);
    expect(before, isNotEmpty);

    _applyInsertEdit(
      doc,
      oldText: src1,
      newText: src2,
      insertAtUtf16: insertAt,
      insertedText: insert,
    );
    expect(doc.reparse(src2), isTrue);
    final afterIncremental = doc.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    final fresh = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(fresh.dispose);
    expect(fresh.reparse(src2), isTrue);
    final afterFresh = fresh.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    expect(afterIncremental, afterFresh);
  });

  test('tree-sitter incremental doc matches full parse (js newline insert)', () {
    const query = r'(identifier) @variable';
    const src1 = 'function main() { return 1 + 2; }\nmain();\n';
    const insert = '\n// hi\n';
    final insertAt = src1.indexOf('{') + 1;
    final src2 = src1.replaceRange(insertAt, insertAt, insert);

    final doc = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(doc.dispose);
    expect(doc.reparse(src1), isTrue);

    _applyInsertEdit(
      doc,
      oldText: src1,
      newText: src2,
      insertAtUtf16: insertAt,
      insertedText: insert,
    );
    expect(doc.reparse(src2), isTrue);
    final afterIncremental = doc.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    final fresh = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(fresh.dispose);
    expect(fresh.reparse(src2), isTrue);
    final afterFresh = fresh.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    expect(afterIncremental, afterFresh);
  });

  test('tree-sitter doc supports multiple edits before reparse', () {
    const query = r'(identifier) @variable';
    const src0 = 'function main() { return 1 + 2; }\nmain();\n';

    final src1 = src0.replaceFirst('function ', 'function async ');
    final src2 = src1.replaceFirst('{', '{\n  // hi');
    final src3 = src2.replaceFirst('main();', 'main();\nmain();');

    final doc = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(doc.dispose);
    expect(doc.reparse(src0), isTrue);

    // Apply edits without reparsing between them.
    _applyDiffEdit(doc, oldText: src0, newText: src1);
    _applyDiffEdit(doc, oldText: src1, newText: src2);
    _applyDiffEdit(doc, oldText: src2, newText: src3);

    expect(doc.reparse(src3), isTrue);
    final afterIncremental = doc.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    final fresh = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(fresh.dispose);
    expect(fresh.reparse(src3), isTrue);
    final afterFresh = fresh.queryCaptures(query)
        .map((c) => (c.startByte, c.endByte, c.name))
        .toList();

    expect(afterIncremental, afterFresh);
  });

  test('tree-sitter incremental doc fuzz (js identifiers)', () {
    const query = r'(identifier) @variable';
    final rnd = Random(1);

    String text = 'function main() { return 1 + 2; }\nmain();\n';
    final doc = TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
    addTearDown(doc.dispose);
    expect(doc.reparse(text), isTrue);

    for (var step = 0; step < 60; step++) {
      final oldText = text;
      text = _mutateText(oldText, rnd);

      _applyDiffEdit(doc, oldText: oldText, newText: text);

      // Reparse in batches to simulate UI scheduling/coalescing.
      if (step % 5 == 4) {
        expect(doc.reparse(text), isTrue);

        final incremental = doc.queryCaptures(query)
            .map((c) => (c.startByte, c.endByte, c.name))
            .toList();

        final fresh =
            TreeSitterDocument.create(language: TreeSitterLanguage.javascript);
        addTearDown(fresh.dispose);
        expect(fresh.reparse(text), isTrue);
        final baseline = fresh
            .queryCaptures(query)
            .map((c) => (c.startByte, c.endByte, c.name))
            .toList();

        expect(incremental, baseline);
      }
    }
  });
}

String _mutateText(String text, Random rnd) {
  // Keep it relatively small to keep tests fast.
  if (text.length > 600) {
    text = text.substring(0, 600);
  }

  final pos = rnd.nextInt(text.length + 1);
  final op = rnd.nextInt(3);

  String randChunk() {
    const alphabet = ' abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_();{}=+/-\n';
    final len = 1 + rnd.nextInt(4);
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(alphabet[rnd.nextInt(alphabet.length)]);
    }
    return sb.toString();
  }

  switch (op) {
    case 0: // insert
      final chunk = randChunk();
      return text.replaceRange(pos, pos, chunk);
    case 1: // delete
      if (text.isEmpty) return text;
      final end = (pos + 1 + rnd.nextInt(6)).clamp(0, text.length);
      final start = pos.clamp(0, text.length);
      if (end <= start) return text;
      return text.replaceRange(start, end, '');
    default: // replace
      if (text.isEmpty) return randChunk();
      final end = (pos + rnd.nextInt(6)).clamp(0, text.length);
      final start = pos.clamp(0, text.length);
      if (end <= start) return text;
      return text.replaceRange(start, end, randChunk());
  }
}
