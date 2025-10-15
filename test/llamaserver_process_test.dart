import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:llamacpp_tools/src/llamaserver_process.dart';
import 'package:test/test.dart';

import 'test_setup.dart';

void main() {
  group('LllamacppProcess', () {
    final testSetup = TestSetup();

    setUp(() async {
      await testSetup.setUp();
    });

    test('run', () async {
      final process = LlamaserverProcess(
        dir: testSetup.llamacppDir,
        config: LlamaserverConfig(modelPath: testSetup.modelFile.path),
        logWriter: (_) {},
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
