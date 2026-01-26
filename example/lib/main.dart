import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/styles/vs2015.dart';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart'
    as ts;

void main() {
  runApp(const VsCodeLikeApp());
}

enum _FileLanguage { c, javascript, dart }

enum _HighlightEngine { reHighlight, treeSitter }

class _EditorFile {
  final String path;
  final _FileLanguage language;
  late final CodeLineEditingController controller;
  late final _TreeSitterHighlighter highlighter;
  final ValueNotifier<_HighlightEngine> highlightEngine = ValueNotifier(
    _HighlightEngine.treeSitter,
  );

  _EditorFile({
    required this.path,
    required this.language,
    required String initialText,
  }) {
    highlighter = _TreeSitterHighlighter(language: language);
    highlighter.initialize(initialText);
    controller = CodeLineEditingController(
      codeLines: initialText.codeLines,
      options: const CodeLineOptions(
        lineBreak: TextLineBreak.lf,
        indentSize: 2,
      ),
      spanBuilder:
          ({
            required BuildContext context,
            required int index,
            required CodeLine codeLine,
            required TextSpan textSpan,
            required TextStyle style,
          }) {
            if (highlightEngine.value != _HighlightEngine.treeSitter) {
              return textSpan;
            }
            return highlighter.buildLineSpan(
              lineIndex: index,
              lineText: codeLine.text,
              baseStyle: style,
              baseSpan: textSpan,
            );
          },
    );

    controller.addListener(() {
      final pre = controller.preValue;
      if (pre?.codeLines == controller.codeLines) {
        return;
      }
      if (highlightEngine.value == _HighlightEngine.treeSitter) {
        highlighter.schedule(
          controller.text,
          onUpdated: controller.forceRepaint,
        );
      }
    });
    highlightEngine.addListener(() {
      final mode = highlightEngine.value;
      highlighter.setEnabled(mode == _HighlightEngine.treeSitter);
      if (mode == _HighlightEngine.treeSitter) {
        highlighter.schedule(
          controller.text,
          onUpdated: controller.forceRepaint,
        );
      }
      controller.forceRepaint();
    });

    highlighter.setEnabled(
      highlightEngine.value == _HighlightEngine.treeSitter,
    );
    if (highlightEngine.value == _HighlightEngine.treeSitter) {
      highlighter.schedule(controller.text, onUpdated: controller.forceRepaint);
    }
  }

  void dispose() {
    controller.dispose();
    highlighter.dispose();
    highlightEngine.dispose();
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
    unawaited(_loadHighlightQueries());
  }

