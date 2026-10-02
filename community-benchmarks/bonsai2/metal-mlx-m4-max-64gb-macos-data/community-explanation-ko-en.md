# M4 Max 64GB 로컬 LLM 비교: Ollama NVFP4 vs Bonsai PQ2_0 vs MLX 2-bit

실측 그래프: https://dambi-local-llm-bars.chattybeak.chatgpt.site

로컬 LLM의 파일 용량을 줄이면서 한국어 품목 추출과 도구 호출을 유지할 수 있는지 검증했습니다. M4 Max 64GB 한 대에서 측정한 결과이며, 운영 서비스는 교체하거나 중단하지 않았습니다.

## 환경과 방법

- 기존: Ollama 0.33.2, NVFP4 safetensors 27.8B, MLX GPU backend. 설치 태그는 `qwen3.8:27b-mlx`지만 실제 형식은 API와 manifest에서 확인했습니다.
- 후보 A: Bonsai 2 27B PQ2_0 + BF16 mmproj, PrismML llama.cpp Metal release `prism-b10743-adfffbe`.
- 후보 B: Bonsai MLX 2-bit, mlx-vlm 0.7.2 / mlx 0.32.2 / transformers 5.14.1.
- 한국어 주문 1건, 합성 거래명세서 이미지 1장, 모의 도구 호출을 각 모델에서 3회: 총 27회. thinking OFF, 동일 원문·이미지, 문맥 상한 4,096, 출력 상한 512, temperature 0.
- warm은 2·3회차 중앙값. cold는 새 프로세스이며 OS 파일 캐시는 초기화하지 않았습니다.

| 실측 | 기존 Ollama | Bonsai PQ2_0 | Bonsai MLX 2-bit |
|---|---:|---:|---:|
| warm 주문 완료, 초 | 3.03 | 2.62 | 10.79 |
| warm 이미지 완료, 초 | 3.56 | 3.21 | 48.89 |
| warm 모의 도구 완료, 초 | 2.58 | 4.74 | 18.54 |
| 시작부터 첫 주문 완료, 초 | 14.90 | 7.52 | 13.83 |
| 모델 파일, GB | 18.17 | 8.14, mmproj 포함 | 8.60 |
| warm 주문 생성, tok/s | 52.1 | 29.3 | 17.1 |

27회 모두 품명·수량·단위가 기대값과 일치했습니다. 두 Bonsai 구성은 JSON·native tool 형식도 통과했고, Ollama의 이미지 응답은 코드펜스 때문에 strict JSON 검사에서 3회 모두 실패했습니다. 추출값 오류와 형식 실패는 따로 집계했습니다. 실제 도구 실행은 하지 않았습니다.

## 해석의 한계와 판단

입력은 27개의 서로 다른 사례가 아닙니다. 작은 fixture 세트를 반복한 결과이므로 실제 문서 OCR 정확도나 일반적인 한국어 품질로 확대 해석하지 않습니다.

Ollama/PQ는 prefix cache를 사용하고 MLX 후보는 요청 간 cache를 재사용하지 않았습니다. Ollama는 자동 speculative decoding/MTP도 사용했습니다. 주문·이미지 출력은 Bonsai 73토큰 vs Ollama 152/157토큰이라, PQ의 더 짧은 완료 시간이 더 빠른 토큰 생성 자체를 뜻하지 않습니다. 동일 양자화 조건을 분리한 실험이 아닌 현재 서버 구성의 비교입니다.

메모리 RSS는 MLX GPU allocation, physical footprint는 GGUF mmap을 충분히 포함하지 않을 수 있습니다. 서로 다른 카운터로 RAM 절감률을 주장하지 않습니다. 시스템 swap의 시작값도 달라 모델 전용 swap 비교가 아닙니다. 전력·금액 비용은 미측정입니다.

PQ2_0은 주문·문서 추출의 추가 검증 우선 후보입니다. 도구 호출은 기존 Ollama가 더 빨랐으므로 즉시 대체하지 않습니다. 현재 MLX 2-bit 서버 조합은 보류합니다. 이미지 warm 2·3회차 완료는 39.54/58.24초로 변동도 컸고, 원인은 분리 검증하지 않았습니다. 이 결과를 2-bit 양자화 자체의 한계로 일반화하지 않습니다.

