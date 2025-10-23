import 'package:llamacpp_tools/llamacpp_tools.dart';

class LlamaserverSpecRegistry {
  final LlamacppDir _llamacppDir;
  final _entries = <_Entry>[];

  LlamaserverSpecRegistry({required LlamacppDir llamacppDir})
    : _llamacppDir = llamacppDir;

  void addModelDetectionResult(
    ModelDetectionResult result, {
    List<String>? aliases,
  }) {
    for (final benchmark in result.benchmarks) {
      final entry = _Entry(
        _llamacppDir,
        benchmark.config,
        aliases: aliases,
        sha256: result.fileInfo.sha256,
      );
      _entries.add(entry);
    }
  }

  LlamaserverSpec? selectSpec(String input, {int? contextSize}) {
    contextSize ??= 4096;
    for (final entry in _entries) {
      if (entry.contextSize < contextSize) continue;
      if (entry.accept(input)) {
        return entry.spec;
      }
    }
    return null;
  }
}

class _Entry {
  final String? sha256;
  final List<String>? aliases;
  final LlamaserverConfig config;
  final LlamaserverSpec spec;

  _Entry(
    LlamacppDir dir,
    this.config, {
    required this.aliases,
    required this.sha256,
  }) : spec = LlamaserverSpec(llamacppDir: dir, config: config);

  late final modelPath = config.modelPath!;
  late final contextSize = config.contextSize ?? 4096;
  late final pathLastPart = modelPath
      .split('/')
      .last
      .toLowerCase()
      .replaceFirst(RegExp(r'\.gguf$'), '');

  // Derive base name without quantization (e.g., "qwen2.5-7b-instruct-q4_k_m" → "qwen2.5-7b-instruct")
  late final pathWithoutQuant = pathLastPart.replaceFirst(
    RegExp(r'-q\d+[_k].*$'),
    '',
  );

  bool accept(String input) {
    if (sha256 == input) {
      return true;
    }

    if (aliases != null && aliases!.contains(input)) {
      return true;
    }

    if (pathLastPart == input) {
      return true;
    }

    if (pathWithoutQuant == input) {
      return true;
    }

    return false;
  }
}
