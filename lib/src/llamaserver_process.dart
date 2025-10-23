import 'dart:io';
import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:process_visor/process_visor.dart';

import 'llamacpp_dir.dart';

part 'llamaserver_process.g.dart';

/// Configuration for a llama.cpp server process.
@JsonSerializable()
class LlamaserverConfig {
  /// The host address to bind the server to. Defaults to '0.0.0.0'.
  final String? host;

  /// The port number to bind the server to. If null, a free port is auto-detected.
  final int? port;

  /// Path to the model file to load.
  final String? modelPath;

  /// Number of threads to use for processing. Defaults to system optimal.
  final int? threads;

  /// Context size in tokens. Determines the maximum input/output length.
  final int? contextSize;

  /// Whether to enable embeddings endpoint.
  final bool? embeddings;

  /// The value of the flash attention option.
  final FlashAttention? flashAttention;

  /// Whether to lock the model in memory to prevent swapping.
  final bool? mlock;

  /// Number of layers to offload to GPU for acceleration.
  final int? gpuLayers;

  /// Number of MoE experts to keep on CPU (--n-cpu-moe).
  final int? nCpuMoe;

  /// Tensor override patterns for selective CPU offloading (--override-tensors).
  /// Each pattern is in the format "name=CPU" (e.g., "ffn_up.*=CPU").
  final List<String>? overrideTensors;

  /// Additional command line arguments to pass to the server.
  final List<String>? args;

  /// Creates a new server configuration.
  LlamaserverConfig({
    String? host,
    int? port,
    String? modelPath,
    this.threads,
    this.contextSize,
    this.embeddings,
    FlashAttention? flashAttention,
    this.mlock,
    this.gpuLayers,
    this.nCpuMoe,
    this.overrideTensors,
    this.args,
  }) : host = host != null && host.isNotEmpty ? host : null,
       port = (port ?? 0) == 0 ? null : port,
       modelPath = modelPath != null && modelPath.isNotEmpty ? modelPath : null,
       flashAttention =
           (flashAttention ?? FlashAttention.auto) == FlashAttention.auto
           ? null
           : flashAttention;

  /// Creates a configuration from JSON data.
  factory LlamaserverConfig.fromJson(Map<String, dynamic> json) =>
      _$LlamaserverConfigFromJson(json);

  // Creates a new config instance with updated values (if specified).
  LlamaserverConfig replace({
    String? host,
    int? port,
    String? modelPath,
    FlashAttention? flashAttention,
    bool? mlock,
    int? gpuLayers,
    int? nCpuMoe,
    List<String>? overrideTensors,
  }) {
    return LlamaserverConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      modelPath: modelPath ?? this.modelPath,
      threads: threads,
      contextSize: contextSize,
      embeddings: embeddings,
      flashAttention: flashAttention ?? this.flashAttention,
      mlock: mlock ?? this.mlock,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      nCpuMoe: nCpuMoe ?? this.nCpuMoe,
      overrideTensors: overrideTensors ?? this.overrideTensors,
      args: args,
    );
  }

  /// Converts the configuration to JSON data.
  Map<String, dynamic> toJson() => _$LlamaserverConfigToJson(this);
}

enum FlashAttention { on, off, auto }

extension PrivateLlamaserverConfigExt on LlamaserverConfig {
  int get _contextSizeOr4096 => contextSize ?? 4096;
  FlashAttention get _flashAttentionOrAuto =>
      flashAttention ?? FlashAttention.auto;
  bool get _embeddingsOrFalse => embeddings ?? false;
  int get _gpuLayersOr0 => gpuLayers ?? 0;
  int get _nCpuMoeOr0 => nCpuMoe ?? 0;

  bool accept(LlamaserverConfig other) {
    if (this == other) return true;
    if (modelPath != other.modelPath) {
      return false;
    }
    if (_contextSizeOr4096 < other._contextSizeOr4096) {
      return false;
    }
    if (_flashAttentionOrAuto != other._flashAttentionOrAuto) {
      return false;
    }
    if (_embeddingsOrFalse != other._embeddingsOrFalse) {
      return false;
    }
    if (_gpuLayersOr0 < other._gpuLayersOr0) {
      return false;
    }
    if (gpuLayers == null && other.gpuLayers != null) {
      return false;
    }
    if (_nCpuMoeOr0 > other._nCpuMoeOr0) {
      return false;
    }
    if (_differs(overrideTensors, other.overrideTensors)) {
      return false;
    }
    if (_differs(args, other.args)) {
      return false;
    }
    return true;
  }
}

