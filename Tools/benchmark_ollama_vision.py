#!/usr/bin/env python3
"""
SmolPad Kimi-VL-A3B-Thinking Benchmark — Ollama
Compares against Qwen2.5-VL-7B results.
"""
import base64, json, sys, time, urllib.error, urllib.request
from pathlib import Path

HOST = sys.argv[1] if len(sys.argv) > 1 else "http://192.168.1.8:11434"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "richardyoung/kimi-vl-a3b-thinking:latest"
FIXTURE_DIR = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/tmp/smolpad-vision-fixtures")

TESTS = [
    ("calc-derivative-poly",   "calc_derivative_poly-512.png",   "Read and solve step by step.", "12x^3"),
    ("calc-derivative-chain",  "calc_derivative_chain-512.png",  "Read and solve step by step.", "(2x + 3)"),
    ("calc-integral",          "calc_integral-512.png",          "Read and solve step by step.", "14"),
    ("calc-limit",             "calc_limit-512.png",             "Read and solve step by step.", "3"),
    ("calc-partial",           "calc_partial-512.png",           "Read and solve step by step.", "2xy"),
    ("calc-gradient",          "calc_gradient-512.png",          "Read and solve step by step.", "3x^2"),
    ("prob-expectation",       "prob_expectation-512.png",       "Read and solve step by step.", "0.9"),
    ("prob-variance",          "prob_variance-512.png",          "Read and solve step by step.", "9"),
    ("prob-bayes",             "prob_bayes-512.png",             "Read and solve step by step.", "0.475"),
    ("linalg-eigenvalues",     "linalg_eigenvalues-512.png",     "Read and solve step by step.", "lambda"),
    ("linalg-dot",             "linalg_dot-512.png",             "Read and solve step by step.", "8"),
    ("linalg-det",             "linalg_det-512.png",             "Read and solve step by step.", "-2"),
    ("ml-mse-gradient",        "ml_mse_gradient-512.png",        "Read and solve step by step.", "sum"),
    ("ml-softmax",             "ml_softmax-512.png",             "Read and solve step by step.", "0.67"),
    ("ml-cross-entropy",       "ml_cross_entropy-512.png",       "Read and solve step by step.", "0.357"),
    ("rl-bellman",             "rl_bellman-512.png",             "Read and solve step by step.", "14"),
    ("rl-qlearning",           "rl_qlearning-512.png",           "Read and solve step by step.", "6.22"),
    ("rl-policy-gradient",     "rl_policy_gradient-512.png",     "Read and solve step by step.", "3"),
]

# Previous Qwen2.5-VL results for comparison
QWEN_RESULTS = {
    "calc-derivative-poly":   ("CHECK", 6.7, "garbled"),
    "calc-derivative-chain":  ("CHECK", 6.3, "garbled"),
    "calc-integral":          ("CHECK", 7.5, "garbled"),
    "calc-limit":             ("CHECK", 38.7, "gibberish loop"),
    "calc-partial":           ("PASS", 22.3, ""),
    "calc-gradient":          ("PASS", 16.1, ""),
    "prob-expectation":       ("PASS", 22.2, ""),
    "prob-variance":          ("PASS", 13.0, ""),
    "prob-bayes":             ("PASS", 17.5, ""),
    "linalg-eigenvalues":     ("PASS", 33.8, ""),
    "linalg-dot":             ("PASS", 14.5, ""),
    "linalg-det":             ("PASS", 26.1, ""),
    "ml-mse-gradient":        ("PASS", 35.1, ""),
    "ml-softmax":             ("CHECK", 28.1, ""),
    "ml-cross-entropy":       ("PASS", 28.0, ""),
    "rl-bellman":             ("CHECK", 34.3, ""),
    "rl-qlearning":           ("CHECK", 17.4, ""),
    "rl-policy-gradient":     ("PASS", 17.9, ""),
}


def post_json(url, payload, timeout=300):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        # Ollama streams by default; read all lines
        raw = resp.read().decode("utf-8")
        # Parse NDJSON (one JSON per line)
        last = {}
        for line in raw.strip().split("\n"):
            if line.strip():
                last = json.loads(line)
        return last


