import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as path;

import 'llamacpp_dir.dart';

/// Visits the llama.cpp GitHub page for recent releases, parses
/// the HTML and returns the versions that may be the most recent ones.
Future<List<String>> scrapeRecentLlamacppVersionsFromGitHub() async {
  final releasePageUrl = 'https://github.com/ggml-org/llama.cpp/releases';

  try {
    // Make HTTP GET request to the releases page
    final response = await http.get(Uri.parse(releasePageUrl));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch releases page: ${response.statusCode}');
    }

    // Parse the HTML content
    final document = html.parse(response.body);

    // Find release version links - GitHub uses specific CSS classes for release tags
    final versionElements = document.querySelectorAll(
      'a[href*="/releases/tag/"]',
    );

    final versions = <String>[];

    for (final element in versionElements) {
      final href = element.attributes['href'];
      if (href != null) {
        // Extract version from href like "/ggml-org/llama.cpp/releases/tag/b3875"
        final tagMatch = RegExp(r'/releases/tag/(.+)$').firstMatch(href);
        if (tagMatch != null) {
          var version = tagMatch.group(1);
          if (version != null) {
            // Remove 'b' prefix if present (e.g., "b3875" becomes "3875")
            if (version.startsWith('b')) {
              version = version.substring(1);
            }
            if (!versions.contains(version)) {
              versions.add(version);
            }
          }
        }
      }
    }

    return versions;
  } catch (e) {
    throw Exception('Failed to scrape versions from GitHub: $e');
  }
}

/// Returns null if no release was detected.
Future<String?> _detectGithubReleaseUrl(String version) async {
  // Add 'b' prefix for the download URL since GitHub releases use 'b' prefix
  final tagVersion = 'b$version';
  return 'https://github.com/ggerganov/llama.cpp/releases/download/$tagVersion/llama-$tagVersion-bin-ubuntu-x64.zip';
}

Future<LlamacppDir> setupLllamacppReleaseFromGitHub({
  required String targetPath,
  required String version,
}) async {
  // Check if targetPath is already a valid LlamacppDir
  final existingDir = await LlamacppDir.detect(targetPath);
  if (existingDir != null) {
    // Check if the existing installation matches the requested version
    try {
      final existingVersion = await existingDir.version;
      if (existingVersion == version) {
        return existingDir;
      } else {
        throw StateError(
          'Target path contains llama.cpp version $existingVersion, but requested version $version',
        );
      }
    } catch (e) {
      throw StateError(
        'Target path contains llama.cpp but version cannot be determined: $e',
      );
    }
  }

  final releaseUrl = await _detectGithubReleaseUrl(version);
  if (releaseUrl == null) {
    throw StateError('Unable to detect release binary for $version.');
  }

  // Download and extract release to targetPath
  await _downloadAndExtractRelease(releaseUrl, targetPath, version);

  // Verify the installation
  final installedDir = await LlamacppDir.detect(targetPath);
  if (installedDir == null) {
    throw StateError('Failed to install llama.cpp to $targetPath');
  }

  return installedDir;
}

/// Downloads and extracts a llama.cpp release to the target path.
Future<void> _downloadAndExtractRelease(
  String releaseUrl,
  String targetPath,
  String version,
) async {
  // Create target directory if it doesn't exist
  final targetDir = Directory(targetPath);
  await targetDir.create(recursive: true);

  // Download the release
  final response = await http.get(Uri.parse(releaseUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to download release: ${response.statusCode}');
  }

  // Save to temporary file
  // Create temporary file for the zip
  final tempDir = Directory.systemTemp.createTempSync('llamacpp_tools_');
  final zipFile = File(path.join(tempDir.path, 'llama-cpp.zip'));
  await zipFile.writeAsBytes(response.bodyBytes);

  try {
    // Extract the ZIP file using system unzip command
    final result = await Process.run('unzip', [
      '-o',
      zipFile.path,
      '-d',
      '.',
    ], workingDirectory: targetPath);

    if (result.exitCode != 0) {
      throw Exception('Failed to extract ZIP file: ${result.stderr}');
    }
  } finally {
    // Clean up temporary ZIP file
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