bool _differs(List<String>? a, List<String>? b) {
  a ??= const <String>[];
  b ??= const <String>[];
  if (a.length != b.length) {
    return true;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return true;
    }
  }
  return false;
}

/// Manages a llama.cpp server process lifecycle.
///
/// Handles starting, stopping, and monitoring a llama-server process with
/// the specified configuration. Automatically detects free ports and monitors
/// server startup status.
class LlamaserverProcess {
  final LlamacppDir _dir;
  final LogWriter? _logWriter;
  final LlamaserverConfig _config;

  ProcessVisor? _visor;
  int? _actualPort;

  /// Creates a new server process manager.
  ///
  /// [dir] specifies the llama.cpp installation directory.
  /// [config] contains the server configuration.
  /// [logWriter] optionally handles process output logging.
  LlamaserverProcess({
    required LlamacppDir dir,
    required LlamaserverConfig config,
    LogWriter? logWriter,
  }) : _dir = dir,
       _config = config,
       _logWriter = logWriter;

  /// The actual port the server is bound to, or null if not started.
  int? get port => _actualPort;

  /// The current status of the server process.
  ProcessStatus get status => _visor?.status ?? ProcessStatus.absent;

  /// Starts the llama-server process.
  ///
  /// Builds the command line arguments from the configuration and launches
  /// the server. Waits for the server to be ready before returning.
  /// Does nothing if the server is already started.
  Future<void> start() async {
    if (_visor != null) {
      return;
    }
    final serverPath = await _dir.getServerPath();
    if (serverPath == null) {
      throw StateError('llama-server not found in ${_dir.rootPath}');
    }

    if (_config.modelPath == null) {
      throw ArgumentError('`modelPath` must be specified.');
    }

    List<String>? flashAttentionParams;
    if (_config.flashAttention != null) {
      final effectiveFlashAttention =
          _config.flashAttention ?? FlashAttention.auto;
      final cliHelp = await _dir.llamacliFullHelpOutput;
      final useEnumFlashAttention = cliHelp.contains(
        ' --flash-attn [on|off|auto]',
      );
      if (useEnumFlashAttention) {
        flashAttentionParams = ['--flash-attn', _config.flashAttention!.name];
      } else {
        if (effectiveFlashAttention == FlashAttention.on) {
          flashAttentionParams = ['--flash-attn'];
        }
      }
    }

    final host = _config.host ?? '0.0.0.0';
    final configPort = _config.port;
    _actualPort = configPort != null && configPort > 0
        ? configPort
        : await _detectFreePort();

    final visor = _visor = ProcessVisor(
      args: [
        serverPath,
        '--host',
        host,
        '--port',
        _actualPort.toString(),
        '--model',
        _config.modelPath!,
        if (_config.threads != null) ...['--threads', '${_config.threads}'],
        if (_config.contextSize != null) ...[
          '--ctx-size',
          '${_config.contextSize}',
        ],
        ...?flashAttentionParams,
        if (_config.embeddings ?? false) '--embeddings',
        if (_config.mlock ?? false) '--mlock',
        if (_config.gpuLayers != null) ...[
          '--gpu-layers',
          '${_config.gpuLayers}',
        ],
        if (_config.nCpuMoe != null) ...['--n-cpu-moe', '${_config.nCpuMoe}'],
        if (_config.overrideTensors != null)
          for (final pattern in _config.overrideTensors!) ...[
            '--override-tensors',
            pattern,
          ],
        ...?_config.args,
      ],
      logWriter:
          _logWriter ??
          (e) => print('[${e.pid}]${e.isError ? 'ERROR:' : ''}${e.text}'),
      startIndicator: (e) {
        return e.text.contains(
          'main: server is listening on http://$host:$port - starting the main loop',
        );
      },
      workingDirectory: p.dirname(serverPath),
    );

    await visor.start();
    await visor.started;
  }

  /// Stops the llama-server process.
  ///
  /// Gracefully shuts down the server process and cleans up resources.
  /// Does nothing if the server is not running.
  Future<void> stop({bool force = false}) async {
    if (_visor != null) {
      await _visor!.stop(force: force);
      _visor = null;
    }
    _actualPort = null;
  }

  /// Restarts the llama-server process.
  ///
  /// Equivalent to calling [stop] followed by [start].
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<int> _detectFreePort() async {
    final serverSocket = await ServerSocket.bind('127.0.0.1', 0);
    final port = serverSocket.port;
    await serverSocket.close();
    return port;
  }
}
