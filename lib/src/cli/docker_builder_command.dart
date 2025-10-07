import 'package:args/command_runner.dart';

import '../docker/docker_builder.dart';

/// Main Docker command that groups all Docker-related subcommands.
class DockerCommand extends Command<void> {
  @override
  final String name = 'docker';

  @override
  final String description =
      'Docker container management for llama.cpp builds.';

  DockerCommand() {
    addSubcommand(BuildBuilderCommand());
    addSubcommand(RunBuilderCommand());
    addSubcommand(ListBuildersCommand());
  }
}

/// Command to build a Docker container from a Dockerfile builder.
class BuildBuilderCommand extends Command<void> {
  @override
  final String name = 'build-builder';

  @override
  final String description =
      'Build a Docker container from a Dockerfile builder.';

  BuildBuilderCommand() {
    argParser.addOption(
      'builder',
      abbr: 'b',
      help: 'The Dockerfile builder (without .Dockerfile extension).',
      mandatory: true,
    );
    argParser.addOption(
      'container',
      abbr: 'c',
      help: 'The name/tag for the built container.',
      mandatory: true,
    );
  }

  @override
  Future<void> run() async {
    final builder = argResults!['builder'] as String;
    final containerName = argResults!['container'] as String;

    await LlamacppDocker.buildBuilder(
      builder: builder,
      containerName: containerName,
    );
  }

  @override
  String get invocation =>
      'llamacpp_tools docker build-builder --builder <builder> --container <container-name>';
}

/// Command to run a Docker container with specified parameters.
class RunBuilderCommand extends Command<void> {
  @override
  final String name = 'run-builder';

  @override
  final String description = 'Run a Docker container to build llama.cpp.';

  RunBuilderCommand() {
    argParser.addOption(
      'container',
      help: 'The name/tag of the container to run.',
      mandatory: true,
    );
    argParser.addOption(
      'version',
      abbr: 'v',
      help: 'The llama.cpp version to build.',
      mandatory: true,
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'The output directory for built binaries.',
      defaultsTo: './output',
    );
  }

  @override
  Future<void> run() async {
    final containerName = argResults!['container'] as String;
    final version = argResults!['version'] as String;
    final outputDirectory = argResults!['output'] as String;

    await LlamacppDocker.runBuilder(containerName, version, outputDirectory);
  }

  @override
  String get invocation =>
      'llamacpp_tools docker run-builder --container <name> --version <version> [--output <dir>]';
}

/// Command to list available Dockerfile builders.
class ListBuildersCommand extends Command<void> {
  @override
  final String name = 'list-builders';

  @override
  final String description =
      'List available Dockerfile builders that can be built.';

  @override
  Future<void> run() async {
    final builders = LlamacppDocker.listBuilders();

    if (builders.isEmpty) {
      print('No Dockerfile builders available.');
      return;
    }

    print('Available Dockerfile builders:');
    for (final builder in builders) {
      print('  $builder');
    }
    print('');
    print(
      'Use these builders with: llamacpp_tools docker build-builder --builder <builder> --container <container-name>',
    );
  }

  @override
  String get invocation => 'llamacpp_tools docker list-builders';
}
