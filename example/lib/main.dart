import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart'
    as ts;

void main() {
  runApp(const VsCodeLikeApp());
}

enum _FileLanguage { c, javascript, dart }

class _EditorFile {
  final String path;
  final _FileLanguage language;
  late final CodeLineEditingController controller;
  late final _TreeSitterHighlighter highlighter;

  _EditorFile({
    required this.path,
    required this.language,
    required String initialText,
  }) {
    highlighter = _TreeSitterHighlighter(language: language);
    controller = CodeLineEditingController(
      codeLines: initialText.codeLines,
      options: const CodeLineOptions(lineBreak: TextLineBreak.lf, indentSize: 2),
      spanBuilder: ({
        required BuildContext context,
        required int index,
        required CodeLine codeLine,
        required TextSpan textSpan,
        required TextStyle style,
      }) {
        return highlighter.buildLineSpan(
          lineIndex: index,
          lineText: codeLine.text,
          baseStyle: style,
          baseSpan: textSpan,
        );
      },
    );

    controller.addListener(() {
      highlighter.schedule(controller.text, onUpdated: controller.forceRepaint);
    });
    highlighter.schedule(controller.text, onUpdated: controller.forceRepaint);
  }

  void dispose() {
    controller.dispose();
    highlighter.dispose();
  }
}

class VsCodeLikeApp extends StatefulWidget {
  const VsCodeLikeApp({super.key});

  @override
  State<VsCodeLikeApp> createState() => _VsCodeLikeAppState();
}

class _VsCodeLikeAppState extends State<VsCodeLikeApp> {
  late final List<_EditorFile> _files;
  int _activeIndex = 2;

  @override
  void initState() {
    super.initState();
    _files = [
      _EditorFile(
        path: 'src/hello.c',
        language: _FileLanguage.c,
        initialText: _seedC,
      ),
      _EditorFile(
        path: 'src/app.js',
        language: _FileLanguage.javascript,
        initialText: _seedJs,
      ),
      _EditorFile(
        path: 'lib/main.dart',
        language: _FileLanguage.dart,
        initialText: _seedDart,
      ),
    ];
  }

