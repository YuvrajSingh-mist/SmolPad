#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LMMS_PYTHON="${LMMS_PYTHON:-python3}"
LMMS_MODEL_TYPE="${LMMS_MODEL_TYPE:-openai}"
LMMS_MODEL="${LMMS_MODEL:-mlx-community/Qwen2.5-VL-7B-Instruct-4bit}"
LMMS_BASE_URL="${LMMS_BASE_URL:-http://192.168.1.8:8080/v1}"
LMMS_API_KEY="${LMMS_API_KEY:-EMPTY}"
LMMS_TASKS="${LMMS_TASKS:-mme,mmmu_val,mathvista}"
LMMS_BATCH_SIZE="${LMMS_BATCH_SIZE:-1}"
LMMS_LIMIT="${LMMS_LIMIT:-}"
LMMS_OUTPUT_PATH="${LMMS_OUTPUT_PATH:-${ROOT_DIR}/.benchmark-results/lmms-eval}"

mkdir -p "${LMMS_OUTPUT_PATH}"

if ! "${LMMS_PYTHON}" -c 'import lmms_eval' >/dev/null 2>&1; then
  cat <<'EOF'
lmms-eval is not installed in the current Python environment.

Install it with one of:
  uv pip install lmms-eval
  python3 -m pip install lmms-eval

Then re-run:
  bash Tools/run_lmms_eval_openai.sh
EOF
  exit 1
fi

export OPENAI_API_KEY="${LMMS_API_KEY}"

MODEL_ARGS="model=${LMMS_MODEL},base_url=${LMMS_BASE_URL},api_key=${LMMS_API_KEY}"

CMD=(
  "${LMMS_PYTHON}" -m lmms_eval
  --model "${LMMS_MODEL_TYPE}"
  --model_args "${MODEL_ARGS}"
  --tasks "${LMMS_TASKS}"
  --batch_size "${LMMS_BATCH_SIZE}"
  --output_path "${LMMS_OUTPUT_PATH}"
)

if [[ -n "${LMMS_LIMIT}" ]]; then
  CMD+=(--limit "${LMMS_LIMIT}")
fi

echo "Running lmms-eval against OpenAI-compatible endpoint"
echo "Model:      ${LMMS_MODEL}"
echo "Base URL:   ${LMMS_BASE_URL}"
echo "Tasks:      ${LMMS_TASKS}"
echo "Batch size: ${LMMS_BATCH_SIZE}"
echo "Output:     ${LMMS_OUTPUT_PATH}"
echo

"${CMD[@]}"
