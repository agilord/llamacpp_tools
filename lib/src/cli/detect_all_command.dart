import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../llamacpp_dir.dart';
import '../model/detect_model.dart';

/// Command to detect all GGUF models in a directory.
class DetectAllCommand extends Command<void> {
  @override
  final String name = 'detect-all';

  @override
  final String description =
      'Analyze all GGUF model files in a directory and determine optimal runtime settings.';

  DetectAllCommand() {
    argParser.addOption(
      'llamacpp-dir',
      abbr: 'd',
      help: 'Path to the llama.cpp installation directory.',
      mandatory: true,
    );
    argParser.addOption(
      'model-dir',
      abbr: 'm',
      help:
          'Directory containing GGUF model files to analyze (searched recursively).',
      mandatory: true,
    );
    argParser.addOption(
      'output-dir',
      abbr: 'o',
      help:
          'Output directory for JSON results files. If not specified, each JSON file is saved next to its model file.',
    );
    argParser.addFlag(
      'skip',
      help: 'Skip models that already have a JSON output file.',
      negatable: true,
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    final llamacppDirPath = argResults!['llamacpp-dir'] as String;
    final modelDirPath = argResults!['model-dir'] as String;
    final outputDirPath = argResults!['output-dir'] as String?;
    final skipExisting = argResults!['skip'] as bool;

    // Detect llama.cpp directory
    print('Detecting llama.cpp installation at: $llamacppDirPath');
    final llamacppDir = await LlamacppDir.detect(llamacppDirPath);

    if (llamacppDir == null) {
      print('Error: No valid llama.cpp installation found at $llamacppDirPath');
      print(
        'Please ensure the directory contains llama-server and llama-cli binaries.',
      );
      return;
    }

    print('Found llama.cpp at: ${llamacppDir.rootPath}');

    // Get version
    try {
      final version = await llamacppDir.version;
      print('llama.cpp version: $version');
    } catch (e) {
      print('Warning: Could not determine llama.cpp version: $e');
    }

    print('');

    // Find all GGUF files
    final modelDir = Directory(modelDirPath);
    if (!await modelDir.exists()) {
      print('Error: Model directory not found: $modelDirPath');
      return;
    }

    print('Scanning for GGUF files in: $modelDirPath');
    final ggufFiles = await _findGgufFiles(modelDir);

    if (ggufFiles.isEmpty) {
      print('No GGUF files found in directory.');
      return;
    }

    print('Found ${ggufFiles.length} GGUF file(s)\n');

    // Process each model
    final results = <String, bool>{}; // path -> success
    var skipped = 0;

    for (var i = 0; i < ggufFiles.length; i++) {
      final modelFile = ggufFiles[i];
      final modelPath = modelFile.path;
      final relativePath = p.relative(modelPath, from: modelDirPath);

      print('═' * 80);
      print('Processing model ${i + 1}/${ggufFiles.length}: $relativePath');
      print('═' * 80);

      // Determine output path
      String? outputPath;
      if (outputDirPath != null) {
        outputPath = p.join(outputDirPath, '$relativePath.json');
      } else {
        outputPath = '$modelPath.json';
      }

      // Check if output already exists and skip if requested
      if (skipExisting && await File(outputPath).exists()) {
        print('Skipping (output file already exists): $outputPath\n');
        skipped++;
        continue;
      }

      // Ensure output directory exists
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);

      // Run detection
      try {
        final detector = ModelDetector(
          llamacppDir: llamacppDir,
          modelPath: modelPath,
        );
        final result = await detector.detect();

        // Save to JSON file
        final jsonFile = File(outputPath);
        await jsonFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );

        results[relativePath] = true;
        print('');
      } catch (e, stackTrace) {
        print('Error during model detection: $e');
        print('Stack trace: $stackTrace');
        results[relativePath] = false;
        print('');
      }
    }

    // Print summary
    print('═' * 80);
    print('SUMMARY');
    print('═' * 80);
    print('Total models found: ${ggufFiles.length}');
    if (skipped > 0) {
      print('Skipped (already processed): $skipped');
    }
    print('Processed: ${results.length}');

    final successful = results.values.where((success) => success).length;
    final failed = results.length - successful;

    print('Successful: $successful');
    if (failed > 0) {
      print('Failed: $failed');
      print('\nFailed models:');
      for (final entry in results.entries) {
        if (!entry.value) {
          print('  - ${entry.key}');
        }
      }
    }
  }

  /// Recursively finds all .gguf files in the directory
  Future<List<File>> _findGgufFiles(Directory dir) async {
    final ggufFiles = <File>[];

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
          ggufFiles.add(entity);
        }
      }
    } catch (e) {
      print('Warning: Error scanning directory: $e');
    }

    // Sort files by path for consistent ordering
    ggufFiles.sort((a, b) => a.path.compareTo(b.path));

    return ggufFiles;
  }

  @override
  String get invocation =>
      'llamacpp_tools model detect-all --llamacpp-dir <path> --model-dir <path> [--output-dir <path>] [--[no-]skip]';
}
