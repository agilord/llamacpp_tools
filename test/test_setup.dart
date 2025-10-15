import 'dart:io';
import 'package:huggingface_tools/huggingface_tools.dart';
import 'package:llamacpp_tools/src/llamacpp_dir.dart';
import 'package:path/path.dart' as path;

import 'package:llamacpp_tools/src/llamacpp_github.dart';

class TestSetup {
  late LlamacppDir llamacppDir;
  late File modelFile;

  Future<void> setUp() async {
    final versions = await LlamacppGithub.scrapeRecentVersions();
    final targetVersion = versions.first;
    final llamaPath = path.join(
      '.dart_tool',
      'cached',
      'llama_cpp',
      targetVersion,
    );
    llamacppDir = await LlamacppGithub.downloadAndSetupRelease(
      targetPath: llamaPath,
      version: targetVersion,
    );

    modelFile = File(
      path.join('.dart_tool', 'cached', 'model', 'gte-small.Q2_K.gguf'),
    ).absolute;
    if (!await modelFile.exists()) {
      await modelFile.parent.create(recursive: true);
      final model = await getModelInfo('ChristianAzinn/gte-small-gguf');

      final ggufFile = model.ggufModelFiles.firstWhere(
        (f) => f.filename == 'gte-small.Q2_K.gguf',
      );
      await downloadFile(ggufFile, targetFilePath: modelFile.path);
    }
  }
}