  @override
  void dispose() {
    for (final f in _files) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF1E1E1E),
        primary: Color(0xFF007ACC),
      ),
      dividerColor: const Color(0xFF3C3C3C),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: const Color(0xFF2A2D2E),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Column(
          children: [
            const _TitleBar(),
            Expanded(
              child: Row(
                children: [
                  _Explorer(
                    files: _files,
                    activeIndex: _activeIndex,
                    onOpen: (i) => setState(() => _activeIndex = i),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _Tabs(
                          files: _files,
                          activeIndex: _activeIndex,
                          onSelect: (i) => setState(() => _activeIndex = i),
                        ),
                        Expanded(
                          child: _EditorSurface(file: _files[_activeIndex]),
                        ),
                        _StatusBar(file: _files[_activeIndex]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF3C3C3C)),
      child: SizedBox(
        height: 36,
        child: Row(
          children: const [
            SizedBox(width: 12),
            Icon(Icons.code, size: 16, color: Color(0xFFD4D4D4)),
            SizedBox(width: 8),
            Text(
              'Flutter VS Code (tree-sitter)',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFD4D4D4),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Explorer extends StatelessWidget {
  final List<_EditorFile> files;
  final int activeIndex;
  final ValueChanged<int> onOpen;

  const _Explorer({
    required this.files,
    required this.activeIndex,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF252526)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Text(
                'EXPLORER',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFCCCCCC),
                  letterSpacing: 0.9,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF3C3C3C)),
            Expanded(
              child: ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, i) {
                  final f = files[i];
                  final isActive = i == activeIndex;
                  return InkWell(
                    onTap: () => onOpen(i),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: isActive ? const Color(0xFF37373D) : null,
                      child: Row(
                        children: [
                          Icon(
                            _fileIcon(f.language),
                            size: 16,
                            color: const Color(0xFFD4D4D4),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f.path,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFFD4D4D4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(_FileLanguage language) {
    switch (language) {
      case _FileLanguage.c:
        return Icons.memory;
      case _FileLanguage.javascript:
        return Icons.data_object;
      case _FileLanguage.dart:
        return Icons.flutter_dash;
    }
  }
}

class _Tabs extends StatelessWidget {
  final List<_EditorFile> files;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const _Tabs({
    required this.files,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF2D2D2D)),
        child: Row(
          children: [
            for (var i = 0; i < files.length; i++)
              _Tab(
                label: files[i].path.split('/').last,
                active: i == activeIndex,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E1E1E) : null,
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? const Color(0xFF007ACC) : Colors.transparent,
            ),
            right: const BorderSide(color: Color(0xFF3C3C3C)),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: active
                ? const Color(0xFFFFFFFF)
                : const Color(0xFFCCCCCC),
          ),
        ),
      ),
    );
  }
}

class _EditorSurface extends StatelessWidget {
  final _EditorFile file;

  const _EditorSurface({required this.file});

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: ['Menlo', 'monospace'],
      fontSize: 13,
      height: 1.4,
      color: Color(0xFFD4D4D4),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E)),
      child: CodeEditor(
        controller: file.controller,
        style: CodeEditorStyle(
          fontFamily: baseStyle.fontFamily,
          fontFamilyFallback: baseStyle.fontFamilyFallback,
          fontSize: baseStyle.fontSize,
          fontHeight: baseStyle.height,
          textColor: baseStyle.color,
          backgroundColor: const Color(0xFF1E1E1E),
          selectionColor: const Color(0xFF264F78),
          cursorColor: const Color(0xFFFFFFFF),
          cursorLineColor: const Color(0xFF2A2D2E),
        ),
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          return Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Menlo', 'monospace'],
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF858585),
                ),
              ),
              const SizedBox(width: 8),
            ],
          );
        },
        padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
        maxLengthSingleLineRendering: 6000,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final _EditorFile file;
  const _StatusBar({required this.file});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF007ACC)),
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                file.path,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              ValueListenableBuilder<CodeLineEditingValue>(
                valueListenable: file.controller,
                builder: (context, value, _) {
                  final line = value.selection.extentIndex + 1;
                  final col = value.selection.extentOffset + 1;
                  return Text(
                    'Ln $line, Col $col',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  );
                },
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<_TreeSitterHighlightStats>(
                valueListenable: file.highlighter.stats,
                builder: (context, stats, _) {
                  final label = switch (stats.state) {
                    _TreeSitterHighlightState.idle => 'tree-sitter',
                    _TreeSitterHighlightState.parsing => 'tree-sitter: parsing…',
                    _TreeSitterHighlightState.disabled =>
                      'tree-sitter: disabled (${stats.reason})',
                    _TreeSitterHighlightState.error => 'tree-sitter: error',
                  };
                  return Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TreeSitterHighlightState { idle, parsing, disabled, error }

class _TreeSitterHighlightStats {
  final _TreeSitterHighlightState state;
  final String? reason;
  const _TreeSitterHighlightStats(this.state, {this.reason});
}

class _TreeSitterHighlighter {
  static const int _maxBytesForHighlight = 6 * 1024 * 1024;
  static const Duration _debounce = Duration(milliseconds: 180);

  final _FileLanguage language;
  final ValueNotifier<_TreeSitterHighlightStats> stats = ValueNotifier(
    const _TreeSitterHighlightStats(_TreeSitterHighlightState.idle),
  );

  Timer? _debounceTimer;
  int _revision = 0;
  bool _disposed = false;
  List<List<int>> _lineSpansTriples = const [];

  _TreeSitterHighlighter({required this.language});

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    stats.dispose();
  }

  void schedule(String text, {required VoidCallback onUpdated}) {
    if (_disposed) return;

    _revision++;
    final rev = _revision;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () async {
      if (_disposed || rev != _revision) return;

      if (text.length > _maxBytesForHighlight) {
        _lineSpansTriples = const [];
        stats.value = const _TreeSitterHighlightStats(
          _TreeSitterHighlightState.disabled,
          reason: '> 6MB',
        );
        onUpdated();
        return;
      }

      stats.value =
          const _TreeSitterHighlightStats(_TreeSitterHighlightState.parsing);
      try {
        final payload = _HighlightPayload(text: text, language: language);
        final lineSpans = await Isolate.run(() => _highlightWorker(payload));
        if (_disposed || rev != _revision) return;
        _lineSpansTriples = lineSpans;
        stats.value = const _TreeSitterHighlightStats(
          _TreeSitterHighlightState.idle,
        );
        onUpdated();
      } catch (_) {
        if (_disposed || rev != _revision) return;
        _lineSpansTriples = const [];
        stats.value =
            const _TreeSitterHighlightStats(_TreeSitterHighlightState.error);
        onUpdated();
      }
    });
  }

  TextSpan buildLineSpan({
    required int lineIndex,
    required String lineText,
    required TextStyle baseStyle,
    required TextSpan baseSpan,
  }) {
    if (lineIndex < 0 || lineIndex >= _lineSpansTriples.length) {
      return baseSpan;
    }

    final triples = _lineSpansTriples[lineIndex];
    if (triples.isEmpty) return baseSpan;

    final children = <TextSpan>[];
    var cursor = 0;

    for (var i = 0; i + 2 < triples.length; i += 3) {
      final start = triples[i].clamp(0, lineText.length);
      final end = triples[i + 1].clamp(0, lineText.length);
      final color = triples[i + 2];
      if (end <= start) continue;

      if (start > cursor) {
        children.add(
          TextSpan(text: lineText.substring(cursor, start), style: baseStyle),
        );
      }
      children.add(
        TextSpan(
          text: lineText.substring(start, end),
          style: baseStyle.copyWith(color: Color(color)),
        ),
      );
      cursor = end;
    }

    if (cursor < lineText.length) {
      children.add(TextSpan(text: lineText.substring(cursor), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

class _HighlightPayload {
  final String text;
  final _FileLanguage language;
  const _HighlightPayload({required this.text, required this.language});
}

@pragma('vm:entry-point')
List<List<int>> _highlightWorker(_HighlightPayload payload) {
  final text = payload.text;
  final tokens = ts.parseTokens(
    text,
    language: switch (payload.language) {
      _FileLanguage.c => ts.TreeSitterLanguage.c,
      _FileLanguage.javascript => ts.TreeSitterLanguage.javascript,
      _FileLanguage.dart => ts.TreeSitterLanguage.dart,
    },
  );

  final byteToUtf16 = _buildByteToUtf16Map(text);
  final lineStarts = _lineStartsUtf16(text);
  final perLine = List.generate(lineStarts.length, (_) => <int>[]);

  int mapByte(int b) {
    if (b <= 0) return 0;
    if (b >= byteToUtf16.last.$1) return byteToUtf16.last.$2;
    var lo = 0, hi = byteToUtf16.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = byteToUtf16[mid].$1;
      if (v == b) return byteToUtf16[mid].$2;
      if (v < b) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // Not an exact boundary (should be rare); clamp to previous.
    return byteToUtf16[hi.clamp(0, byteToUtf16.length - 1)].$2;
  }

  int lineForUtf16(int i) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final s = lineStarts[mid];
      if (s == i) return mid;
      if (s < i) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi.clamp(0, lineStarts.length - 1);
  }

  int lineEndUtf16(int line) {
    if (line + 1 >= lineStarts.length) return text.length;
    // Next line starts after a '\n', so current line ends at (nextStart - 1).
    return (lineStarts[line + 1] - 1).clamp(0, text.length);
  }

  void addSpan(int startUtf16, int endUtf16, int color) {
    if (endUtf16 <= startUtf16) return;
    final startLine = lineForUtf16(startUtf16);
    final endLine = lineForUtf16(endUtf16);
    if (startLine == endLine) {
      final base = lineStarts[startLine];
      perLine[startLine].addAll([startUtf16 - base, endUtf16 - base, color]);
      return;
    }
    {
      final base = lineStarts[startLine];
      perLine[startLine].addAll([
        startUtf16 - base,
        lineEndUtf16(startLine) - base,
        color,
      ]);
    }
    for (var line = startLine + 1; line < endLine; line++) {
      final base = lineStarts[line];
      perLine[line].addAll([0, lineEndUtf16(line) - base, color]);
    }
    {
      final base = lineStarts[endLine];
      perLine[endLine].addAll([0, endUtf16 - base, color]);
    }
  }

  for (final token in tokens) {
    final start = mapByte(token.startByte);
    final end = mapByte(token.endByte);
    if (end <= start) continue;
    final color = _tokenColor(
      token,
      language: payload.language,
    );
    if (color == 0xFFD4D4D4) continue;
    addSpan(start, end, color);
  }

  for (var i = 0; i < perLine.length; i++) {
    perLine[i] = _normalizeTriples(perLine[i]);
  }

  return perLine;
}

List<(int, int)> _buildByteToUtf16Map(String text) {
  final pairs = <(int, int)>[];
  var byte = 0;
  var utf16 = 0;
  pairs.add((0, 0));
  for (final rune in text.runes) {
    byte += _utf8Len(rune);
    utf16 += rune > 0xFFFF ? 2 : 1;
    pairs.add((byte, utf16));
  }
  return pairs;
}

int _utf8Len(int rune) {
  if (rune <= 0x7F) return 1;
  if (rune <= 0x7FF) return 2;
  if (rune <= 0xFFFF) return 3;
  return 4;
}

List<int> _lineStartsUtf16(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    final cu = text.codeUnitAt(i);
    if (cu == 0x0A /* \n */) {
      starts.add(i + 1);
    }
  }
  if (starts.isEmpty) return const [0];
  return starts;
}

List<int> _normalizeTriples(List<int> triples) {
  if (triples.isEmpty) return const [];
  final spans = <({int s, int e, int c})>[];
  for (var i = 0; i + 2 < triples.length; i += 3) {
    spans.add((s: triples[i], e: triples[i + 1], c: triples[i + 2]));
  }
  spans.sort((a, b) {
    final s = a.s.compareTo(b.s);
    if (s != 0) return s;
    return a.e.compareTo(b.e);
  });

  final out = <({int s, int e, int c})>[];
  for (final span in spans) {
    if (out.isEmpty) {
      out.add(span);
      continue;
    }
    final prev = out.last;
    if (span.s >= prev.e) {
      out.add(span);
      continue;
    }
    // Overlap: clamp the new span to start after the previous end.
    final clampedStart = prev.e;
    if (span.e > clampedStart) {
      out.add((s: clampedStart, e: span.e, c: span.c));
    }
  }

  final flattened = <int>[];
  for (final span in out) {
    flattened.addAll([span.s, span.e, span.c]);
  }
  return flattened;
}

int _tokenColor(ts.TreeSitterToken token, {required _FileLanguage language}) {
  final type = token.type;

  if (type.contains('comment')) return 0xFF6A9955;
  if (type.contains('string') || type.contains('char')) return 0xFFCE9178;
  if (type.contains('number')) return 0xFFB5CEA8;
  if (type.contains('type') || type == 'primitive_type') return 0xFF4EC9B0;

  if (!token.named) {
    if (_isKeyword(type, language: language)) return 0xFF569CD6;
    if (_isOperator(type)) return 0xFFD4D4D4;
    return 0xFFD4D4D4;
  }

  if (type.endsWith('identifier') || type == 'identifier') return 0xFF9CDCFE;
  if (type.contains('function')) return 0xFFDCDCAA;

  return 0xFFD4D4D4;
}

bool _isOperator(String type) {
  const ops = {
    '+',
    '-',
    '*',
    '/',
    '%',
    '=',
    '==',
    '!=',
    '<',
    '<=',
    '>',
    '>=',
    '&&',
    '||',
    '!',
    '&',
    '|',
    '^',
    '~',
    '<<',
    '>>',
    '+=',
    '-=',
    '*=',
    '/=',
    '%=',
    '=>',
    '?.',
    '??',
    '??=',
  };
  return ops.contains(type);
}

bool _isKeyword(String type, {required _FileLanguage language}) {
  switch (language) {
    case _FileLanguage.c:
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
    case _FileLanguage.javascript:
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
        'try',
        'catch',
        'finally',
        'throw',
        'await',
        'async',
        'yield',
      }.contains(type);
    case _FileLanguage.dart:
      return const {
        'abstract',
        'as',
        'assert',
        'async',
        'await',
        'base',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'covariant',
        'default',
        'deferred',
        'do',
        'dynamic',
        'else',
        'enum',
        'export',
        'extends',
        'extension',
        'external',
        'factory',
        'false',
        'final',
        'finally',
        'for',
        'Function',
        'get',
        'hide',
        'if',
        'implements',
        'import',
        'in',
        'interface',
        'is',
        'late',
        'library',
        'mixin',
        'new',
        'null',
        'of',
        'on',
        'operator',
        'part',
        'required',
        'rethrow',
        'return',
        'sealed',
        'set',
        'show',
        'static',
        'super',
        'switch',
        'sync',
        'this',
        'throw',
        'true',
        'try',
        'typedef',
        'var',
        'void',
        'when',
        'while',
        'with',
        'yield',
      }.contains(type);
  }
}

const _seedC = r'''
#include <stdio.h>

typedef struct {
  int id;
  const char* name;
} User;

static int add(int a, int b) {
  return a + b;
}

int main(void) {
  // VS Code-ish demo file
  User u = { .id = 1, .name = "Ada" };
  printf("hello %s (%d) -> %d\n", u.name, u.id, add(1, 2));
  return 0;
}
''';

const _seedJs = r'''
// Simple demo file
export function add(a, b) {
  return a + b;
}

async function main() {
  const user = { id: 1, name: "Ada" };
  console.log(`hello ${user.name} (${user.id}) -> ${add(1, 2)}`);
}

main();
''';

const _seedDart = r'''
import 'dart:math' as math;

class Greeter {
  final String name;
  const Greeter(this.name);

  String greet() => 'Hello, $name';
}

int add(int a, int b) => a + b;

void main() {
  // VS Code-ish demo file
  final g = Greeter('World');
  final r = math.Random(1).nextInt(10);
  print('${g.greet()} -> ${add(r, 2)}');
}
''';
