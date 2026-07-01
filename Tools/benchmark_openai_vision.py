#!/usr/bin/env python3
"""
Compatibility wrapper.

This file used to contain the MLX/OpenAI-compatible benchmark payload directly.
The canonical script is now `benchmark_mlx_vision.py`, which matches the actual
server being benchmarked in SmolPad today.
"""
from benchmark_mlx_vision import main


if __name__ == "__main__":
    main()
