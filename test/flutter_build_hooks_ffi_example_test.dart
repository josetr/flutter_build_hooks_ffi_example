import 'package:test/test.dart';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart';

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
}
