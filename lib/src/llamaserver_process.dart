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
  final String modelPath;

  /// Number of threads to use for processing. Defaults to system optimal.
  final int? threads;

  /// Context size in tokens. Determines the maximum input/output length.
  final int? contextSize;

  /// Whether to enable embeddings endpoint.
  final bool? embeddings;

  /// Whether to enable flash attention optimization.
  final bool? flashAttention;

  /// Whether to lock the model in memory to prevent swapping.
  final bool? mlock;

  /// Number of layers to offload to GPU for acceleration.
  final int? gpuLayers;

  /// Additional command line arguments to pass to the server.
  final List<String>? args;

  /// Creates a new server configuration.
  LlamaserverConfig({
    this.host,
    this.port,
    required this.modelPath,
    this.threads,
    this.contextSize,
    this.embeddings,
    this.flashAttention,
    this.mlock,
    this.gpuLayers,
    this.args,
  });

  /// Creates a configuration from JSON data.
  factory LlamaserverConfig.fromJson(Map<String, dynamic> json) =>
      _$LlamaserverConfigFromJson(json);

  // Creates a new config instance with updated values (if specified).
  LlamaserverConfig replace({
    String? host,
    int? port,
    bool? flashAttention,
    bool? mlock,
    int? gpuLayers,
  }) {
    return LlamaserverConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      modelPath: modelPath,
      threads: threads,
      contextSize: contextSize,
      embeddings: embeddings,
      flashAttention: flashAttention ?? this.flashAttention,
      mlock: mlock ?? this.mlock,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      args: args,
    );
  }

  /// Converts the configuration to JSON data.
  Map<String, dynamic> toJson() => _$LlamaserverConfigToJson(this);
}

extension PrivateLlamaserverConfigExt on LlamaserverConfig {
  bool accept(LlamaserverConfig other) {
    if (this == other) return true;
    if (modelPath != other.modelPath) {
      return false;
    }
    if ((contextSize ?? 4096) < (other.contextSize ?? 4096)) {
      return false;
    }
    if ((flashAttention ?? false) != (other.flashAttention ?? false)) {
      return false;
    }
    if ((embeddings ?? false) != (other.embeddings ?? false)) {
      return false;
    }
    if ((gpuLayers ?? 0) < (other.gpuLayers ?? 0)) {
      return false;
    }
    if (gpuLayers == null && other.gpuLayers != null) {
      return false;
    }
    final args1 = args ?? const <String>[];
    final args2 = other.args ?? const <String>[];
    if (args1.length != args2.length) {
      return false;
    }
    for (var i = 0; i < args1.length; i++) {
      if (args1[i] != args2[i]) {
        return false;
      }
    }
    return true;
  }
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
        _config.modelPath,
        if (_config.threads != null) ...['--threads', '${_config.threads}'],
        if (_config.contextSize != null) ...[
          '--ctx-size',
          '${_config.contextSize}',
        ],
        if (_config.flashAttention ?? false) '--flash-attn',
        if (_config.embeddings ?? false) '--embeddings',
        if (_config.mlock ?? false) '--mlock',
        if (_config.gpuLayers != null) ...[
          '--gpu-layers',
          '${_config.gpuLayers}',
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
