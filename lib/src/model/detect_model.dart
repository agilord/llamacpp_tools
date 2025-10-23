import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:gguf/gguf.dart';
import 'package:json_annotation/json_annotation.dart';

import '../llamacpp_dir.dart';
import '../llamaserver_process.dart';
import 'package:llamacpp_rpc_client/llamacpp_rpc_client.dart';

part 'detect_model.g.dart';

const _benchmarkPrompts = [
  'What is machine learning and how does it differ from traditional programming?',
  'What are the essential ingredients needed to make pasta from scratch?',
  'How many players are on a basketball team during a game?',
];

/// Model file metadata
@JsonSerializable()
class ModelFileInfo {
  /// File size in bytes
  final int fileSize;

  /// SHA256 hash of the file
  final String sha256;

  /// Model architecture from GGUF metadata
  final String? architecture;

  /// Context length from GGUF metadata
  final int? contextLength;

  /// The block count based on tensor layer names.
  final int blockCount;

  /// Number of parameters in the model.
  final int? parameterCount;

  /// All GGUF metadata key-value pairs
  final Map<String, dynamic>? metadata;

  ModelFileInfo({
    required this.fileSize,
    required this.sha256,
    this.architecture,
    this.contextLength,
    required this.blockCount,
    this.parameterCount,
    this.metadata,
  });

  factory ModelFileInfo.fromJson(Map<String, dynamic> json) =>
      _$ModelFileInfoFromJson(json);

  Map<String, dynamic> toJson() => _$ModelFileInfoToJson(this);
}

/// A benchmark run for the given configuration.
@JsonSerializable()
class Benchmark {
  final int contextSize;
  final LlamaserverConfig config;
  final double promptTps;
  final double generationTps;

  Benchmark({
    required this.contextSize,
    required this.config,
    required this.promptTps,
    required this.generationTps,
  });

  factory Benchmark.fromJson(Map<String, dynamic> json) =>
      _$BenchmarkFromJson(json);

  Map<String, dynamic> toJson() => _$BenchmarkToJson(this);

  late final _score = promptTps + generationTps;
}

/// Complete model detection result
@JsonSerializable()
class ModelDetectionResult {
  /// File metadata
  final ModelFileInfo fileInfo;

  /// Optimal configurations per context size
  final List<Benchmark> benchmarks;

  ModelDetectionResult({required this.fileInfo, required this.benchmarks});

  factory ModelDetectionResult.fromJson(Map<String, dynamic> json) =>
      _$ModelDetectionResultFromJson(json);

  Map<String, dynamic> toJson() => _$ModelDetectionResultToJson(this);
}

final _baseContextSizesInKiB = [4, 8, 16, 24, 32, 48, 64, 96, 128, 192, 256];

/// Wrapper for tensor override patterns with proper equality
class _OverridePattern {
  final List<String> patterns;

  _OverridePattern(this.patterns);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _OverridePattern) return false;
    if (patterns.length != other.patterns.length) return false;
    for (var i = 0; i < patterns.length; i++) {
      if (patterns[i] != other.patterns[i]) return false;
    }
    return true;
  }

  @override
  late final hashCode = Object.hashAll(patterns);
}

/// Predefined tensor override patterns to test for CPU offloading
final _tensorOverridePatterns = [
  _OverridePattern(['ffn_up.*=CPU']),
  _OverridePattern(['ffn_down.*=CPU']),
  _OverridePattern(['ffn_gate.*=CPU']),
  _OverridePattern(['ffn_up.*=CPU', 'ffn_down.*=CPU']),
  _OverridePattern(['ffn_up.*=CPU', 'ffn_gate.*=CPU']),
  _OverridePattern(['attn.*=CPU']),
];

/// Result from generating test configurations
class _ConfigGenResult {
  final List<LlamaserverConfig> configs;
  final int? maxGpuLayers;
  final int? minCpuMoe;
  final Set<_OverridePattern> workingTensorOverrides;

  _ConfigGenResult({
    required this.configs,
    this.maxGpuLayers,
    this.minCpuMoe,
    required this.workingTensorOverrides,
  });
}

