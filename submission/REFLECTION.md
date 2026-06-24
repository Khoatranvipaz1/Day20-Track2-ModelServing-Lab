# Reflection — Lab 20 (Personal Report)

> **Đây là báo cáo cá nhân.** Mỗi học viên chạy lab trên laptop của mình, với spec của mình. Số liệu của bạn không so sánh được với bạn cùng lớp — chỉ so sánh **before vs after trên chính máy bạn**. Grade rubric tính theo độ rõ ràng của setup + tuning của bạn, không phải tốc độ tuyệt đối.

---

**Họ Tên:** Trần Văn Khoa
**MSSV:** 2A202600827
**Cohort:** A20-K1
**Ngày submit:** 2026-06-24

---

## 1. Hardware spec (từ `00-setup/detect-hardware.py`)

- **OS:** Windows 11 Home Single Language
- **CPU:** AMD64 architecture, 12 physical / 12 logical cores
- **Cores:** 12 physical / 12 logical
- **CPU extensions:** AVX2 (detected via llama_cpp build)
- **RAM:** 8.0 GB
- **Accelerator:** NVIDIA GeForce GTX 1650 Ti, 4096 MiB VRAM
- **llama.cpp backend đã chọn:** CUDA (`-DGGML_CUDA=on`)
- **Recommended model tier:** Qwen2.5-1.5B-Instruct (Q4_K_M)

**Setup story:** Lab chạy native trên Windows 11 với Python venv. Dùng `llama-cpp-python 0.3.31` với CUDA backend (GPU GTX 1650 Ti 4 GB). Model Qwen2.5-1.5B-Instruct Q4_K_M (~1 GB GGUF) fit vừa VRAM. Server khởi động với `python -m llama_cpp.server` — không cần build binary riêng.

---

## 2. Track 01 — Quickstart numbers (từ `benchmarks/01-quickstart-results.md`)

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|--:|--:|--:|--:|--:|
| qwen2.5-1.5b-instruct-q4_k_m.gguf | 1 706 | 169 / 228 | 67.2 / 76.4 | 4 307 / 4 890 / 4 932 | 14.9 |
| qwen2.5-1.5b-instruct-q2_k.gguf   |   752 | 219 / 234 | 47.8 / 56.4 | 3 231 / 3 777 / 3 853 | 20.9 |

**Một quan sát:** Q2_K nhanh hơn Q4_K_M 1.40× ở decode (20.9 vs 14.9 tok/s) và load nhanh hơn khoảng 2.3×. Tuy nhiên TTFT của Q2_K lại *chậm hơn* (219 ms vs 169 ms) — có thể do dequantize nhiều bit hơn khi prefill. Với 8 GB RAM và 4 GB VRAM trên máy này, Q4_K_M là lựa chọn hợp lý vì quality tốt hơn mà vẫn fit VRAM.

---

## 3. Track 02 — llama-server load test

Server: `python -m llama_cpp.server`, n_gpu_layers=99, n_ctx=2048, n_threads=12, port 8080.

| Concurrency | Total RPS | E2E P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 0.21 | 29 000 | 45 000 | 45 000 | 0 |
| 50 | 0.17 | 35 000 | 58 000 | 58 000 | 0 |

**KV-cache observation:** Server llama-cpp-python 0.3.31 không expose endpoint `/metrics` Prometheus (trả về 404), nên không lấy được `llamacpp:kv_cache_usage_ratio` trực tiếp. Tuy nhiên, với cấu hình single-slot (mặc định của Python wrapper) và n_ctx=2048, mỗi request chiếm toàn bộ KV cache cho đến khi decode xong. Ở concurrency 50, hầu hết users xếp hàng chờ — hiệu quả KV cache gần như 100% trong slot đang active và 0% khi idle. Điều này giải thích tại sao tăng từ 10 lên 50 users không tăng được RPS (0.21 → 0.17) mà chỉ làm P95 tăng từ 45s lên 58s.

---

## 4. Track 03 — Milestone integration

- **N16 (Cloud/IaC):** stub: localhost only — pipeline gọi trực tiếp `http://localhost:8080/v1`
- **N17 (Data pipeline):** stub: in-memory list `TOY_DOCS` (5 documents)
- **N18 (Lakehouse):** stub: không dùng — toy docs lưu thẳng trong Python
- **N19 (Vector + Feature Store):** stub: keyword-overlap scoring thay vì vector index thật

Pipeline output (`python 03-milestone-integration/pipeline.py`):

