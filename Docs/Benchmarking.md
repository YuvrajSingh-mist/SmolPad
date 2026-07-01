# Benchmarking Strategy

## What We Use

SmolPad needs two different kinds of evaluation:

1. Product regression evaluation
2. Standardized multimodal model evaluation

Those are not the same thing, and mixing them creates misleading results.

### Product Regression Evaluation

Use the existing scripts in `Tools/` for SmolPad-specific handwritten-note behavior:

- image ingestion
- handwriting extraction
- math solving from note snippets
- OpenAI-compatible MLX server compatibility
- latency on the exact local serving stack we ship against

This is what `benchmark_mlx_vision.py` is for.

### Standardized Multimodal Evaluation

Use `lmms-eval` as the primary external benchmark harness.

Why:

- it supports image, video, audio, and text tasks
- it supports 100+ tasks
- it supports OpenAI-compatible endpoints
- it has an async HTTP eval server for production-style workflows
- it is actively maintained and includes recent multimodal model families

Use `VLMEvalKit` as a secondary cross-check when we want very broad benchmark coverage and leaderboard-style comparisons.

## Why Not AIPerf

`AIPerf` is an AI/HPC systems benchmark, not the right harness for product-level VLM/chat evaluation. It is useful for measuring large-scale compute-system performance, but not for checking whether SmolPad correctly understands notes, handles multimodal prompts, or preserves conversational context.

## Recommended Benchmark Ladder

### Layer 1: SmolPad Regression Suite

Run this every time we touch:

- request formatting
- image/message packing
- conversation context
- streaming
- reasoning extraction
- server compatibility

Command:

```bash
bash Tools/run_vision_benchmarks.sh
```

### Layer 2: Standardized LMMS-Eval Suite

Run this to compare models on standard public multimodal tasks:

- `mme`
- `mmmu_val`
- `mathvista`

Command:

```bash
bash Tools/run_lmms_eval_openai.sh
```

This targets an OpenAI-compatible endpoint, so it fits the MLX `/v1/chat/completions` flow we already use.

### Layer 3: Optional VLMEvalKit Cross-Check

Use this when we want:

- wider benchmark breadth
- leaderboard alignment
- a second opinion on model ranking

We should treat this as a complementary suite, not the primary regression gate.

## Production Guidance

For SmolPad release gates, do not rely on one benchmark source only.

Use:

- SmolPad handwritten fixtures for product regressions
- `lmms-eval` for public multimodal quality signals
- runtime logs and payload traces for integration debugging

That combination is much more trustworthy than a single benchmark number.
