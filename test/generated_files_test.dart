import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Generated Files', () {
    test('generated files are up to date', () async {
      // Check if we're in a git repository
      final gitDir = Directory('.git');
      if (!await gitDir.exists()) {
        markTestSkipped(
          'Not in a git repository - skipping generated files test',
        );
        return;
      }

      print('Running file generation...');

      // Run the generate_files.sh script
      final result = await Process.run('bash', [
        'tool/generate_files.sh',
      ], workingDirectory: Directory.current.path);

      if (result.exitCode != 0) {
        fail(
          'generate_files.sh failed with exit code ${result.exitCode}:\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
        );
      }

      print('File generation completed. Checking for git changes...');

      // Check if any .g.dart files have been modified
      final gitStatusResult = await Process.run('git', [
        'status',
        '--porcelain',
        '*.g.dart',
      ], workingDirectory: Directory.current.path);

      if (gitStatusResult.exitCode != 0) {
        fail(
          'git status failed with exit code ${gitStatusResult.exitCode}:\n'
          'stdout: ${gitStatusResult.stdout}\n'
          'stderr: ${gitStatusResult.stderr}',
        );
      }

      final gitOutput = gitStatusResult.stdout.toString().trim();

      if (gitOutput.isNotEmpty) {
        // Show which files changed
        final changedFiles = gitOutput
            .split('\n')
            .where((line) => line.contains('.g.dart'))
            .map((line) => line.substring(2).trim()) // Remove git status prefix
            .toList();

        fail(
          'Generated files are out of date. The following .g.dart files have changes:\n'
          '${changedFiles.map((file) => '  - $file').join('\n')}\n'
          '\n'
          'Please run "tool/generate_files.sh" to update generated files and commit the changes.\n'
          '\n'
          'Git status output:\n$gitOutput',
        );
      }

      print('✅ All generated files are up to date');
    });
  });
}
