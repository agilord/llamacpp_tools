import 'package:args/command_runner.dart';

import 'github_downloader.dart';

/// Main GitHub command that groups all GitHub-related subcommands.
class GithubCommand extends Command<void> {
  @override
  final String name = 'github';

  @override
  final String description =
      'GitHub repository management for llama.cpp releases.';

  GithubCommand() {
    addSubcommand(GithubScrapeRecentVersionsCommand());
    addSubcommand(GithubSetupReleaseCommand());
  }
}

/// Command to scrape recent versions from GitHub releases.
class GithubScrapeRecentVersionsCommand extends Command<void> {
  @override
  final String name = 'scrape-recent-versions';

  @override
  final String description =
      'Scrape recent llama.cpp versions from GitHub releases page.';

  @override
  Future<void> run() async {
    print('Scraping recent versions from GitHub...');

    final versions = await scrapeRecentLlamacppVersionsFromGitHub();

    if (versions.isEmpty) {
      print('No versions found.');
      return;
    }

    print('Recent llama.cpp versions:');
    for (final version in versions) {
      print('  $version');
    }
  }

  @override
  String get invocation => 'llamacpp_tools github scrape-recent-versions';
}

/// Command to setup a llama.cpp release from GitHub.
class GithubSetupReleaseCommand extends Command<void> {
  @override
  final String name = 'setup-release';

  @override
  final String description =
      'Download and setup a llama.cpp release from GitHub.';

  GithubSetupReleaseCommand() {
    argParser.addOption(
      'version',
      abbr: 'v',
      help: 'The llama.cpp version to download and setup.',
      mandatory: true,
    );
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'The target directory to install llama.cpp.',
      mandatory: true,
    );
  }

  @override
  Future<void> run() async {
    final version = argResults!['version'] as String;
    final targetPath = argResults!['target'] as String;

    print('Setting up llama.cpp version $version in $targetPath...');

    final llamacppDir = await setupLllamacppReleaseFromGitHub(
      targetPath: targetPath,
      version: version,
    );

    print('Successfully setup llama.cpp at ${llamacppDir.rootPath}');

    // Verify installation by getting version
    try {
      final installedVersion = await llamacppDir.getVersion();
      print('Installed version: $installedVersion');
    } catch (e) {
      print('Warning: Could not verify installed version: $e');
    }
  }

  @override
  String get invocation =>
      'llamacpp_tools github setup-release --version <version> --target <path>';
}
