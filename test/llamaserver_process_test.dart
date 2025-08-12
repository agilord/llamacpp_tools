import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:huggingface_tools/huggingface_tools.dart';
import 'package:llamacpp_tools/src/llamacpp_dir.dart';
import 'package:llamacpp_tools/src/llamaserver_process.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamacpp_tools/src/github_downloader.dart';

void main() {
  group('LllamacppProcess', () {
    late LlamacppDir llamacppDir;
    late File modelFile;

    setUp(() async {
      final versions = await scrapeRecentLlamacppVersionsFromGitHub();
      final targetVersion = versions.first;
      final llamaPath = path.join(
        '.dart_tool',
        'cached',
        'llama_cpp',
        targetVersion,
      );
      llamacppDir = await setupLllamacppReleaseFromGitHub(
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
    });

    test('run', () async {
      final process = LlamaserverProcess(
        dir: llamacppDir,
        config: LlamaserverConfig(modelPath: modelFile.path),
      );
      try {
        await process.start();
        final rs = await http.get(
          Uri.parse('http://127.0.0.1:${process.port}/health'),
        );
        expect(rs.statusCode, 200);
        expect(json.decode(rs.body), {'status': 'ok'});
      } finally {
        await process.stop();
      }
    });
  });
}