/// Class for model detection operations
class ModelDetector {
  final LlamacppDir _llamacppDir;
  final String _modelPath;
  late bool _hasGpu;
  late int _blockCount;

  ModelDetector({required LlamacppDir llamacppDir, required String modelPath})
    : _llamacppDir = llamacppDir,
      _modelPath = modelPath;

  /// Generates test configurations for a given context size
  Future<_ConfigGenResult> _generateTestConfigs({
    required int contextSize,
    int? startMaxGpuLayers,
    int? startMinCpuMoe,
    Set<_OverridePattern>? workingTensorOverrides,
  }) async {
    final configs = <LlamaserverConfig>[];
    int? foundMaxGpuLayers;
    int? foundMinCpuMoe;
    final foundWorkingOverrides = <_OverridePattern>{};

    // Determine which tensor override patterns to test
    final patternsToTest = workingTensorOverrides ?? _tensorOverridePatterns;

    for (final flashAttn in [FlashAttention.on, FlashAttention.off]) {
      if (!_hasGpu) {
        // CPU only: test with and without flash attention
        configs.add(
          LlamaserverConfig(
            contextSize: contextSize,
            gpuLayers: null,
            flashAttention: flashAttn,
          ),
        );
      } else {
        // Test if model fits entirely in VRAM
        final config = LlamaserverConfig(
          contextSize: contextSize,
          gpuLayers: 999,
          flashAttention: flashAttn,
        );
        final result = await _testConfig(config);
        if (result != null) {
          configs.add(config);
        } else {
          // Model doesn't fit in VRAM, try different strategies

          // Find optimal --gpu-layers
          final maxGpuLayers = await _findMaxGpuLayers(
            contextSize: contextSize,
            flashAttention: flashAttn,
            startValue: startMaxGpuLayers,
          );

          // Track the maximum of GPU layers found across flash attention modes
          if (foundMaxGpuLayers == null || maxGpuLayers > foundMaxGpuLayers) {
            foundMaxGpuLayers = maxGpuLayers;
          }

          configs.add(
            LlamaserverConfig(
              contextSize: contextSize,
              gpuLayers: maxGpuLayers > 0 ? maxGpuLayers : null,
              flashAttention: flashAttn,
            ),
          );

          // All layers to GPU + --n-cpu-moe
          final minCpuMoe = await _findMinCpuMoe(
            contextSize: contextSize,
            flashAttention: flashAttn,
            startValue: startMinCpuMoe,
          );

          if (minCpuMoe != null) {
            // Track the minimum of CPU MoE found across flash attention modes
            if (foundMinCpuMoe == null || minCpuMoe < foundMinCpuMoe) {
              foundMinCpuMoe = minCpuMoe;
            }

            configs.add(
              LlamaserverConfig(
                contextSize: contextSize,
                gpuLayers: 999,
                flashAttention: flashAttn,
                nCpuMoe: minCpuMoe,
              ),
            );
          }

          // All layers to GPU + override-tensors
          for (final pattern in patternsToTest) {
            final overrideConfig = LlamaserverConfig(
              contextSize: contextSize,
              gpuLayers: 999,
              flashAttention: flashAttn,
              overrideTensors: pattern.patterns,
            );
            configs.add(overrideConfig);

            // Test this config to see if it works
            final overrideResult = await _testConfig(overrideConfig);
            if (overrideResult != null) {
              foundWorkingOverrides.add(pattern);
            }
          }
        }
      }
    }

    return _ConfigGenResult(
      configs: configs,
      maxGpuLayers: foundMaxGpuLayers,
      minCpuMoe: foundMinCpuMoe,
      workingTensorOverrides: foundWorkingOverrides,
    );
  }

