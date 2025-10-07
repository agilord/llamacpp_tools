import 'package:llamacpp_tools/llamacpp_tools.dart';

Future<void> main() async {
  // Configure and start a server
  final config = LlamaserverConfig(
    modelPath: '/path/to/model.gguf',
    port: 8080,
    threads: 4,
  );

  final process = LlamaserverProcess(
    dir: (await LlamacppDir.detect('/path/to/llama-cpp'))!,
    config: config,
  );

  await process.start();
  print('Server running on port ${process.port}');
}
