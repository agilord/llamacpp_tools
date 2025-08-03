#!/usr/bin/env dart

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:llamacpp_tools/src/docker_builder_command.dart';
import 'package:llamacpp_tools/src/github_downloader_command.dart';

/// Command runner for llamacpp_tools CLI
class LlamacppToolsCommandRunner extends CommandRunner<void> {
  LlamacppToolsCommandRunner()
    : super(
        'llamacpp_tools',
        'Tools to manage llama.cpp local setup (detecting, downloading or building).',
      ) {
    addCommand(DockerCommand());
    addCommand(GithubCommand());
  }
}

Future<void> main(List<String> arguments) async {
  final runner = LlamacppToolsCommandRunner();

  try {
    await runner.run(arguments);
  } on UsageException catch (e, stackTrace) {
    // Handle usage errors (like --help or invalid arguments)
    print(e.message);
    if (e.usage.isNotEmpty) {
      print('');
      print(e.usage);
    }
    print('Stack trace:');
    print(stackTrace);
    exit(1);
  } catch (e, stackTrace) {
    // Handle other errors
    print('Error: $e');
    print('Stack trace:');
    print(stackTrace);
    exit(1);
  }
}
