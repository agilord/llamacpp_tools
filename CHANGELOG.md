# Changelog

## 0.3.0

**Breaking changes:**
- `LlamaserverConfig.flashAttention` is now an enum `FlashAttention`.

**New feature:**
- `LlamaserverSpec` to support `ProcessSwitcher` (see `package:process_visor`) + lookup from `LlamaserverSpecRegistry` (to implement an alternative `llama-swap`).
- Supports detecting optimal parameters for models not fitting into VRAM (CLI or `ModelDetector`).

## 0.2.0

**Breaking changes:**
- Github methods are moved into the `LlamacppGithub` class and renamed.
- Docker-builder methods are moved into the `LlamacppDocker` class and renamed.

## 0.1.2

- Improved CUDA build (copying runtime libraries).
- Small improvements in `LlamacppDir` and the server process.

## 0.1.1

- Added support for running the `llama-server` process.

## 0.1.0

- Inital release with downloading from GitHub and building CUDA-support with docker.