def run_test(name, image_name, prompt, expected):
    image_path = FIXTURE_DIR / image_name
    if not image_path.exists():
        print(f"SKIP\t{name}\tmissing fixture: {image_path}")
        return None

    encoded = base64.b64encode(image_path.read_bytes()).decode("ascii")

    payload = {
        "model": MODEL,
        "stream": False,
        "messages": [{
            "role": "user",
            "content": prompt,
            "images": [encoded],
        }],
        "options": {
            "temperature": 0,
            "num_ctx": 8192,
            "num_predict": 768,
        },
    }

    started = time.perf_counter()
    try:
        result = post_json(f"{HOST.rstrip('/')}/api/chat", payload)
        elapsed = time.perf_counter() - started
        answer = result.get("message", {}).get("content", "").strip()
        reasoning = result.get("message", {}).get("thinking", "") or ""
        tokens_done = result.get("eval_count", "?")
        tokens_per_sec = result.get("eval_duration", 0) / 1e9
        tps = tokens_done / tokens_per_sec if tokens_per_sec > 0 else 0

        expected_lower = expected.lower()
        answer_lower = answer.lower()
        status = "PASS" if expected_lower in answer_lower else "CHECK"

        qwen = QWEN_RESULTS.get(name, ("?", 0, ""))
        qwen_status, qwen_time = qwen[0], qwen[1]
        delta = elapsed - qwen_time

        print(f"{status}\t{name}\t{elapsed:.1f}s\t(qwen={qwen_status} {qwen_time:.1f}s, Δ={delta:+.1f}s)\ttok={tokens_done} tps={tps:.0f}")
        if reasoning:
            print(f"  [thinking] {reasoning[:200]}...")
        print(f"  [answer]   {answer[:250]}")
        print(f"  [expected] {expected}")
        print()

        return {"name": name, "status": status, "time": elapsed, "tokens": tokens_done, "tps": tps}
    except Exception as exc:
        elapsed = time.perf_counter() - started
        print(f"FAIL\t{name}\t{elapsed:.1f}s\t{exc}")
        print()
        return None


def main():
    print(f"Kimi-VL-A3B-Thinking Benchmark — Ollama")
    print(f"Server: {HOST}  |  Model: {MODEL}")
    print(f"vs. Qwen2.5-VL-7B-Instruct-4bit (MLX-VLM)")
    print(f"Tests: {len(TESTS)}")
    print("=" * 80)

    results = []
    for test in TESTS:
        r = run_test(*test)
        if r:
            results.append(r)

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY: Kimi-VL-A3B-Thinking (Ollama) vs Qwen2.5-VL-7B (MLX-VLM)")
    print("=" * 80)
    passes = sum(1 for r in results if r["status"] == "PASS")
    checks = sum(1 for r in results if r["status"] == "CHECK")
    fails = sum(1 for r in results if r["status"] == "FAIL")
    total_time = sum(r["time"] for r in results)
    avg_time = total_time / len(results) if results else 0

    qwen_total = sum(QWEN_RESULTS.get(r["name"], (0, 0))[1] for r in results)
    qwen_passes = sum(1 for r in results if QWEN_RESULTS.get(r["name"], ("?", 0))[0] == "PASS")

    print(f"Kimi-VL:  {passes} PASS, {checks} CHECK, {fails} FAIL  |  avg {avg_time:.1f}s/test  |  total {total_time:.0f}s")
    print(f"Qwen-VL:  {qwen_passes} PASS, {18 - qwen_passes} CHECK/FAIL  |  avg {qwen_total/18:.1f}s/test  |  total {qwen_total:.0f}s")
    print(f"Speed:    Kimi is {qwen_total/total_time:.1f}x {'faster' if total_time < qwen_total else 'slower'} than Qwen")
    print(f"Accuracy: Kimi {passes}/18 vs Qwen {qwen_passes}/18")


if __name__ == "__main__":
    main()