다음 비교에서는 cache와 speculative decoding을 통제하고, 익명화한 실제 문서·다양한 주문으로 평가를 확대할 필요가 있습니다. 유사한 Apple Silicon 환경에서 mlx-vlm의 이미지 지연이나 PQ tool 성능을 비교하신 경험이 있다면 의견을 부탁드립니다.

공식 구현/호환성 문서: https://github.com/PrismML-Eng/Bonsai-demo/blob/main/BACKEND-SUPPORT.md

---

# Local LLMs on an M4 Max 64GB: Ollama NVFP4 vs Bonsai PQ2_0 vs MLX 2-bit

Measured charts: https://dambi-local-llm-bars.chattybeak.chatgpt.site

I tested whether smaller local model files could preserve Korean item extraction and tool-call formatting. These are measurements from one M4 Max 64GB, not benchmarks borrowed from another machine. The existing production service was not replaced or interrupted.

## Setup

- Baseline: Ollama 0.33.2, NVFP4 safetensors, 27.8B, MLX GPU backend. The installed tag was `qwen3.8:27b-mlx`; actual format was checked through the API and model manifest.
- Candidate A: Bonsai 2 27B PQ2_0 + BF16 mmproj, PrismML llama.cpp Metal, release `prism-b10743-adfffbe`.
- Candidate B: Bonsai MLX 2-bit, mlx-vlm 0.7.2 / mlx 0.32.2 / transformers 5.14.1.
- 27 requests: 3 configurations × 3 fixed tasks × 3 repetitions. One Korean order, one synthetic transaction-statement image, and mock tool calls. Same raw text/image; thinking OFF; context cap 4,096; output cap 512; temperature 0.
- Warm values are medians of repetitions 2–3. Cold means a fresh process; OS file caches were not cleared.

| Measurement | Ollama | Bonsai PQ2_0 | Bonsai MLX 2-bit |
|---|---:|---:|---:|
| Warm order completion, s | 3.03 | 2.62 | 10.79 |
| Warm image completion, s | 3.56 | 3.21 | 48.89 |
| Warm mock tool completion, s | 2.58 | 4.74 | 18.54 |
| Startup to first order completion, s | 14.90 | 7.52 | 13.83 |
| Model files, GB | 18.17 | 8.14 incl. mmproj | 8.60 |
| Warm order generation, tok/s | 52.1 | 29.3 | 17.1 |

Extracted item names, quantities and units matched expected values in all 27 requests. Both Bonsai configurations passed JSON/native-tool formatting checks. Ollama's image responses failed strict JSON in all three repetitions due to code fences; extracted values were still correct. Tool execution was mocked.

## Caveats and decision

These are repeated small fixtures, not 27 distinct examples or evidence of general OCR accuracy. Ollama/PQ used prefix caching; the MLX candidate did not reuse prompts between requests. Ollama also used automatic speculative decoding/MTP. Bonsai generated 73 tokens for order/image JSON, versus 152/157 for Ollama. Shorter completion does not imply faster token generation, and these configurations are not a controlled quantization ablation.

RSS can miss MLX GPU allocations and physical footprint can miss GGUF mmap pages. Neither counter establishes comparable total RAM savings. Swap is system-wide, with different starting values. Power and monetary costs were not measured.

Decision: prioritize further PQ2_0 validation for extraction; retain Ollama for now. Hold the current MLX 2-bit server configuration. Its warm image completions also varied substantially, at 39.54/58.24 seconds; the cause was not isolated, so I do not attribute this generally to 2-bit quantization.

Next steps are matched cache/speculative-decoding conditions and a larger set of anonymized real documents and orders. Comparisons or suggestions on Apple Silicon mlx-vlm image latency and PQ tool performance are welcome.

Official compatibility documentation: https://github.com/PrismML-Eng/Bonsai-demo/blob/main/BACKEND-SUPPORT.md