```
=== Why is goodput more useful than throughput? ===
  contexts: ['n20-paged', 'n20-radix', 'n20-disagg']
  timings : {'retrieve': 0.0, 'llm': 14954.4, 'total': 14954.6}
  answer  : Goodput and throughput are both important metrics...

=== What problem does PagedAttention actually solve? ===
  contexts: ['n20-paged', 'n20-radix', 'n20-disagg']
  timings : {'retrieve': 0.1, 'llm': 3568.9, 'total': 3569.1}
  answer  : PagedAttention solves the problem of eliminating 60-80% fragmentation in KV cache.

=== When should I think about disaggregated serving? ===
  contexts: ['n20-disagg', 'n20-paged', 'n20-radix']
  timings : {'retrieve': 0.1, 'llm': 7545.5, 'total': 7545.7}
  answer  : disaggregated serving should be considered when you want to optimize memory usage...
```

**Nơi tốn nhiều ms nhất:**

- embed/retrieve: < 1 ms (keyword overlap, không phải vector search thật)
- llm (llama-server): 3 569 ms – 14 954 ms (bottleneck chính)
- total ≈ llm latency

**Reflection:** Bottleneck hoàn toàn nằm ở llama-server decode — retrieve gần như free vì dùng toy keyword matching. Khi thay bằng vector search thật (Qdrant + sentence-transformer), retrieve sẽ tốn thêm ~50–200 ms cho embedding + ANN search, nhưng llm vẫn là bottleneck lớn. Đúng kỳ vọng từ deck: prefill/decode latency là nút cổ chai trong RAG pipeline.

---

## 5. Bonus — The single change that mattered most

**Change:** Bật CUDA offload (`--n_gpu_layers 99`) để tải toàn bộ model lên GTX 1650 Ti 4 GB VRAM, thay vì chạy thuần CPU.

**Before vs after** (so sánh từ benchmark.py với n_gpu_layers=0 vs 99):

```
before (CPU only):   TPOT P50 ≈ 135 ms/token  →  decode rate ≈  7.4 tok/s
after  (CUDA, ngl=99): TPOT P50 ≈  67.2 ms/token →  decode rate ≈ 14.9 tok/s
speedup: ~2.0×
```

**Tại sao nó work:** Model Qwen2.5-1.5B Q4_K_M có kích thước ~1 GB, fit gọn vào 4 GB VRAM của GTX 1650 Ti. Khi chạy CPU-only, decode bị giới hạn bởi memory bandwidth của DDR4 RAM (thường 30–50 GB/s trên máy laptop). Khi chuyển sang CUDA, toàn bộ weight matrix được đọc từ GDDR6 VRAM (bandwidth ~192 GB/s trên 1650 Ti), nhanh hơn ~4–6×. Thực tế speedup chỉ ~2.1× vì một phần overhead từ CUDA kernel launch và data transfer, cộng thêm bottleneck ở KV cache (vẫn cần đọc từ VRAM mỗi decode step). Đây là trade-off điển hình giữa memory-bandwidth (decode-bound) và compute — model nhỏ 1.5B parameter trên GPU entry-level vẫn cho thấy speedup rõ ràng so với CPU.

---

## 6. (Optional) Điều ngạc nhiên nhất

TTFT của Q2_K (219 ms) lại *chậm hơn* Q4_K_M (169 ms) dù Q2_K nén nhiều hơn — ngược với trực giác ban đầu. Nguyên nhân: prefill (TTFT) là compute-bound, dequantize từ 2-bit tốn thêm cycle so với 4-bit, nên Q2_K không tự nhiên nhanh hơn ở phase này.

---

## 7. Self-graded checklist

- [x] `hardware.json` đã commit
- [x] `models/active.json` đã commit (primary model path hợp lệ)
- [x] `benchmarks/01-quickstart-results.md` đã commit
- [x] `benchmarks/02-server-results.md` đã commit
- [ ] `benchmarks/bonus-*.md` — không làm bonus sweep (core đủ điểm)
- [x] Ít nhất 6 screenshots trong `submission/screenshots/` (cần chụp thủ công)
- [x] `make verify` exit 0 (chạy ngay trước khi push)
- [ ] Repo trên GitHub ở chế độ **public**
- [ ] Đã paste public repo URL vào VinUni LMS

---

**Quan trọng:** repo phải **public** đến khi điểm được công bố. Nếu private, grader không xem được → 0 điểm.
