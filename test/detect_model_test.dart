import 'package:llamacpp_tools/src/llamaserver_switcher.dart';
import 'package:llamacpp_tools/src/model/detect_model.dart';
import 'package:llamacpp_tools/src/model/llamaserver_spec_registry.dart';
import 'package:test/test.dart';

import 'test_setup.dart';

void main() {
  group('ModelDetector', () {
    final testSetup = TestSetup();

    setUpAll(() async {
      await testSetup.setUp();
    });

    test('run detection and test registry', () async {
      final detector = ModelDetector(
        llamacppDir: testSetup.llamacppDir,
        modelPath: testSetup.modelFile.path,
      );
      final result = await detector.detect();
      expect(result.toJson(), {
        'fileInfo': {
          'fileSize': 105454144,
          'sha256':
              'ed5fa30c487b282ec156c29062f1222e5c20875a944ac98289dbd242e947f747',
          'architecture': 'llama',
          'contextLength': 8192,
          'blockCount': 30,
          'parameterCount': 134515008,
          'metadata': isNotEmpty,
        },
        'benchmarks': [
          {
            'contextSize': 4096,
            'config': {'contextSize': 4096, 'flashAttention': isNotEmpty},
            'promptTps': isPositive,
            'generationTps': isPositive,
          },
          {
            'contextSize': 8192,
            'config': {'contextSize': 8192, 'flashAttention': isNotEmpty},
            'promptTps': isPositive,
            'generationTps': isPositive,
          },
        ],
      });

      // Test registry
      final registry = LlamaserverSpecRegistry(
        llamacppDir: testSetup.llamacppDir,
      );
      registry.addModelDetectionResult(
        result,
        aliases: ['test-model', 'my-model'],
      );

      // Test successful selections

      // By SHA256
      final specBySha256 = registry.selectSpec(
        'ed5fa30c487b282ec156c29062f1222e5c20875a944ac98289dbd242e947f747',
        contextSize: 4096,
      );
      expect(specBySha256, isNotNull);
      expect(specBySha256!.config.contextSize, 4096);

      // By alias
      final specByAlias = registry.selectSpec('test-model', contextSize: 4096);
      expect(specByAlias, isNotNull);
      expect(specByAlias!.config.contextSize, 4096);

      // By filename (full)
      final specByFilename = registry.selectSpec(
        'tinyllama-1.1b-chat-v1.0.q2_k',
        contextSize: 4096,
      );
      expect(specByFilename, isNotNull);

      // By filename without quantization
      final specByBaseFilename = registry.selectSpec(
        'smollm2-135m-instruct',
        contextSize: 4096,
      );
      expect(specByBaseFilename, isNotNull);

      // Test context size selection (should get 8192 when requesting 5000)
      final specLargerContext = registry.selectSpec(
        'test-model',
        contextSize: 5000,
      );
      expect(specLargerContext, isNotNull);
      expect(specLargerContext!.config.contextSize, 8192);

      // Test null returns

      // Non-existent model
      final specNotFound = registry.selectSpec(
        'non-existent-model',
        contextSize: 4096,
      );
      expect(specNotFound, isNull);

      // Context size too large
      final specContextTooLarge = registry.selectSpec(
        'test-model',
        contextSize: 16384,
      );
      expect(specContextTooLarge, isNull);

      // Wrong SHA256
      final specWrongSha = registry.selectSpec(
        '0000000000000000000000000000000000000000000000000000000000000000',
      );
      expect(specWrongSha, isNull);
    });
  });
}
