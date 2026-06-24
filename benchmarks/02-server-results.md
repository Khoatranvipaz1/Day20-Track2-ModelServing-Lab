# 02 — llama-server Load Test Results

Server: `python -m llama_cpp.server` (llama-cpp-python 0.3.31, CUDA backend)
Model: `qwen2.5-1.5b-instruct-q4_k_m.gguf`
Hardware: GTX 1650 Ti 4 GB VRAM, 8 GB RAM, AMD64 12-core CPU

## Locust headless runs

```
locust -f 02-llama-cpp-server/load-test.py --headless -u <N> -r 1 -t 60s --host http://localhost:8080
```

### Concurrency 10 (u=10, r=1, t=60s)

```
Type     Name                  # reqs  # fails |   Avg    Min    Max    Med | req/s
---------|---------------------|-------|--------|--------|------|------|------|------
POST     short                     12  0(0.00%)| 27309   7094  45211  26000 |  0.21
---------|---------------------|-------|--------|--------|------|------|------|------
         Aggregated                12  0(0.00%)| 27309   7094  45211  26000 |  0.21

Response time percentiles (ms)
  50%=29000  66%=32000  75%=40000  80%=40000  90%=44000  95%=45000  99%=45000
```

### Concurrency 50 (u=50, r=5, t=60s)

```
Type     Name                  # reqs  # fails |   Avg    Min    Max    Med | req/s
---------|---------------------|-------|--------|--------|------|------|------|------
POST     long-rag                   4  0(0.00%)| 21821   6398  48002  11000 |  0.07
POST     short                      6  0(0.00%)| 40752  27013  57907  35000 |  0.10
---------|---------------------|-------|--------|--------|------|------|------|------
         Aggregated                10  0(0.00%)| 33180   6398  57907  32000 |  0.17

Response time percentiles (ms)
  50%=35000  66%=40000  75%=48000  80%=53000  90%=58000  95%=58000  99%=58000
```

## Summary table

| Concurrency | Total RPS | E2E P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 0.21 | 29 000 | 45 000 | 45 000 | 0 |
| 50 | 0.17 | 35 000 | 58 000 | 58 000 | 0 |

## Notes

- The `llama-cpp-python` server processes requests serially (single slot by default). With 10+ concurrent users, requests queue and E2E latency grows linearly with concurrency.
- At u=10: 12 requests served in 60s. Average latency 27s (decode @ ~15.7 tok/s, 80 tokens out ≈ 5s decode + prefill overhead × 5.4× serialisation factor).
- At u=50: only 10 requests completed in 60s — many users were still waiting. P95 jumped to 58s.
- KV-cache metrics unavailable via `/metrics` endpoint on the Python wrapper server; observation: with n_ctx=2048 and single-slot serving, each request occupies the full context window until completion, so effective KV utilisation ≈ 100% per active slot, 0% when idle.
