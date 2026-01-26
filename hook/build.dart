import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

Uri? _findVs2022MsvcTool({
  required Logger logger,
  required String toolName,
  required String targetArchFolder,
}) {
  // Prefer VS 2022 Community (commonly installed with the Desktop C++ workload).
  const vsRoot = r'C:\Program Files\Microsoft Visual Studio\2022\Community';
  final msvcRoot = Directory(
    '$vsRoot\\VC\\Tools\\MSVC',
  );
  if (!msvcRoot.existsSync()) {
    logger.info('VS2022 MSVC root not found: ${msvcRoot.path}');
    return null;
  }

  // Pick the newest MSVC version folder.
  final versions =
      msvcRoot
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  for (final v in versions) {
    final exe = File(
      '${v.path}\\bin\\Hostx64\\$targetArchFolder\\$toolName.exe',
    );
    if (exe.existsSync()) {
      logger.info('Using MSVC tool from VS2022: ${exe.path}');
      return exe.uri;
    }
  }

  logger.warning('Failed to locate $toolName.exe under ${msvcRoot.path}');
  return null;
}

void _forceWindowsCompilerIfMissing(BuildInput input, Logger logger) {
  final cfg = input.config.code;
  if (cfg.targetOS != OS.windows) return;
  if (cfg.cCompiler?.compiler != null) return;

  // native_toolchain_c defaults to the latest Visual Studio instance; on some
  // machines that may be installed without MSVC (cl.exe). Prefer VS2022 when
  // present so `dart test` and build hooks work out-of-the-box.
  final targetArchFolder = switch (cfg.targetArchitecture) {
    Architecture.ia32 => 'x86',
    Architecture.x64 => 'x64',
    Architecture.arm64 => 'arm64',
    _ => 'x64',
  };

  final cl = _findVs2022MsvcTool(
    logger: logger,
    toolName: 'cl',
    targetArchFolder: targetArchFolder,
  );
  final lib = _findVs2022MsvcTool(
    logger: logger,
    toolName: 'lib',
    targetArchFolder: targetArchFolder,
  );
  final link = _findVs2022MsvcTool(
    logger: logger,
    toolName: 'link',
    targetArchFolder: targetArchFolder,
  );
  if (cl == null || lib == null || link == null) return;

  final configJson = input.config.json;
  final extensions =
      (configJson['extensions'] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  configJson['extensions'] = extensions;

  final codeAssets =
      (extensions['code_assets'] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  extensions['code_assets'] = codeAssets;

  final cCompiler =
      (codeAssets['c_compiler'] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  codeAssets['c_compiler'] = cCompiler;

  // These are file paths (strings) in the schema.
  cCompiler['cc'] = cl.toFilePath();
  cCompiler['ar'] = lib.toFilePath();
  cCompiler['ld'] = link.toFilePath();
  // Work around native_toolchain_c accessing `cCompilerConfig.windows` without
  // guarding for null. An empty object means "Windows config present but no
  // developer command prompt override".
  cCompiler['windows'] = (cCompiler['windows'] as Map?) ?? <String, Object?>{};
}

Future<void> _ensureGitClone({
  required Logger logger,
  required Directory directory,
  required String url,
  String? ref,
}) async {
  final gitDir = Directory.fromUri(directory.uri.resolve('.git/'));
  if (gitDir.existsSync()) {
    return;
  }

  if (directory.existsSync()) {
    logger.info('Deleting stale directory: ${directory.path}');
    directory.deleteSync(recursive: true);
  }

  final cloneArgs = <String>[
    'clone',
    '--depth',
    '1',
    if (ref != null) ...['--branch', ref],
    url,
    directory.path,
  ];
  logger.info('git ${cloneArgs.join(' ')}');
  final result = await Process.run('git', cloneArgs, runInShell: true);
  if (result.exitCode != 0) {
    throw InfraError(
      message:
          'Failed to clone $url into ${directory.path}.\n'
          '${result.stdout}\n${result.stderr}',
    );
  }
}

Future<String?> _copySource({
  required Logger logger,
  required String sourcePath,
  required Directory destinationDirectory,
  required String destinationFileName,
}) async {
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    logger.warning('Missing source file: $sourcePath');
    return null;
  }

  destinationDirectory.createSync(recursive: true);
  final destinationFile = File(
    destinationDirectory.uri.resolve(destinationFileName).toFilePath(),
  );
  await sourceFile.copy(destinationFile.path);
  return destinationFile.path;
}

Future<String?> _copyHeader({
  required Logger logger,
  required String sourcePath,
  required Directory destinationDirectory,
  required String destinationFileName,
}) async {
  return _copySource(
    logger: logger,
    sourcePath: sourcePath,
    destinationDirectory: destinationDirectory,
    destinationFileName: destinationFileName,
  );
}

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    hierarchicalLoggingEnabled = true;
    Logger.root
      ..level = Level.ALL
      ..onRecord.listen((record) => stdout.writeln(record.message));
    final logger = Logger('native');

    _forceWindowsCompilerIfMissing(input, logger);

    final packageName = input.packageName;

    final thirdPartyDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('third_party/'),
    )..createSync(recursive: true);

    final treeSitterDir = Directory.fromUri(
      thirdPartyDir.uri.resolve('tree-sitter/'),
    );
    final treeSitterCDir = Directory.fromUri(
      thirdPartyDir.uri.resolve('tree-sitter-c/'),
    );
    final treeSitterJavascriptDir = Directory.fromUri(
      thirdPartyDir.uri.resolve('tree-sitter-javascript/'),
    );
    final treeSitterDartDir = Directory.fromUri(
      thirdPartyDir.uri.resolve('tree-sitter-dart/'),
    );

    await _ensureGitClone(
      logger: logger,
      directory: treeSitterDir,
      url: 'https://github.com/tree-sitter/tree-sitter.git',
      ref: 'v0.26.3',
    );
    await _ensureGitClone(
      logger: logger,
      directory: treeSitterCDir,
      url: 'https://github.com/tree-sitter/tree-sitter-c.git',
    );
    await _ensureGitClone(
      logger: logger,
      directory: treeSitterJavascriptDir,
      url: 'https://github.com/tree-sitter/tree-sitter-javascript.git',
    );
    await _ensureGitClone(
      logger: logger,
      directory: treeSitterDartDir,
      url: 'https://github.com/UserNobody14/tree-sitter-dart.git',
      ref: 'master',
    );

    final treeSitterInclude = Directory.fromUri(
      treeSitterDir.uri.resolve('lib/include/'),
    );
    final treeSitterSrc = Directory.fromUri(
      treeSitterDir.uri.resolve('lib/src/'),
    );
    final treeSitterAmalgamatedSource = treeSitterSrc.uri
        .resolve('lib.c')
        .toFilePath();

    // native_toolchain_c compiles all sources into a single output directory.
    // Many grammars use the same basename (`parser.c`), which can cause MSVC to
    // emit the same object name (`parser.obj`) multiple times, and then ignore
    // duplicates at link time. Copy grammar sources to unique filenames first.
    final stagedGrammarDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('third_party_generated/'),
    );
    final stagedTreeSitterHeadersDir = Directory.fromUri(
      stagedGrammarDir.uri.resolve('tree_sitter/'),
    );

    // Some grammars include `tree_sitter/parser.h`, but tree-sitter keeps it in
    // `lib/src/parser.h`. Provide a tiny include shim by copying it.
    await _copyHeader(
      logger: logger,
      sourcePath: treeSitterSrc.uri.resolve('parser.h').toFilePath(),
      destinationDirectory: stagedTreeSitterHeadersDir,
      destinationFileName: 'parser.h',
    );

    final languageSources = <String>[
      if (await _copySource(
            logger: logger,
            sourcePath: treeSitterCDir.uri.resolve('src/parser.c').toFilePath(),
            destinationDirectory: stagedGrammarDir,
            destinationFileName: 'tree_sitter_c_parser.c',
          )
          case final path?)
        path,
      if (await _copySource(
            logger: logger,
            sourcePath: treeSitterJavascriptDir.uri
                .resolve('src/parser.c')
                .toFilePath(),
            destinationDirectory: stagedGrammarDir,
            destinationFileName: 'tree_sitter_javascript_parser.c',
          )
          case final path?)
        path,
      if (await _copySource(
            logger: logger,
            sourcePath: treeSitterJavascriptDir.uri
                .resolve('src/scanner.c')
                .toFilePath(),
            destinationDirectory: stagedGrammarDir,
            destinationFileName: 'tree_sitter_javascript_scanner.c',
          )
          case final path?)
        path,
      if (await _copySource(
            logger: logger,
            sourcePath: treeSitterDartDir.uri
                .resolve('src/parser.c')
                .toFilePath(),
            destinationDirectory: stagedGrammarDir,
            destinationFileName: 'tree_sitter_dart_parser.c',
          )
          case final path?)
        path,
      if (await _copySource(
            logger: logger,
            sourcePath: treeSitterDartDir.uri
                .resolve('src/scanner.c')
                .toFilePath(),
            destinationDirectory: stagedGrammarDir,
            destinationFileName: 'tree_sitter_dart_scanner.c',
          )
          case final path?)
        path,
    ];

    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: [
        'src/$packageName.c',
        treeSitterAmalgamatedSource,
        ...languageSources,
      ],
      includes: [
        treeSitterInclude.path,
        treeSitterSrc.path,
        stagedGrammarDir.path,
      ],
    );

    await cbuilder.run(input: input, output: output, logger: logger);
  });
}