  Future<void> _loadHighlightQueries() async {
    try {
      final c = await rootBundle.loadString(
        'assets/tree_sitter/c/highlights.scm',
      );
      final js = await rootBundle.loadString(
        'assets/tree_sitter/javascript/highlights.scm',
      );
      final dart = await rootBundle.loadString(
        'assets/tree_sitter/dart/highlights.scm',
      );

      for (final f in _files) {
        final query = switch (f.language) {
          _FileLanguage.c => c,
          _FileLanguage.javascript => js,
          _FileLanguage.dart => dart,
        };
        f.highlighter.setQuery(query);
        f.highlighter.schedule(
          f.controller.text,
          onUpdated: f.controller.forceRepaint,
        );
      }
    } catch (_) {
      // If assets fail to load, we'll fall back to token-based highlighting.
    }
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
            color: active ? const Color(0xFFFFFFFF) : const Color(0xFFCCCCCC),
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
      child: ValueListenableBuilder<_HighlightEngine>(
        valueListenable: file.highlightEngine,
        builder: (context, engine, _) {
          final codeTheme = switch (engine) {
            _HighlightEngine.reHighlight => _reHighlightTheme(file.language),
            _HighlightEngine.treeSitter => null,
          };

          return CodeEditor(
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
              codeTheme: codeTheme,
            ),
            indicatorBuilder:
                (context, editingController, chunkController, notifier) {
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
          );
        },
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
              ValueListenableBuilder<_HighlightEngine>(
                valueListenable: file.highlightEngine,
                builder: (context, engine, _) {
                  final label = switch (engine) {
                    _HighlightEngine.reHighlight => 'HL: RE',
                    _HighlightEngine.treeSitter => 'HL: TS',
                  };
                  return InkWell(
                    onTap: () {
                      final next = switch (engine) {
                        _HighlightEngine.reHighlight =>
                          _HighlightEngine.treeSitter,
                        _HighlightEngine.treeSitter =>
                          _HighlightEngine.reHighlight,
                      };
                      file.highlightEngine.value = next;
                    },
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<_HighlightEngine>(
                valueListenable: file.highlightEngine,
                builder: (context, engine, _) {
                  if (engine != _HighlightEngine.treeSitter) {
                    return const Text(
                      're-highlight',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    );
                  }

                  return ValueListenableBuilder<_TreeSitterHighlightStats>(
                    valueListenable: file.highlighter.stats,
                    builder: (context, stats, _) {
                      final label = switch (stats.state) {
                        _TreeSitterHighlightState.idle => 'tree-sitter',
                        _TreeSitterHighlightState.parsing =>
                          'tree-sitter: parsing…',
                        _TreeSitterHighlightState.disabled =>
                          'tree-sitter: disabled (${stats.reason})',
                        _TreeSitterHighlightState.error =>
                          stats.reason == null
                              ? 'tree-sitter: error'
                              : 'tree-sitter: error (details)',
                      };
                      return InkWell(
                        onTap:
                            (stats.state == _TreeSitterHighlightState.error &&
                                stats.reason != null)
                            ? () {
                                showDialog<void>(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: const Text('tree-sitter error'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(stats.reason!),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Close'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            : null,
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
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

  final _FileLanguage language;
  final ValueNotifier<bool> enabled = ValueNotifier(true);
  final ValueNotifier<_TreeSitterHighlightStats> stats = ValueNotifier(
    const _TreeSitterHighlightStats(_TreeSitterHighlightState.idle),
  );

  int _revision = 0;
  bool _disposed = false;
  String _text = '';
  List<int> _lineStarts = const [0];
  List<_Span> _spans = const [];
  String? _query;
  ts.TreeSitterDocument? _doc;
  bool _postFrameScheduled = false;
  bool _needsRun = false;

  _TreeSitterHighlighter({required this.language});

  void setEnabled(bool value) {
    if (_disposed) return;
    if (enabled.value == value) return;
    enabled.value = value;

    if (!value) {
      _spans = const [];
      stats.value = const _TreeSitterHighlightStats(
        _TreeSitterHighlightState.disabled,
        reason: 'toggled off',
      );
    } else {
      stats.value = const _TreeSitterHighlightStats(
        _TreeSitterHighlightState.idle,
      );
    }
  }

  void initialize(String initialText) {
    if (_text.isNotEmpty) return;
    _text = initialText;
    _lineStarts = _lineStartsUtf16ForText(initialText);
    try {
      _doc = ts.TreeSitterDocument.create(
        language: switch (language) {
          _FileLanguage.c => ts.TreeSitterLanguage.c,
          _FileLanguage.javascript => ts.TreeSitterLanguage.javascript,
          _FileLanguage.dart => ts.TreeSitterLanguage.dart,
        },
      );
      _doc!.reparse(initialText);
    } catch (e, st) {
      final details = '$e\n\n$st';
      debugPrint(details);
      stats.value = _TreeSitterHighlightStats(
        _TreeSitterHighlightState.error,
        reason: details,
      );
      _doc = null;
    }
  }

  void dispose() {
    _disposed = true;
    _doc?.dispose();
    enabled.dispose();
    stats.dispose();
  }

  void setQuery(String? query) {
    _query = query;
  }

  void schedule(String text, {required VoidCallback onUpdated}) {
    if (_disposed) return;
    if (!enabled.value) return;

    final change = _computeChange(_text, text);
    _applyChangeToSpans(change);

    // IMPORTANT: Apply `ts_tree_edit` immediately so the native document stays
    // in sync even if we debounce/cancel reparses. Otherwise, the next debounced
    // edit would be computed against the updated Dart text but applied to a
    // stale native tree, causing unstable highlighting.
    final docForEdit = _doc;
    if (docForEdit != null &&
        (change.startUtf16 != change.oldEndUtf16 ||
            change.startUtf16 != change.newEndUtf16)) {
      docForEdit.edit(
        startByte: change.startByte,
        oldEndByte: change.oldEndByte,
        newEndByte: change.newEndByte,
        startRow: change.startRow,
        startCol: change.startCol,
        oldEndRow: change.oldEndRow,
        oldEndCol: change.oldEndCol,
        newEndRow: change.newEndRow,
        newEndCol: change.newEndCol,
      );
    }

    _text = text;
    _lineStarts = _lineStartsUtf16ForText(text);

    _revision++;
    _needsRun = true;
    if (_postFrameScheduled) return;
    _postFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      if (_disposed) return;
      if (!enabled.value) return;
      if (!_needsRun) return;
      _needsRun = false;

      final rev = _revision;

      final doc = _doc;
      if (doc == null) {
        _spans = const [];
        stats.value = const _TreeSitterHighlightStats(
          _TreeSitterHighlightState.error,
          reason: 'tree-sitter document not initialized',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => onUpdated());
        return;
      }

      if (_text.length > _maxBytesForHighlight) {
        _spans = const [];
        stats.value = const _TreeSitterHighlightStats(
          _TreeSitterHighlightState.disabled,
          reason: '> 6MB',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => onUpdated());
        return;
      }

      stats.value = const _TreeSitterHighlightStats(
        _TreeSitterHighlightState.parsing,
      );
      try {
        // Incremental parse on UI isolate: reuse the already-edited tree.
        final ok = doc.reparse(_text);
        if (!ok) {
          throw StateError('ts_doc_reparse failed');
        }

        final query = _query;
        if (query == null || query.trim().isEmpty) {
          _spans = const [];
        } else {
          final captures = doc.queryCaptures(query);
          _spans = _capturesToSpans(_text, captures);
        }
        if (_disposed || rev != _revision) return;
        stats.value = const _TreeSitterHighlightStats(
          _TreeSitterHighlightState.idle,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => onUpdated());
      } catch (e, st) {
        if (_disposed || rev != _revision) return;
        _spans = const [];
        final details = '$e\n\n$st';
        debugPrint(details);
        stats.value = _TreeSitterHighlightStats(
          _TreeSitterHighlightState.error,
          reason: details,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => onUpdated());
      }
      // If more edits came in while we were running, schedule another pass.
      if (_needsRun && !_postFrameScheduled) {
        _postFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameScheduled = false;
          if (_disposed || !enabled.value) return;
          if (_needsRun) {
            schedule(_text, onUpdated: onUpdated);
          }
        });
      }
    });
  }

  TextSpan buildLineSpan({
    required int lineIndex,
    required String lineText,
    required TextStyle baseStyle,
    required TextSpan baseSpan,
  }) {
    if (!enabled.value) return baseSpan;
    if (lineIndex < 0 || lineIndex >= _lineStarts.length) return baseSpan;

    final lineStart = _lineStarts[lineIndex];
    final lineEnd = (lineIndex + 1 < _lineStarts.length)
        ? (_lineStarts[lineIndex + 1] - 1).clamp(0, _text.length)
        : _text.length;

    if (lineEnd <= lineStart) return baseSpan;

    final triples = _triplesForLine(lineStart, lineEnd);
    if (triples.isEmpty) return baseSpan;

    final children = <TextSpan>[];
    var cursor = 0;

    for (var i = 0; i + 2 < triples.length; i += 3) {
      final start = (triples[i] - lineStart).clamp(0, lineText.length);
      final end = (triples[i + 1] - lineStart).clamp(0, lineText.length);
      final color = triples[i + 2];
      if (end <= start) continue;

      // Guard against overlapping/out-of-order spans. If we render spans that
      // move backwards, we can end up duplicating text (e.g. "mainmainmain").
      final safeStart = start < cursor ? cursor : start;
      if (end <= safeStart) continue;

      if (safeStart > cursor) {
        children.add(
          TextSpan(
            text: lineText.substring(cursor, safeStart),
            style: baseStyle,
          ),
        );
      }
      children.add(
        TextSpan(
          text: lineText.substring(safeStart, end),
          style: baseStyle.copyWith(color: Color(color)),
        ),
      );
      cursor = end;
    }

    if (cursor < lineText.length) {
      children.add(
        TextSpan(text: lineText.substring(cursor), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }

  List<int> _triplesForLine(int lineStart, int lineEnd) {
    if (_spans.isEmpty) return const [];
    final out = <int>[];

    // First span that might intersect this line.
    var lo = 0;
    var hi = _spans.length - 1;
    var first = _spans.length;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_spans[mid].endUtf16 <= lineStart) {
        lo = mid + 1;
      } else {
        first = mid;
        hi = mid - 1;
      }
    }

    for (var i = first; i < _spans.length; i++) {
      final s = _spans[i];
      if (s.startUtf16 >= lineEnd) break;
      final start = s.startUtf16.clamp(lineStart, lineEnd);
      final end = s.endUtf16.clamp(lineStart, lineEnd);
      if (end <= start) continue;
      out.addAll([start, end, s.color]);
    }

    return out;
  }

  List<_Span> _capturesToSpans(
    String text,
    List<ts.TreeSitterCapture> captures,
  ) {
    if (captures.isEmpty) return const [];
    final byteToUtf16 = _buildByteToUtf16Map(text);

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
      return byteToUtf16[hi.clamp(0, byteToUtf16.length - 1)].$2;
    }

    final ranked = <_RankedSpan>[];
    for (final cap in captures) {
      final style = _captureStyle(cap.name);
      if (style == null) continue;
      final start = mapByte(cap.startByte);
      final end = mapByte(cap.endByte);
      if (end <= start) continue;
      ranked.add(_RankedSpan(start, end, style.color, style.priority));
    }

    ranked.sort((a, b) {
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      final s = a.startUtf16.compareTo(b.startUtf16);
      if (s != 0) return s;
      return b.endUtf16.compareTo(a.endUtf16);
    });

    final out = <_Span>[];
    for (final span in ranked) {
      _insertNonOverlappingSorted(out, span);
    }
    return out;
  }

  void _insertNonOverlappingSorted(List<_Span> out, _RankedSpan span) {
    var start = span.startUtf16;
    final end = span.endUtf16;
    if (end <= start) return;

    // `out` is always sorted by start and non-overlapping.
    int lowerBound(int pos) {
      var lo = 0;
      var hi = out.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (out[mid].endUtf16 <= pos) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    int lowerBoundByStart(int pos) {
      var lo = 0;
      var hi = out.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (out[mid].startUtf16 < pos) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final insertAt = lowerBound(start);
    var i = insertAt;
    var cursor = start;
    final pieces = <_Span>[];

    while (i < out.length) {
      final existing = out[i];
      if (existing.startUtf16 >= end) break;

      if (existing.startUtf16 > cursor) {
        pieces.add(
          _Span(cursor, existing.startUtf16.clamp(cursor, end), span.color),
        );
      }

      if (existing.endUtf16 > cursor) {
        cursor = existing.endUtf16;
      }
      if (cursor >= end) break;
      i++;
    }

    if (cursor < end) {
      pieces.add(_Span(cursor, end, span.color));
    }

    if (pieces.isEmpty) return;
    // Insert each piece at its sorted position to preserve ordering.
    for (final piece in pieces) {
      out.insert(lowerBoundByStart(piece.startUtf16), piece);
    }
  }

  void _applyChangeToSpans(_TextChange change) {
    if (_spans.isEmpty) return;
    final delta = change.newEndUtf16 - change.oldEndUtf16;
    final changedStart = change.startUtf16;
    final changedOldEnd = change.oldEndUtf16;

    final updated = <_Span>[];
    for (final s in _spans) {
      final intersects =
          s.startUtf16 < changedOldEnd && s.endUtf16 > changedStart;
      if (intersects) continue;

      if (s.startUtf16 >= changedOldEnd) {
        updated.add(_Span(s.startUtf16 + delta, s.endUtf16 + delta, s.color));
      } else {
        updated.add(s);
      }
    }
    _spans = updated;
  }
}

CodeHighlightTheme _reHighlightTheme(_FileLanguage language) {
  final key = switch (language) {
    _FileLanguage.c => 'c',
    _FileLanguage.javascript => 'javascript',
    _FileLanguage.dart => 'dart',
  };
  final mode = switch (language) {
    _FileLanguage.c => langC,
    _FileLanguage.javascript => langJavascript,
    _FileLanguage.dart => langDart,
  };

  return CodeHighlightTheme(
    languages: {key: CodeHighlightThemeMode(mode: mode)},
    theme: vs2015Theme,
  );
}

List<int> _lineStartsUtf16ForText(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

class _CaptureStyle {
  final int priority;
  final int color;
  const _CaptureStyle(this.priority, this.color);
}

_CaptureStyle? _captureStyle(String name) {
  final group = name.split('.').first;
  switch (group) {
    case 'comment':
      return const _CaptureStyle(90, 0xFF6A9955);
    case 'string':
      return const _CaptureStyle(80, 0xFFCE9178);
    case 'number':
      return const _CaptureStyle(70, 0xFFB5CEA8);
    case 'keyword':
      return const _CaptureStyle(60, 0xFF569CD6);
    case 'type':
      return const _CaptureStyle(55, 0xFF4EC9B0);
    case 'function':
      return const _CaptureStyle(50, 0xFFDCDCAA);
    case 'constant':
    case 'boolean':
    case 'constructor':
      return const _CaptureStyle(45, 0xFF569CD6);
    case 'operator':
    case 'punctuation':
    case 'delimiter':
      return const _CaptureStyle(40, 0xFFD4D4D4);
    case 'variable':
    case 'property':
    case 'attribute':
    case 'identifier':
      return const _CaptureStyle(30, 0xFF9CDCFE);
    default:
      return null;
  }
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

class _Span {
  final int startUtf16;
  final int endUtf16;
  final int color;
  const _Span(this.startUtf16, this.endUtf16, this.color);
}

class _RankedSpan extends _Span {
  final int priority;
  const _RankedSpan(
    super.startUtf16,
    super.endUtf16,
    super.color,
    this.priority,
  );
}

class _TextChange {
  final int startUtf16;
  final int oldEndUtf16;
  final int newEndUtf16;
  final int startByte;
  final int oldEndByte;
  final int newEndByte;
  final int startRow;
  final int startCol;
  final int oldEndRow;
  final int oldEndCol;
  final int newEndRow;
  final int newEndCol;

  const _TextChange({
    required this.startUtf16,
    required this.oldEndUtf16,
    required this.newEndUtf16,
    required this.startByte,
    required this.oldEndByte,
    required this.newEndByte,
    required this.startRow,
    required this.startCol,
    required this.oldEndRow,
    required this.oldEndCol,
    required this.newEndRow,
    required this.newEndCol,
  });
}

_TextChange _computeChange(String oldText, String newText) {
  if (oldText == newText) {
    return const _TextChange(
      startUtf16: 0,
      oldEndUtf16: 0,
      newEndUtf16: 0,
      startByte: 0,
      oldEndByte: 0,
      newEndByte: 0,
      startRow: 0,
      startCol: 0,
      oldEndRow: 0,
      oldEndCol: 0,
      newEndRow: 0,
      newEndCol: 0,
    );
  }

  var start = 0;
  final minLen = oldText.length < newText.length
      ? oldText.length
      : newText.length;
  while (start < minLen &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
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

  final startByte = _utf8LenOfSlice(oldText, 0, start);
  final oldEndByte = startByte + _utf8LenOfSlice(oldText, start, oldEnd);
  final newEndByte = startByte + _utf8LenOfSlice(newText, start, newEnd);

  final (sr, sc) = _pointAtUtf16(oldText, start);
  final (oer, oec) = _pointAtUtf16(oldText, oldEnd);
  final (ner, nec) = _pointAtUtf16(newText, newEnd);

  return _TextChange(
    startUtf16: start,
    oldEndUtf16: oldEnd,
    newEndUtf16: newEnd,
    startByte: startByte,
    oldEndByte: oldEndByte,
    newEndByte: newEndByte,
    startRow: sr,
    startCol: sc,
    oldEndRow: oer,
    oldEndCol: oec,
    newEndRow: ner,
    newEndCol: nec,
  );
}

(int, int) _pointAtUtf16(String text, int utf16Index) {
  utf16Index = utf16Index.clamp(0, text.length);
  var row = 0;
  var lastLineStart = 0;
  for (var i = 0; i < utf16Index; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      row++;
      lastLineStart = i + 1;
    }
  }
  final colBytes = _utf8LenOfSlice(text, lastLineStart, utf16Index);
  return (row, colBytes);
}

int _utf8LenOfSlice(String text, int start, int end) {
  start = start.clamp(0, text.length);
  end = end.clamp(start, text.length);
  var bytes = 0;
  for (final rune in text.substring(start, end).runes) {
    bytes += _utf8Len(rune);
  }
  return bytes;
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
