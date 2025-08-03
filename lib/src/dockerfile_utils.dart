import 'dart:io';
import 'package:path/path.dart' as path;

/// Scans the ./docker/ directory and generates lib/src/dockerfiles.g.dart
/// with const String variables for each Dockerfile found.
Future<void> generateDockerfilesConstants() async {
  final dockerDir = Directory('docker');
  final outputFile = File('lib/src/dockerfiles.g.dart');

  if (!await dockerDir.exists()) {
    throw StateError('Docker directory not found: ${dockerDir.path}');
  }

  final dockerfiles = <String, ({String variableName, String content})>{};

  // Scan for Dockerfile files
  await for (final entity in dockerDir.list()) {
    if (entity is File) {
      final fileName = path.basename(entity.path);
      if (fileName.toLowerCase().endsWith('dockerfile')) {
        final content = await entity.readAsString();
        final variableName = _createVariableName(fileName);
        dockerfiles[fileName] = (variableName: variableName, content: content);
      }
    }
  }

  if (dockerfiles.isEmpty) {
    throw StateError('No Dockerfile files found in ${dockerDir.path}');
  }

  // Generate the output file
  final buffer = StringBuffer();
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated from Dockerfiles in docker/');
  buffer.writeln('');

  // Sort by variable name for consistent output
  final sortedEntries = dockerfiles.entries.toList()
    ..sort((a, b) => a.value.variableName.compareTo(b.value.variableName));

  for (final entry in sortedEntries) {
    buffer.writeln('/// Content of ${entry.key}');
    buffer.writeln(
      'const String ${entry.value.variableName} = r\'\'\'${entry.value.content}\'\'\';',
    );
    buffer.writeln('');
  }

  // Generate dockerfileContents map
  buffer.writeln('/// Map from relative filename to Dockerfile content');
  buffer.writeln('final Map<String, String> dockerfileContents = {');
  for (final entry in sortedEntries) {
    buffer.writeln('  \'${entry.key}\': ${entry.value.variableName},');
  }
  buffer.writeln('};');

  await outputFile.writeAsString(buffer.toString());

  print(
    'Generated ${outputFile.path} with ${dockerfiles.length} Dockerfile(s):',
  );
  for (final entry in dockerfiles.entries) {
    print('  - ${entry.key} -> ${entry.value.variableName}');
  }
}

/// Creates a valid Dart variable name from a filename.
/// Examples:
/// - "cuda-builder.Dockerfile" -> "_cudaBuilderDockerfile"
/// - "Dockerfile" -> "_dockerfile"
/// - "multi-stage.dockerfile" -> "_multiStageDockerfile"
String _createVariableName(String fileName) {
  // Remove file extension and normalize
  String name = fileName;
  if (name.toLowerCase().endsWith('.dockerfile')) {
    name = name.substring(0, name.length - 11); // Remove ".dockerfile"
  } else if (name.toLowerCase() == 'dockerfile') {
    name = 'dockerfile';
  }

  // Convert to camelCase
  final parts = name.split(RegExp(r'[-_.]'));
  final camelCase =
      parts.first.toLowerCase() +
      parts.skip(1).map((part) => _capitalize(part.toLowerCase())).join('');

  // Add "Dockerfile" suffix if not already present
  String variableName = camelCase;
  if (!camelCase.toLowerCase().endsWith('dockerfile')) {
    variableName = camelCase + 'Dockerfile';
  }

  // Make it private by adding underscore prefix
  return '_$variableName';
}

/// Capitalizes the first letter of a string.
String _capitalize(String str) {
  if (str.isEmpty) return str;
  return str[0].toUpperCase() + str.substring(1).toLowerCase();
}

/// Main function to run the generator when this file is executed directly.
Future<void> main(List<String> args) async {
  try {
    await generateDockerfilesConstants();
    print('Successfully generated dockerfiles.g.dart');
  } catch (e) {
    print('Error generating dockerfiles.g.dart: $e');
    exit(1);
  }
}
