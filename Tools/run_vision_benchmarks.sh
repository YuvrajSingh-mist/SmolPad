#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${FIXTURE_DIR:-/tmp/smolpad-vision-fixtures}"
MLX_HOST="${MLX_HOST:-http://192.168.1.8:8080}"
MLX_MODEL="${MLX_MODEL:-mlx-community/Qwen2.5-VL-7B-Instruct-4bit}"
OLLAMA_HOST="${OLLAMA_HOST:-http://192.168.1.8:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-richardyoung/kimi-vl-a3b-thinking:latest}"

echo "Generating handwritten fixtures into ${FIXTURE_DIR}"
swift "${ROOT_DIR}/Tools/MakeVisionFixtures.swift"

echo
echo "Running MLX vision benchmark"
python3 "${ROOT_DIR}/Tools/benchmark_mlx_vision.py" "${MLX_HOST}" "${MLX_MODEL}" "${FIXTURE_DIR}"

echo
echo "Running Ollama vision benchmark"
python3 "${ROOT_DIR}/Tools/benchmark_ollama_vision.py" "${OLLAMA_HOST}" "${OLLAMA_MODEL}" "${FIXTURE_DIR}"
