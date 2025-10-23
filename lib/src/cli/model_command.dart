import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../llamacpp_dir.dart';
import '../model/detect_model.dart';
import 'detect_all_command.dart';

/// Main Model command that groups all model-related subcommands.
class ModelCommand extends Command<void> {
  @override
  final String name = 'model';

  @override
  final String description = 'Model analysis and optimization tools.';

  ModelCommand() {
    addSubcommand(DetectModelCommand());
    addSubcommand(DetectAllCommand());
  }
}

/// Command to detect model capabilities and find optimal runtime settings.
class DetectModelCommand extends Command<void> {
  @override
  final String name = 'detect';

  @override
  final String description =
      'Analyze a GGUF model file and determine optimal runtime settings.';

  DetectModelCommand() {
    argParser.addOption(
      'llamacpp-dir',
      abbr: 'd',
      help: 'Path to the llama.cpp installation directory.',
      mandatory: true,
    );
    argParser.addOption(
      'model',
      abbr: 'm',
      help: 'Path to the GGUF model file to analyze.',
      mandatory: true,
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Output path for the JSON results file. Defaults to <model-path>.json.',
    );
  }

  @override
  Future<void> run() async {
    final llamacppDirPath = argResults!['llamacpp-dir'] as String;
    final modelPath = argResults!['model'] as String;
    final outputPath = argResults!['output'] as String?;

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

    // Run detection
    try {
      final detector = ModelDetector(
        llamacppDir: llamacppDir,
        modelPath: modelPath,
      );
      final result = await detector.detect();

      // Save to JSON file
      final jsonPath = outputPath ?? '$modelPath.json';
      final jsonFile = File(jsonPath);
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    } catch (e, stackTrace) {
      print('Error during model detection: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  String get invocation =>
      'llamacpp_tools model detect --llamacpp-dir <path> --model <path> [--output <path>]';
}
