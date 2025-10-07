import 'dart:io';
import 'package:path/path.dart' as path;

import 'dockerfiles.g.dart';

class LlamacppDocker {
  /// Builds a Docker container from a Dockerfile builder.
  ///
  /// [builder] - The builder to lookup in dockerfileContents (without .Dockerfile extension)
  /// [containerName] - The name/tag for the built container
  ///
  /// Creates a temporary directory, writes the Dockerfile content, and builds the container.
  static Future<void> buildBuilder({
    required String builder,
    required String containerName,
  }) async {
    final dockerfileKey = '$builder.Dockerfile';

    // Lookup the Dockerfile content
    final dockerfileContent = dockerfileContents[dockerfileKey];
    if (dockerfileContent == null) {
      throw ArgumentError('Dockerfile not found for builder: $dockerfileKey');
    }

    // Create temporary directory
    final tempDir = await Directory.systemTemp.createTemp('docker_build_');

    try {
      // Write Dockerfile content to temp directory
      final dockerfilePath = path.join(tempDir.path, 'Dockerfile');
      await File(dockerfilePath).writeAsString(dockerfileContent);

      print('Building Docker container: $containerName');
      print('Using Dockerfile: $dockerfileKey');
      print('Temp directory: ${tempDir.path}');

      // Run docker build command
      final result = await Process.run('docker', [
        'build',
        '-t',
        containerName,
        '.',
      ], workingDirectory: tempDir.path);

      if (result.exitCode != 0) {
        throw Exception(
          'Docker build failed with exit code ${result.exitCode}:\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
        );
      }

      print('Successfully built Docker container: $containerName');
      if (result.stdout.toString().isNotEmpty) {
        print('Build output:\n${result.stdout}');
      }
    } finally {
      // Clean up temporary directory
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        print('Warning: Could not delete temp directory ${tempDir.path}: $e');
      }
    }
  }

  /// Runs a Docker container with specified parameters.
  ///
  /// [containerName] - The name/tag of the container to run
  /// [version] - The version parameter to pass to the container
  /// [outputDirectory] - The directory to mount as /output in the container
  ///
  /// Runs the container with GPU support and mounts the output directory.
  static Future<void> runBuilder(
    String containerName,
    String version,
    String outputDirectory,
  ) async {
    // Ensure output directory exists
    final outputDir = Directory(outputDirectory);
    await outputDir.create(recursive: true);

    print('Running Docker container: $containerName');
    print('Version: $version');
    print('Output directory: ${outputDir.absolute.path}');

    // Run docker run command with GPU support and volume mount
    final result = await Process.run('docker', [
      'run',
      '--rm',
      '--gpus',
      'all',
      '-v',
      '${outputDir.absolute.path}:/output',
      containerName,
      version,
    ]);

    if (result.exitCode != 0) {
      throw Exception(
        'Docker run failed with exit code ${result.exitCode}:\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
      );
    }

    print('Docker container completed successfully');
    if (result.stdout.toString().isNotEmpty) {
      print('Container output:\n${result.stdout}');
    }
  }

  /// Lists available Dockerfile builders that can be used with buildDockerContainer.
  ///
  /// Returns a list of builders (without .Dockerfile extension) that can be passed
  /// to buildDockerContainer.
  static List<String> listBuilders() {
    return dockerfileContents.keys
        .where((key) => key.endsWith('.Dockerfile'))
        .map((key) => key.substring(0, key.length - 11)) // Remove .Dockerfile
        .toList()
      ..sort();
  }
}
