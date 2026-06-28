#!/usr/bin/env python3
"""
SmolPad MLX VLM Benchmark — Hard Math & Reasoning
Usage: python3 benchmark_mlx_vision.py [host] [model] [fixture-dir]
"""
import base64, json, sys, time, urllib.error, urllib.request
from pathlib import Path

HOST = sys.argv[1] if len(sys.argv) > 1 else "http://192.168.1.8:8080"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
FIXTURE_DIR = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/tmp/smolpad-vision-fixtures")

TESTS = [
    # Calculus
    ("calc-derivative-poly",   "calc_derivative_poly-512.png",   "Read the equation and find the derivative. Give step-by-step reasoning.", "12x^3"),
    ("calc-derivative-chain",  "calc_derivative_chain-512.png",  "Find the derivative using the chain rule.", "(2x + 3)"),
    ("calc-integral",          "calc_integral-512.png",          "Evaluate the definite integral. Show steps.", "14"),
    ("calc-limit",             "calc_limit-512.png",             "Evaluate the limit.", "3"),
    ("calc-partial",           "calc_partial-512.png",           "Find the partial derivative w.r.t x.", "2xy"),
    ("calc-gradient",          "calc_gradient-512.png",          "Compute the gradient vector.", "3x^2"),

    # Probability
    ("prob-expectation",       "prob_expectation-512.png",       "Compute the expected value.", "0.9"),
    ("prob-variance",          "prob_variance-512.png",          "Compute the variance.", "9"),
    ("prob-bayes",             "prob_bayes-512.png",             "Apply Bayes theorem.", "0.475"),

    # Linear Algebra
    ("linalg-eigenvalues",     "linalg_eigenvalues-512.png",     "Find the eigenvalues.", "lambda"),
    ("linalg-dot",             "linalg_dot-512.png",             "Compute the dot product.", "8"),
    ("linalg-det",             "linalg_det-512.png",             "Compute the determinant.", "-2"),

    # ML
    ("ml-mse-gradient",        "ml_mse_gradient-512.png",        "Find the gradient of the MSE loss.", "sum"),
    ("ml-softmax",             "ml_softmax-512.png",             "Compute softmax probabilities.", "0.67"),
    ("ml-cross-entropy",       "ml_cross_entropy-512.png",       "Compute cross-entropy loss.", "0.357"),

    # RL
    ("rl-bellman",             "rl_bellman-512.png",             "Compute V(0) using the Bellman equation.", "14"),
    ("rl-qlearning",           "rl_qlearning-512.png",           "Update Q using the Q-learning rule.", "6.22"),
    ("rl-policy-gradient",     "rl_policy_gradient-512.png",     "Compute the policy gradient.", "3"),
]


def post_json(url, payload, timeout=300):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def run_test(name, image_name, prompt, expected):
    image_path = FIXTURE_DIR / image_name
    if not image_path.exists():
        print(f"SKIP\t{name}\tmissing fixture: {image_path}")
        return
    encoded = base64.b64encode(image_path.read_bytes()).decode("ascii")

    payload = {
        "model": MODEL,
        "stream": False,
        "temperature": 0,
        "top_p": 0.95,
        "max_tokens": 768,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": (
                    "Read the handwritten note carefully. If it contains math, "
                    "first transcribe the equation exactly as written, then solve "
                    "it step by step with clear reasoning. End with a boxed final answer. "
                    + prompt
                )},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded}"}},
            ],
        }],
    }

    started = time.perf_counter()
    try:
        result = post_json(f"{HOST.rstrip('/')}/v1/chat/completions", payload)
        elapsed = time.perf_counter() - started
        msg = result.get("choices", [{}])[0].get("message", {})
        answer = msg.get("content", "").strip()
        reasoning = msg.get("reasoning", "") or ""
        tokens = result.get("usage", {}).get("total_tokens", "?")

        # Check if expected appears in answer (case-insensitive, partial match)
        expected_lower = expected.lower()
        answer_lower = answer.lower()
        status = "PASS" if expected_lower in answer_lower else "CHECK"

        print(f"{status}\t{name}\t{elapsed:.1f}s\ttok={tokens}")
        if reasoning:
            print(f"  [reasoning] {reasoning[:200]}...")
        print(f"  [answer]    {answer[:300]}")
        print(f"  [expected]  {expected}")
        print()
    except urllib.error.HTTPError as exc:
        elapsed = time.perf_counter() - started
        body = exc.read().decode("utf-8", errors="replace")[:300]
        print(f"FAIL\t{name}\t{elapsed:.1f}s\tHTTP {exc.code}: {body}")
        print()
    except Exception as exc:
        elapsed = time.perf_counter() - started
        print(f"FAIL\t{name}\t{elapsed:.1f}s\t{exc}")
        print()


def main():
    print(f"MLX VLM Benchmark — {MODEL}")
    print(f"Server: {HOST}  |  Thinking: ON  |  Fixtures: {FIXTURE_DIR}")
    print(f"Tests: {len(TESTS)}")
    print("=" * 70)
    passed = 0
    for test in TESTS:
        run_test(*test)
    print(f"Done. (PASS = expected found in answer, CHECK = verify manually)")


if __name__ == "__main__":
    main()
