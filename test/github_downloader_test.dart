import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:llamacpp_tools/src/github_downloader.dart';
import 'package:llamacpp_tools/src/llamacpp_dir.dart';

void main() {
  group('GitHub Version Scraping', () {
    test('scrapeRecentVersionsFromGitHub returns versions', () async {
      // Call the function to scrape versions from GitHub
      final versions = await scrapeRecentLlamacppVersionsFromGitHub();

      // Assert that we got some versions back
      expect(
        versions,
        isNotEmpty,
        reason: 'Should return at least one version',
      );

      // Assert that versions are non-empty strings
      for (final version in versions) {
        expect(
          version,
          isNotEmpty,
          reason: 'Version string should not be empty',
        );
        expect(version, isA<String>(), reason: 'Version should be a string');
      }

      // Print versions for debugging (optional)
      print(
        'Found ${versions.length} versions: ${versions.take(5).join(', ')}${versions.length > 5 ? '...' : ''}',
      );
    });

    test('scrapeRecentVersionsFromGitHub returns unique versions', () async {
      final versions = await scrapeRecentLlamacppVersionsFromGitHub();

      // Convert to set and back to list to check for duplicates
      final uniqueVersions = versions.toSet().toList();

      expect(
        versions.length,
        equals(uniqueVersions.length),
        reason: 'All versions should be unique',
      );
    });
  });

  group('GitHub Download and Setup', () {
    test(
      'download and verify llama.cpp installation',
      () async {
        // This test downloads a real release, so it may take some time
        // and requires internet connection
        print('Fetching recent versions from GitHub...');

        // Get recent versions
        final versions = await scrapeRecentLlamacppVersionsFromGitHub();
        expect(
          versions,
          isNotEmpty,
          reason: 'Should find at least one version',
        );

        // Pick the first (most recent) version
        final targetVersion = versions.first;
        print('Using version: $targetVersion');

        // Setup target directory
        final targetPath = path.join(
          '.dart_tool',
          'cached',
          'llama_cpp',
          targetVersion,
        );

        print('Downloading and setting up llama.cpp to: $targetPath');

        // Download and setup the release
        final llamacppDir = await setupLllamacppReleaseFromGitHub(
          targetPath: targetPath,
          version: targetVersion,
        );

        // Verify the installation
        expect(
          llamacppDir,
          isNotNull,
          reason: 'Should return a valid LlamacppDir',
        );
        expect(
          llamacppDir.rootPath,
          contains(targetVersion),
          reason: 'Root path should contain the version',
        );

        // Detect the installation
        print('Detecting llama.cpp installation...');
        final detectedDir = await LlamacppDir.detect(targetPath);
        expect(
          detectedDir,
          isNotNull,
          reason: 'Should detect the installation',
        );
        expect(
          detectedDir!.rootPath,
          equals(llamacppDir.rootPath),
          reason: 'Detected directory should match setup directory',
        );

        // Verify binary paths exist
        final serverPath = await detectedDir.getServerPath();
        final cliPath = await detectedDir.getCliPath();

        expect(
          serverPath,
          isNotNull,
          reason: 'Should find llama-server binary',
        );
        expect(cliPath, isNotNull, reason: 'Should find llama-cli binary');

        expect(
          await File(serverPath!).exists(),
          isTrue,
          reason: 'llama-server file should exist',
        );
        expect(
          await File(cliPath!).exists(),
          isTrue,
          reason: 'llama-cli file should exist',
        );

        // Get and verify the version
        print('Verifying installation version...');
        final installedVersion = await detectedDir.version;
        expect(
          installedVersion,
          equals(targetVersion),
          reason: 'Installed version should match requested version',
        );

        print(
          'Successfully verified llama.cpp version $installedVersion installation',
        );

        // Test that detecting the same directory again returns the same result
        final secondDetection = await LlamacppDir.detect(targetPath);
        expect(secondDetection, isNotNull);
        expect(secondDetection!.rootPath, equals(detectedDir.rootPath));

        // Test that calling setup again with same version returns existing installation
        print('Testing setup with existing installation...');
        final existingDir = await setupLllamacppReleaseFromGitHub(
          targetPath: targetPath,
          version: targetVersion,
        );
        expect(
          existingDir.rootPath,
          equals(llamacppDir.rootPath),
          reason: 'Should return existing installation when version matches',
        );
      },
      timeout: Timeout(Duration(minutes: 10)),
    ); // Allow time for download

    test('setup fails with version mismatch', () async {
      // This test requires an existing installation from the previous test
      final versions = await scrapeRecentLlamacppVersionsFromGitHub();
      expect(
        versions.length,
        greaterThan(1),
        reason: 'Need at least 2 versions for this test',
      );

      final existingVersion = versions.first;
      final differentVersion = versions[1];

      final targetPath = path.join(
        '.dart_tool',
        'cached',
        'llama_cpp',
        existingVersion,
      );

      // Verify we have an existing installation
      final existingDir = await LlamacppDir.detect(targetPath);
      if (existingDir == null) {
        // Skip this test if no existing installation
        markTestSkipped(
          'No existing installation found for version mismatch test',
        );
        return;
      }

      // Try to setup with a different version - should fail
      expect(
        () => setupLllamacppReleaseFromGitHub(
          targetPath: targetPath,
          version: differentVersion,
        ),
        throwsA(isA<StateError>()),
        reason: 'Should throw StateError when version mismatch detected',
      );
    });
  });
}
