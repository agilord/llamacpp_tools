// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detect_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelFileInfo _$ModelFileInfoFromJson(Map<String, dynamic> json) =>
    ModelFileInfo(
      fileSize: (json['fileSize'] as num).toInt(),
      sha256: json['sha256'] as String,
      architecture: json['architecture'] as String?,
      contextLength: (json['contextLength'] as num?)?.toInt(),
      blockCount: (json['blockCount'] as num).toInt(),
      parameterCount: (json['parameterCount'] as num?)?.toInt(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$ModelFileInfoToJson(ModelFileInfo instance) =>
    <String, dynamic>{
      'fileSize': instance.fileSize,
      'sha256': instance.sha256,
      'architecture': ?instance.architecture,
      'contextLength': ?instance.contextLength,
      'blockCount': instance.blockCount,
      'parameterCount': ?instance.parameterCount,
      'metadata': ?instance.metadata,
    };

Benchmark _$BenchmarkFromJson(Map<String, dynamic> json) => Benchmark(
  contextSize: (json['contextSize'] as num).toInt(),
  config: LlamaserverConfig.fromJson(json['config'] as Map<String, dynamic>),
  promptTps: (json['promptTps'] as num).toDouble(),
  generationTps: (json['generationTps'] as num).toDouble(),
);

Map<String, dynamic> _$BenchmarkToJson(Benchmark instance) => <String, dynamic>{
  'contextSize': instance.contextSize,
  'config': instance.config.toJson(),
  'promptTps': instance.promptTps,
  'generationTps': instance.generationTps,
};

ModelDetectionResult _$ModelDetectionResultFromJson(
  Map<String, dynamic> json,
) => ModelDetectionResult(
  fileInfo: ModelFileInfo.fromJson(json['fileInfo'] as Map<String, dynamic>),
  benchmarks: (json['benchmarks'] as List<dynamic>)
      .map((e) => Benchmark.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ModelDetectionResultToJson(
  ModelDetectionResult instance,
) => <String, dynamic>{
  'fileInfo': instance.fileInfo.toJson(),
  'benchmarks': instance.benchmarks.map((e) => e.toJson()).toList(),
};
