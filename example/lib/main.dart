import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart'
    as flutter_build_hooks_ffi_example;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late int sumResult;
  late Future<int> sumAsyncResult;

  final TextEditingController _cController = TextEditingController(
    text:
        'int add(int a, int b) { return a + b; }\nint main() { return add(1, 2); }',
  );
  final TextEditingController _jsController = TextEditingController(
    text: 'function add(a, b) { return a + b; }\nadd(1, 2);',
  );

  Future<String>? _cTree;
  Future<String>? _jsTree;
  Future<List<flutter_build_hooks_ffi_example.TreeSitterToken>>? _cTokens;
  Future<List<flutter_build_hooks_ffi_example.TreeSitterToken>>? _jsTokens;

  @override
  void initState() {
    super.initState();
    sumResult = flutter_build_hooks_ffi_example.sum(1, 2);
    sumAsyncResult = flutter_build_hooks_ffi_example.sumAsync(3, 4);
  }

  @override
  void dispose() {
    _cController.dispose();
    _jsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 18);
    const spacerSmall = SizedBox(height: 12);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('tree-sitter + Dart build hooks')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text(
                  'This app uses Dart build hooks to (1) clone tree-sitter + two grammars and '
                  '(2) build a native library, then calls it via Dart FFI.',
                  style: textStyle,
                  textAlign: .center,
                ),
                spacerSmall,
                Text(
                  'sum(1, 2) = $sumResult',
                  style: textStyle,
                  textAlign: .center,
                ),
                spacerSmall,
                FutureBuilder<int>(
                  future: sumAsyncResult,
                  builder: (BuildContext context, AsyncSnapshot<int> value) {
                    final displayValue = (value.hasData)
                        ? value.data
                        : 'loading';
                    return Text(
                      'await sumAsync(3, 4) = $displayValue',
                      style: textStyle,
                      textAlign: .center,
                    );
                  },
                ),
                const Divider(height: 32),
                DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'C'),
                          Tab(text: 'JavaScript'),
                        ],
                      ),
                      SizedBox(
                        height: 520,
                        child: TabBarView(
                          children: [
                            _TreeSitterPane(
                              controller: _cController,
                              onParse: () => setState(() {
                                _cTree = flutter_build_hooks_ffi_example
                                    .parseSExpressionAsync(
                                      _cController.text,
                                      language: flutter_build_hooks_ffi_example
                                          .TreeSitterLanguage
                                          .c,
                                    );
                                _cTokens = flutter_build_hooks_ffi_example
                                    .parseTokensAsync(
                                      _cController.text,
                                      language: flutter_build_hooks_ffi_example
                                          .TreeSitterLanguage
                                          .c,
                                    );
                              }),
                              result: _cTree,
                              tokens: _cTokens,
                              language: flutter_build_hooks_ffi_example
                                  .TreeSitterLanguage
                                  .c,
                            ),
                            _TreeSitterPane(
                              controller: _jsController,
                              onParse: () => setState(() {
                                _jsTree = flutter_build_hooks_ffi_example
                                    .parseSExpressionAsync(
                                      _jsController.text,
                                      language: flutter_build_hooks_ffi_example
                                          .TreeSitterLanguage
                                          .javascript,
                                    );
                                _jsTokens = flutter_build_hooks_ffi_example
                                    .parseTokensAsync(
                                      _jsController.text,
                                      language: flutter_build_hooks_ffi_example
                                          .TreeSitterLanguage
                                          .javascript,
                                    );
                              }),
                              result: _jsTree,
                              tokens: _jsTokens,
                              language: flutter_build_hooks_ffi_example
                                  .TreeSitterLanguage
                                  .javascript,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeSitterPane extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onParse;
  final Future<String>? result;
  final Future<List<flutter_build_hooks_ffi_example.TreeSitterToken>>? tokens;
  final flutter_build_hooks_ffi_example.TreeSitterLanguage language;

  const _TreeSitterPane({
    required this.controller,
    required this.onParse,
    required this.result,
    required this.tokens,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    const baseCodeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.35,
      color: Color(0xFFD4D4D4),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Source',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: onParse, child: const Text('Parse')),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF1E1E1E),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Expanded(
                      child:
                          FutureBuilder<
                            List<
                              flutter_build_hooks_ffi_example.TreeSitterToken
                            >
                          >(
                            future: tokens,
                            builder: (context, snapshot) {
                              if (tokens == null) {
                                return const Center(
                                  child: Text(
                                    'Tap Parse to show syntax highlighting.',
                                    style: TextStyle(color: Color(0xFFD4D4D4)),
                                  ),
                                );
                              }
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Error: ${snapshot.error}',
                                    style: const TextStyle(
                                      color: Color(0xFFD4D4D4),
                                    ),
                                  ),
                                );
                              }

                              final bytes = Uint8List.fromList(
                                utf8.encode(controller.text),
                              );
                              final tokenList = snapshot.data ?? const [];

                              return SingleChildScrollView(
                                child: SelectionArea(
                                  child: SelectableText.rich(
                                    _buildHighlightedSpan(
                                      bytes,
                                      tokenList,
                                      language: language,
                                      baseStyle: baseCodeStyle,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      collapsedIconColor: const Color(0xFFD4D4D4),
                      iconColor: const Color(0xFFD4D4D4),
                      title: const Text(
                        'Tree (s-expression)',
                        style: TextStyle(color: Color(0xFFD4D4D4)),
                      ),
                      children: [
                        SizedBox(
                          height: 180,
                          child: FutureBuilder<String>(
                            future: result,
                            builder: (context, snapshot) {
                              if (result == null) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Tap Parse to show the syntax tree.',
                                    style: TextStyle(color: Color(0xFFD4D4D4)),
                                  ),
                                );
                              }
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'Error: ${snapshot.error}',
                                    style: const TextStyle(
                                      color: Color(0xFFD4D4D4),
                                    ),
                                  ),
                                );
                              }
                              return SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(
                                    snapshot.data ?? '',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Color(0xFFD4D4D4),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _buildHighlightedSpan(
    Uint8List utf8Bytes,
    List<flutter_build_hooks_ffi_example.TreeSitterToken> tokens, {
    required flutter_build_hooks_ffi_example.TreeSitterLanguage language,
    required TextStyle baseStyle,
  }) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final token in tokens) {
      final start = token.startByte.clamp(0, utf8Bytes.length);
      final end = token.endByte.clamp(0, utf8Bytes.length);
      if (end <= start) continue;

      if (start > cursor) {
        spans.add(
          TextSpan(
            text: utf8.decode(utf8Bytes.sublist(cursor, start)),
            style: baseStyle,
          ),
        );
      }

      spans.add(
        TextSpan(
          text: utf8.decode(utf8Bytes.sublist(start, end)),
          style: baseStyle.copyWith(
            color: _tokenColor(token, language: language),
          ),
        ),
      );

      cursor = end;
    }

    if (cursor < utf8Bytes.length) {
      spans.add(
        TextSpan(
          text: utf8.decode(utf8Bytes.sublist(cursor)),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  Color _tokenColor(
    flutter_build_hooks_ffi_example.TreeSitterToken token, {
    required flutter_build_hooks_ffi_example.TreeSitterLanguage language,
  }) {
    final type = token.type;

    if (type.contains('comment')) {
      return const Color(0xFF6A9955);
    }
    if (type.contains('string') || type.contains('char')) {
      return const Color(0xFFCE9178);
    }
    if (type.contains('number')) {
      return const Color(0xFFB5CEA8);
    }
    if (type.contains('type') || type == 'primitive_type') {
      return const Color(0xFF4EC9B0);
    }

    final keywordColor = const Color(0xFF569CD6);
    if (!token.named) {
      if (_isKeyword(type, language: language)) {
        return keywordColor;
      }
      return const Color(0xFFD4D4D4);
    }

    if (type.endsWith('identifier') || type == 'identifier') {
      return const Color(0xFF9CDCFE);
    }

    return const Color(0xFFD4D4D4);
  }

  bool _isKeyword(
    String type, {
    required flutter_build_hooks_ffi_example.TreeSitterLanguage language,
  }) {
    switch (language) {
      case flutter_build_hooks_ffi_example.TreeSitterLanguage.c:
        return const {
          'return',
          'if',
          'else',
          'for',
          'while',
          'do',
          'switch',
          'case',
          'break',
          'continue',
          'typedef',
          'struct',
          'enum',
          'static',
          'const',
          'void',
          'int',
          'char',
          'float',
          'double',
          'long',
          'short',
          'signed',
          'unsigned',
          'sizeof',
        }.contains(type);
      case flutter_build_hooks_ffi_example.TreeSitterLanguage.javascript:
        return const {
          'function',
          'return',
          'if',
          'else',
          'for',
          'while',
          'do',
          'switch',
          'case',
          'break',
          'continue',
          'const',
          'let',
          'var',
          'class',
          'new',
          'this',
          'import',
          'export',
          'from',
        }.contains(type);
    }
  }
}
