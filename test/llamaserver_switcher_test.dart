import 'package:llamacpp_tools/src/llamaserver_process.dart';
import 'package:llamacpp_tools/src/llamaserver_switcher.dart';
import 'package:process_visor/process_switcher.dart';
import 'package:test/test.dart';

import 'test_setup.dart';

void main() {
  group('LlamaserverSwitcher', () {
    final testSetup = TestSetup();

    setUpAll(() async {
      await testSetup.setUp();
    });

    test('withModel starts server and provides client', () async {
      final switcher = ProcessSwitcher();
      try {
        final result = await switcher.withContext(
          LlamaserverSpec(
            llamacppDir: testSetup.llamacppDir,
            config: LlamaserverConfig(modelPath: testSetup.modelFile.path),
          ),
          (context) async {
            final health = await context.client.health();
            return health;
          },
        );
        expect(result, isNotNull);
        expect(result.status, 'ok');
      } finally {
        await switcher.stop();
      }
    });

    test('withModel reuses same process for compatible configs', () async {
      final switcher = ProcessSwitcher();
      try {
        String? firstPort;
        String? secondPort;

        await switcher.withContext(
          LlamaserverSpec(
            llamacppDir: testSetup.llamacppDir,
            config: LlamaserverConfig(modelPath: testSetup.modelFile.path),
          ),
          (client) async {
            firstPort = client.baseUrl.split(':').last;
          },
        );

        await switcher.withContext(
          LlamaserverSpec(
            llamacppDir: testSetup.llamacppDir,
            config: LlamaserverConfig(modelPath: testSetup.modelFile.path),
          ),
          (client) async {
            secondPort = client.baseUrl.split(':').last;
          },
        );

        expect(firstPort, isNotNull);
        expect(secondPort, isNotNull);
        expect(
          firstPort,
          equals(secondPort),
          reason: 'Should reuse same process for compatible configs',
        );
      } finally {
        await switcher.stop();
      }
    });

    test('withModel switches process for incompatible configs', () async {
      final switcher = ProcessSwitcher();
      try {
        String? firstPort;
        String? secondPort;

        await switcher.withContext(
          LlamaserverSpec(
            llamacppDir: testSetup.llamacppDir,
            config: LlamaserverConfig(
              modelPath: testSetup.modelFile.path,
              contextSize: 512,
            ),
          ),
          (client) async {
            firstPort = client.baseUrl.split(':').last;
          },
        );

        await switcher.withContext(
          LlamaserverSpec(
            llamacppDir: testSetup.llamacppDir,
            config: LlamaserverConfig(
              modelPath: testSetup.modelFile.path,
              contextSize: 1024,
            ),
          ),
          (client) async {
            secondPort = client.baseUrl.split(':').last;
          },
        );

        expect(firstPort, isNotNull);
        expect(secondPort, isNotNull);
        expect(
          firstPort,
          isNot(equals(secondPort)),
          reason: 'Should start new process for incompatible configs',
        );
      } finally {
        await switcher.stop();
      }
    });
  });
}