  /// Generic binary search for optimal configuration value
  Future<int?> _binarySearchConfig({
    required int left,
    required int right,
    required LlamaserverConfig Function(int value) configBuilder,
    required bool maximize,
    int? initialValue,
  }) async {
    // Test initial value if provided (for early exit)
    if (initialValue != null) {
      final testConfig = configBuilder(initialValue);
      final testResult = await _benchmarkConfig(config: testConfig);
      if (testResult == null) {
        return null;
      }
    }

    int? optimalValue = initialValue;
    int searchLeft = left;
    int searchRight = right;

    while (searchLeft <= searchRight) {
      final mid = (searchLeft + searchRight) ~/ 2;

      final config = configBuilder(mid);
      final result = await _benchmarkConfig(config: config);

      if (result != null) {
        optimalValue = mid;
        if (maximize) {
          searchLeft = mid + 1;
        } else {
          searchRight = mid - 1;
        }
      } else {
        if (maximize) {
          searchRight = mid - 1;
        } else {
          searchLeft = mid + 1;
        }
      }
    }

    return optimalValue;
  }

  /// Finds the maximum GPU layers that work
  Future<int> _findMaxGpuLayers({
    required int contextSize,
    required FlashAttention flashAttention,
    int? startValue,
  }) async {
    // If we have a hint from previous context size, start search from there
    final searchRight = startValue ?? min(999, _blockCount);

    return await _binarySearchConfig(
          left: 0,
          right: searchRight,
          configBuilder: (gpuLayers) => LlamaserverConfig(
            contextSize: contextSize,
            gpuLayers: gpuLayers > 0 ? gpuLayers : null,
            flashAttention: flashAttention,
          ),
          maximize: true,
        ) ??
        0;
  }

  /// Finds the minimum CPU MoE count that works
  Future<int?> _findMinCpuMoe({
    required int contextSize,
    required FlashAttention flashAttention,
    int? startValue,
  }) async {
    // If we have a hint from previous context size, use it as initial value
    final initialValue = startValue ?? _blockCount;

    return await _binarySearchConfig(
      left: 0,
      right: _blockCount,
      configBuilder: (nCpuMoe) => LlamaserverConfig(
        contextSize: contextSize,
        gpuLayers: 999,
        flashAttention: flashAttention,
        nCpuMoe: nCpuMoe,
      ),
      maximize: false,
      initialValue: initialValue,
    );
  }

  /// Tests a configuration and returns the result, or null if failed
  Future<Benchmark?> _testConfig(LlamaserverConfig config) async {
    final result = await _benchmarkConfig(config: config);
    return result;
  }

