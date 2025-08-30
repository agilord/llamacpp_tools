import 'dart:io';

import 'package:path/path.dart' as path;

/// Represents a detected llama.cpp directory with its root path.
///
/// This class is used to scan directories and detect valid llama.cpp
/// installations, returning the root directory where llama.cpp is found.
class LlamacppDir {
  /// The root directory path where llama.cpp was detected.
  final String rootPath;

  /// Creates a new LlamacppDir instance with the detected root path.
  ///
  /// [rootPath] - The directory path where llama.cpp was found
  LlamacppDir._(this.rootPath);

  /// Detects a llama.cpp installation starting from the given path.
  ///
  /// Scans the provided [path] and its subdirectories to find a valid
  /// llama.cpp installation. Returns a [LlamacppDir] instance if found,
  /// or null if no valid installation is detected.
  ///
  /// [path] - The directory path to start scanning from
  ///
  /// Returns a Future that completes with a [LlamacppDir] if found, or null.
  static Future<LlamacppDir?> detect(String path) async {
    final directory = Directory(path).absolute;
    path = directory.path;

    if (!directory.existsSync()) {
      return null;
    }

    // First check if the given path itself contains llama.cpp
    if (await _isLlamacppDirectory(path)) {
      return LlamacppDir._(path);
    }

    // Then recursively search subdirectories
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is Directory) {
          if (await _isLlamacppDirectory(entity.path)) {
            return LlamacppDir._(entity.path);
          }
        }
      }
    } catch (e) {
      // Ignore permission errors and continue searching
    }

    return null;
  }

  /// Checks if a directory contains a valid llama.cpp installation.
  ///
  /// [directoryPath] - The directory path to check
  ///
  /// Returns true if the directory contains both llama-server and llama-cli binaries.
  static Future<bool> _isLlamacppDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);

    if (!directory.existsSync()) {
      return false;
    }

    try {
      // Check for both required binaries
      final serverPath = path.join(directoryPath, 'llama-server');
      final cliPath = path.join(directoryPath, 'llama-cli');

      final serverFile = File(serverPath);
      final cliFile = File(cliPath);

      // Both files must exist
      if (!await serverFile.exists() || !await cliFile.exists()) {
        return false;
      }

      // Check if both files are executable
      final serverStat = await serverFile.stat();
      final cliStat = await cliFile.stat();

      return (serverStat.mode & 0x49 != 0) && (cliStat.mode & 0x49 != 0);
    } catch (e) {
      // Return false on any errors
      return false;
    }
  }

  /// Validates that the detected directory still contains llama.cpp.
  ///
  /// Returns true if the root path still contains valid llama.cpp binaries.
  Future<bool> isValid() async {
    return await _isLlamacppDirectory(rootPath);
  }

  /// Gets the path to a specific binary by name.
  ///
  /// [binaryName] - The binary name to find (e.g., 'llama-server', 'llama-cli')
  ///
  /// Returns the full path to the binary if found, null otherwise.
  Future<String?> _getBinaryPath(String binaryName) async {
    final binaryPath = path.join(rootPath, binaryName);
    final file = File(binaryPath);

    if (await file.exists()) {
      return binaryPath;
    }

    return null;
  }

  /// Gets the path to the llama-server binary.
  ///
  /// Returns the full path to the binary if found, null otherwise.
  Future<String?> getServerPath() async {
    return await _getBinaryPath('llama-server');
  }

  /// Gets the path to the llama-cli binary.
  ///
  /// Returns the full path to the binary if found, null otherwise.
  Future<String?> getCliPath() async {
    return await _getBinaryPath('llama-cli');
  }

  /// Gets the full output of calling `llama-cli --version`.
  /// Throws an exception if llama-cli is not found.
  late final llamacliFullVersionOutput = () async {
    final cliPath = await getCliPath();
    if (cliPath == null) {
      throw StateError('llama-cli binary not found in $rootPath');
    }

    try {
      // Run llama-cli --version command
      final result = await Process.run(cliPath, [
        '--version',
      ], workingDirectory: path.dirname(cliPath));

      if (result.exitCode != 0) {
        throw Exception(
          'llama-cli --version failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }

      // Parse the output to extract version
      return result.stderr.toString();
    } catch (e) {
      throw Exception('Failed to get version from llama-cli: $e');
    }
  }();

  /// Gets the version of the llama.cpp installation by calling llama-cli --version.
  ///
  /// Returns the version string extracted from the llama-cli output.
  /// Throws an exception if llama-cli is not found or the version cannot be parsed.
  late final version = () async {
    final output = await llamacliFullVersionOutput;
    // Look for pattern like "version: 6067 (f738989d)"
    final versionMatch = RegExp(
      r'version:\s*(\d+)\s*\([^)]+\)',
    ).firstMatch(output);

    if (versionMatch != null) {
      final version = versionMatch.group(1);
      if (version != null) {
        return version;
      }
    }

    // If the standard pattern doesn't match, try to find just the number
    final numberMatch = RegExp(r'version:\s*(\d+)').firstMatch(output);
    if (numberMatch != null) {
      final version = numberMatch.group(1);
      if (version != null) {
        return version;
      }
    }

    throw Exception('Could not parse version from llama-cli output: $output');
  }();

  /// Gets the relative path from a base directory to the detected root.
  ///
  /// [basePath] - The base directory to calculate relative path from
  ///
  /// Returns the relative path, or the absolute path if not relative.
  String getRelativePath(String basePath) {
    return path.relative(rootPath, from: basePath);
  }

  @override
  String toString() {
    return 'LlamacppDir(rootPath: $rootPath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LlamacppDir && other.rootPath == rootPath;
  }

  @override
  int get hashCode => rootPath.hashCode;
}
