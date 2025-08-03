#!/bin/bash

# Script to generate all generated files and format the code
set -e

echo "Generating Dart files from Docker files..."

# Run the Dockerfile generator
dart run lib/src/dockerfile_utils.dart

echo "Formatting Dart code..."

# Format all Dart files
dart format .

echo "File generation and formatting completed successfully!"