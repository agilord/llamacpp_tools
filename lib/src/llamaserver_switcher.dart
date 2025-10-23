import 'dart:async';

import 'package:llamacpp_rpc_client/llamacpp_rpc_client.dart';
import 'package:llamacpp_tools/src/llamaserver_process.dart';
import 'package:process_visor/process_switcher.dart';

import 'llamacpp_dir.dart';

/// Gives access to a llama-server process with base URL and RPC client.
class LlamaserverContext extends ProcessContext {
  final LlamaserverProcess _process;

  LlamaserverContext._(this._process, {required super.concurrency});

  late final baseUrl = 'http://localhost:${_process.port}';

  late final client = LlamacppRpcClient(baseUrl);

  @override
  Future<void> close({bool force = false}) async {
    await _process.stop(force: force);
    client.close();
  }
}

/// Specifies a llama-server process for [ProcessSwitcher].
class LlamaserverSpec extends ProcessSpec<LlamaserverContext> {
  final LlamacppDir _llamacppDir;
  final LlamaserverConfig _config;

  LlamaserverSpec({
    required LlamacppDir llamacppDir,
    required LlamaserverConfig config,
  }) : _llamacppDir = llamacppDir,
       _config = config;

  late final _hasCuda = () async {
    return (await _llamacppDir.llamacliFullVersionOutput).contains(
      'loaded CUDA backend',
    );
  }();

  @override
  bool accept(ProcessSpec pending) {
    if (pending is! LlamaserverSpec) {
      return false;
    }
    if (pending._llamacppDir.rootPath != _llamacppDir.rootPath) {
      return false;
    }
    return _config.accept(pending._config);
  }

  @override
  Future<LlamaserverContext> start() async {
    var config = _config;
    if (await _hasCuda && config.gpuLayers == null) {
      config = config.replace(gpuLayers: 999);
    }

    final process = LlamaserverProcess(
      dir: _llamacppDir,
      config: config.replace(host: '0.0.0.0', port: 0),
      logWriter: (_) {},
    );
    await process.start();

    return LlamaserverContext._(process, concurrency: 1);
  }
}

extension PrivateLlamaserverSpecExt on LlamaserverSpec {
  LlamaserverConfig get config => _config;
}
