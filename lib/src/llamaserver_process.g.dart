// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llamaserver_process.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlamaserverConfig _$LlamaserverConfigFromJson(Map<String, dynamic> json) =>
    LlamaserverConfig(
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt(),
      modelPath: json['modelPath'] as String,
      threads: (json['threads'] as num?)?.toInt(),
      contextSize: (json['contextSize'] as num?)?.toInt(),
      embeddings: json['embeddings'] as bool?,
      flashAttention: json['flashAttention'] as bool?,
      mlock: json['mlock'] as bool?,
      gpuLayers: (json['gpuLayers'] as num?)?.toInt(),
      args: (json['args'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$LlamaserverConfigToJson(LlamaserverConfig instance) =>
    <String, dynamic>{
      'host': ?instance.host,
      'port': ?instance.port,
      'modelPath': instance.modelPath,
      'threads': ?instance.threads,
      'contextSize': ?instance.contextSize,
      'embeddings': ?instance.embeddings,
      'flashAttention': ?instance.flashAttention,
      'mlock': ?instance.mlock,
      'gpuLayers': ?instance.gpuLayers,
      'args': ?instance.args,
    };