  /// Benchmarks a specific configuration
  Future<Benchmark?> _benchmarkConfig({
    required LlamaserverConfig config,
  }) async {
    LlamaserverProcess? process;

    try {
      // Start server with config
      process = LlamaserverProcess(
        dir: _llamacppDir,
        config: config.replace(modelPath: _modelPath),
        logWriter: (_) {},
      );

      await process.start().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Server start timeout'),
      );

      final baseUrl = 'http://localhost:${process.port}';
      final client = LlamacppRpcClient(baseUrl);

      try {
        // Run all benchmark prompts in sequence
        final promptSpeeds = <double>[];
        final generationSpeeds = <double>[];

        for (final prompt in _benchmarkPrompts) {
          final response = await client
              .completion(prompt, options: CompletionOptions(maxTokens: 20))
              .timeout(
                const Duration(seconds: 120),
                onTimeout: () => throw TimeoutException('Completion timeout'),
              );

          final timings = response.timings;
          if (timings == null) {
            throw Exception('No timings in response');
          }

          promptSpeeds.add(timings.promptPerSecond);
          generationSpeeds.add(timings.predictedPerSecond);
        }

        client.close();

        // Calculate average speeds
        final avgPromptSpeed =
            promptSpeeds.reduce((a, b) => a + b) / promptSpeeds.length;
        final avgGenerationSpeed =
            generationSpeeds.reduce((a, b) => a + b) / generationSpeeds.length;

        return Benchmark(
          contextSize: config.contextSize!,
          config: config,
          promptTps: avgPromptSpeed,
          generationTps: avgGenerationSpeed,
        );
      } catch (e) {
        client.close();
        rethrow;
      }
    } catch (e) {
      return null;
    } finally {
      await process?.stop(force: true);
    }
  }

  /// Reads model file info including hash and GGUF metadata
  Future<ModelFileInfo> _readModelFileInfo() async {
    final file = File(_modelPath);

    if (!await file.exists()) {
      throw ArgumentError('Model file not found: $_modelPath');
    }

    final fileSize = await file.length();

    // Calculate SHA256 hash using streaming
    final sha256Hash = sha256;
    final stream = file.openRead();
    final digest = await sha256Hash.bind(stream).first;
    final hash = digest.toString();

    // Read GGUF metadata
    final ggufFile = await parseGgufFile(_modelPath);

    // Extract metadata
    final metadata = <String, dynamic>{};
    for (final entry in ggufFile.metadata.entries) {
      final key = entry.key;
      final encoded = json.encode(entry.value);
      final length = encoded.length;
      if (length > 200 && key != 'tokenizer.chat_template') {
        continue;
      }
      metadata[key] = entry.value;
    }

    // Extract specific fields
    final architecture = metadata['general.architecture'] as String?;
    final contextLength = metadata['$architecture.context_length'] as int?;

    // Try to estimate parameter count from tensors
    int? parameterCount;
    try {
      parameterCount = ggufFile.tensors.fold<int>(0, (sum, t) {
        final size = t.dimensions.reduce((a, b) => a * b);
        return sum + size;
      });
    } catch (_) {
      parameterCount = null;
    }

    return ModelFileInfo(
      fileSize: fileSize,
      sha256: hash,
      architecture: architecture,
      contextLength: contextLength,
      blockCount: ggufFile.layerBlocksCount,
      parameterCount: parameterCount,
      metadata: metadata,
    );
  }

  /// Checks if GPU support is available
  Future<bool> _hasGpuSupport() async {
    try {
      final output = await _llamacppDir.llamacliFullVersionOutput;
      return output.contains('CUDA');
    } catch (_) {
      return false;
    }
  }

  /// Finds optimal configs for all context sizes
  Future<ModelDetectionResult> detect() async {
    // Read file info and GGUF metadata
    final fileInfo = await _readModelFileInfo();
    _blockCount = fileInfo.blockCount;

    // Detect GPU support once at the beginning
    _hasGpu = await _hasGpuSupport();

    final maxContext = fileInfo.contextLength ?? 128 * 1024;
    final contextSizes = _baseContextSizesInKiB
        .map((s) => s * 1024)
        .where((size) => size <= maxContext)
        .toList();

    final optimalConfigs = <Benchmark>[];

    // Track working limits from previous context size
    // As context grows, max GPU layers can only decrease and min CPU MoE can only increase
    int? maxWorkingGpuLayers;
    int? minWorkingCpuMoe;
    Set<_OverridePattern>? workingTensorOverrides;

    for (final contextSize in contextSizes) {
      final searchResults = await _generateTestConfigs(
        contextSize: contextSize,
        startMaxGpuLayers: maxWorkingGpuLayers,
        startMinCpuMoe: minWorkingCpuMoe,
        workingTensorOverrides: workingTensorOverrides,
      );

      final results = <Benchmark>[];
      for (final config in searchResults.configs) {
        final result = await _testConfig(config);
        if (result != null) results.add(result);
      }

      // Find best result for this context size
      if (results.isNotEmpty) {
        results.sort((a, b) => -a._score.compareTo(b._score));
        optimalConfigs.add(results.first);
      }

      // Update working limits for next context size from search results
      if (searchResults.maxGpuLayers != null) {
        maxWorkingGpuLayers = searchResults.maxGpuLayers;
      }
      if (searchResults.minCpuMoe != null) {
        minWorkingCpuMoe = searchResults.minCpuMoe;
      }
      if (searchResults.workingTensorOverrides.isNotEmpty) {
        workingTensorOverrides = searchResults.workingTensorOverrides;
      }
    }

    return ModelDetectionResult(fileInfo: fileInfo, benchmarks: optimalConfigs);
  }
}
