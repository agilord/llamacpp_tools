import 'package:llamacpp_tools/src/model/detect_model.dart';
import 'package:test/test.dart';

import 'test_setup.dart';

void main() {
  group('ModelDetector', () {
    final testSetup = TestSetup();

    setUpAll(() async {
      await testSetup.setUp();
    });

    test('run detection', () async {
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
    });
  });
}
