# Vision Benchmarks

## Canonical Scripts

- `benchmark_mlx_vision.py`: benchmark for the OpenAI-compatible MLX `/v1/chat/completions` server used by SmolPad.
- `benchmark_ollama_vision.py`: benchmark for the Ollama vision server.
- `benchmark_openai_vision.py`: compatibility wrapper that forwards to `benchmark_mlx_vision.py`.
- `MakeVisionFixtures.swift`: generates handwritten note fixtures into `/tmp/smolpad-vision-fixtures`.
- `run_vision_benchmarks.sh`: generates fixtures, then runs MLX and Ollama benchmarks back to back.
- `run_lmms_eval_openai.sh`: runs `lmms-eval` against an OpenAI-compatible endpoint such as the MLX server.

## Recommended Usage

Use two layers of benchmarking:

- `run_vision_benchmarks.sh` for SmolPad-specific handwritten-note regressions
- `run_lmms_eval_openai.sh` for standardized multimodal benchmarks like `MME`, `MMMU`, and `MathVista`

More detail lives in [Docs/Benchmarking.md](/Users/yuvrajsingh9886/Desktop/SmolPad/Docs/Benchmarking.md).

## Quick Local Run

```bash
bash Tools/run_vision_benchmarks.sh
```

## Override Hosts and Models

```bash
MLX_HOST=http://192.168.1.8:8080 \
MLX_MODEL=mlx-community/Qwen2.5-VL-7B-Instruct-4bit \
OLLAMA_HOST=http://192.168.1.8:11434 \
OLLAMA_MODEL=richardyoung/kimi-vl-a3b-thinking:latest \
bash Tools/run_vision_benchmarks.sh
```

## LMMS-Eval on MLX

```bash
LMMS_BASE_URL=http://192.168.1.8:8080/v1 \
LMMS_MODEL=mlx-community/Qwen2.5-VL-7B-Instruct-4bit \
LMMS_TASKS=mme,mmmu_val,mathvista \
bash Tools/run_lmms_eval_openai.sh
```
