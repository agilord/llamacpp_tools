Dart package and CLI tool for managing llama.cpp local setup (detecting, downloading, building, running).

## Features

- **Directory detection**: Detect existing llama.cpp installations and get version info
- **GitHub integration**: Scrape recent versions and download/setup releases from GitHub
- **Docker building**: Build llama.cpp with CUDA support using containerized environments
- **Process management**: Manages `llama-server` processes with configuration, lifecycle control, and monitoring

## Usage

### GitHub Operations
```bash
# List recent versions from GitHub
dart run llamacpp_tools github scrape-recent-versions

# Download and setup a specific release
dart run llamacpp_tools github setup-release --version 3875 --target ./llama-cpp
```

### Docker Building  
```bash
# List available builders
dart run llamacpp_tools docker list-builders

# Build a container
dart run llamacpp_tools docker build-builder --builder cuda-builder --container llama-cuda

# Run container to build llama.cpp
dart run llamacpp_tools docker run-builder --container llama-cuda --version 3875 --output ./output
```

### Process Management
```dart
import 'package:llamacpp_tools/llamacpp_tools.dart';

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
```
