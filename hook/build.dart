import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

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
