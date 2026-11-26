# Bonsai 2 / 2.5 27B on Intel Arc Pro B50 — 完整调优笔记

> 2026-10/11 实测结论。硬件：Arc Pro B50 16 GB（Xe2，驱动 32.0.101.8976+）、31 GB RAM、Windows 11。
> 软件：PrismML fork `prism-b10787-73bfe6c`（Vulkan 与 SYCL 包）。
> 配套：ModelManager 面板（端口 8086/8088/8089）、`scripts/start_*_server.ps1` 启动脚本。

---

## 一、总览：每个模型该用哪个后端

| 模型 | 后端 | 端口 | 实测 decode | 实测 pp512 | 原因 |
|---|---|---|---|---|---|
| **Bonsai 2.5 27B PQ2_0-mtp** | **SYCL + MTP 3/0.1** | 8088 | **30-32 t/s** | 727 t/s（裸） | 内置 MTP 头净赚 +26-31%（2026-11-26 实测） |
| **Bonsai 2 27B PQ2_0** | **SYCL + T2=all** | 8088 | **25.4 t/s** | **680 t/s** | TernSYCL int2×int8 XMX 内核 |
| HauhauCS 35B-A3B IQ2_M | Vulkan | 8086 | **39.5 t/s** | **784 t/s** | 主流量化走 Vulkan integer-dot 最优；SYCL 慢一半（37.3 / 382） |
| Bonsai 2 27B（备选） | Vulkan | 8089 | 16.0 t/s | 326 t/s | SYCL 出问题时兜底 |

**铁律：Bonsai 格式 → SYCL；主流量化（IQ/K 系）→ Vulkan。** TernSYCL/XMX 优化是 Bonsai 格式专属。

三个本地服务同属 ModelManager `gpu-main` 互斥组（16 GB 卡同时只跑得动一个 27B 级服务）。

---

## 二、SYCL 服务器：启动参数（调优终态）

脚本：`scripts/start_sycl_server.ps1`（`-Port` 可改，默认 8080；ModelManager 传 8088）

```powershell
# 二进制：bin\sycl\llama-server.exe（SYCL 包必须叠在 CPU 包上解压；自带 oneAPI 2025.3.3 运行时 DLL）
# 注意：SYCL 的显存分配走 Level Zero，任务管理器/性能计数器看不到，属正常
llama-server.exe `
  -m <模型>\Ternary-Bonsai-2-27B-PQ2_0.gguf `
  --mmproj <模型>\Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf `
  --host 127.0.0.1 --port 8088 `
  -c 262144 `              # 模型上限 256K；KV 池按需增长，空上下文不浪费
  -ngl 99 -fa on `         # 65/65 层全在 GPU
  -ctk q4_0 -ctv q4_0 `    # ★必须：XMX 解码注意力只认 q4_0 KV；f16 会静默掉回慢路径
  # --load-mode mlock：2.5+MTP 下 262K 会 DEVICE_LOST（2026-11-26 实测，两次复现）；
  # ≤131K 上下文时 mlock 安全。262K 日常配置不要加。
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --jinja `   # demo 的 Bonsai 2 官方采样档
  --image-max-tokens 1024 `  # 大图降到 1024 vision tokens；OCR/截图要全精度改 0（更慢）
  # --load-mode mlock：仅 ≤131K 安全；2.5+MTP+262K 加载即 DEVICE_LOST（见坑表）
```

**环境变量（启动前必须设置，少一个就掉速）**：

```powershell
$env:GGML_SYCL_PTQ1_T2          = 'all'    # 权重重排为 2-bit 布局喂 TernSYCL；不开 decode 25.4→22.7
$env:GGML_SYCL_FA_DEC_DPAS      = '1'      # XMX 解码注意力直读 q4_0 KV
$env:GGML_SYCL_FA_ONEDNN_MAX_KV = '98304'
$env:GGML_SYCL_T2_W8A8_MIN      = '1024'
```

启动成功的标志（日志里应出现）：`fused DeltaNet gates active`、`SWIGLU folded into the rotation`、`fused DeltaNet conv chain active`。
验证：首次请求看 `timings.predicted_per_second ≥ 22`；只有 16 上下 = 走了 Vulkan 或环境变量没生效。

---

## 三、投机解码：现状与未来

**Bonsai 2.5（内置 MTP 头）：开，实测净赚。** 2026-11-26 在 b10787 上实测
（`--spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1`，无 sidecar）：
短提示解码 24.4 → **30-32 t/s（+26-31%）**，`timings.draft_n` 258-267 确认生效；
`LLAMA_MTP_CHAIN=1` 无增益；**n-max 5 + chain 在 262K 上下文下 DEVICE_LOST**（16 GB
装不下草稿 KV/scratch），3/0.1 是安全上限。2026-11-26 复测：**-c 131072 下 n-max 4/5
都稳定**（崩溃确属 262K 特有），但 30.8-33.6 t/s 与 3/0.1 持平——提速天花板就在
30-33，日常配置保持 3/0.1。冷启动预填 413→1429 ms（草稿头过一遍
prompt），热缓存不受影响。详见 `community-benchmarks/bonsai25/sycl-arc-pro-b50-16gb-windows.md`。

**Bonsai 2（全尺寸 sidecar drafter）：不要开。** 已发布的 MTP drafter（`Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf`）是**全尺寸 27B Q8_0（7.6 GB）**——比 6.5 GB 的 target 还重，带宽账永远不可能赢：

| 配置 | 实测 decode |
|---|---|
| 不开 MTP | 25.1 t/s（基线） |
| MTP，不开 chain | 17.7 t/s（更慢） |
| MTP + `LLAMA_MTP_CHAIN=1`（b10787 新增的链式草稿） | 25.0 t/s（追平基线，纯浪费） |

草稿接受率 96.8%、平均草稿长 5.84——质量极好，输在草稿成本。`scripts/start_sycl_mtp.ps1` 已留好（含 chain），等小型 drafter。

**未来可开**：prism 发布小型 DSpark drafter（~0.6 GB，CUDA 上已实测 1.8-2.4×）后：
`--spec-type draft-dspark -md <drafter> -ngld 999 -np 1`（会禁用跨请求前缀缓存，需权衡）。
b10809-b10831 的 CUDA 提交密集打磨 MTP/DFlash2 工具链＝小 drafter 的基建期，关注 `ggml-vulkan`/`ggml-sycl`/`ternsycl` 目录的提交。

---

## 四、已知的坑（全部实测踩过）

### 显存与内存

| 坑 | 现象 | 规避 |
|---|---|---|
| f16 KV + 长上下文 | 262K×64KiB=16 GB 光 KV 就爆卡 → 驱动静默倒内存 → 整机卡死 | 永远 `-ctk/-ctv q4_0`（256K KV 仅 ~4.5 GB） |
| mlock + 262K + MTP | 加载时 `UR_RESULT_ERROR_DEVICE_LOST`（memset buffer_clear），两次复现 | 262K 配置别加 `--load-mode mlock`；≤131K 时安全 |
| 多服务器并行 | 两个 27B 级服务各 ~13 GB，合计 >16 GB → 互相拖死 | `gpu-main` 互斥组；一卡一服务 |
| 任务管理器显存 | SYCL/Level Zero 分配不可见，显示远低于实际 | 以 `llama-server -lv 4` 日志的 buffer size 为准 |
| WUDFHost 假警报 | GPU 计数器里 WUDFHost 显示 ~9.6 GB，像"神秘进程" | 驱动宿主进程，非真实占用，忽略 |

### 性能误判

| 坑 | 真相 |
|---|---|
| 长答案慢 ≠ 硬件慢 | 23 分钟的"5 盒猜猫"答案 ≈3.2 万 token 思考，全程满速。想快：webui 里 💡 Reasoning 调 Medium(2048)，或服务器加 `--reasoning-budget 4096` |
| `-ub` 调大 | 1024/2048 反降（680→492）。保持默认 512 |
| PTQ1_0 更快？ | SYCL 上 XMX 把 PTQ1_0 展开成与 PQ2_0 同布局，**同速**（25.4 vs 25.4）；Vulkan 上确实快 26%（20.1 vs 16.0）但天花板低 |
| 27B 的 Q3/Q4 更好？ | 装得下（13.3 GB + 32K）但只有 10 t/s，且 Bonsai 权重无法 requant（fork 拒绝）；高质量位已被 35B-A3B（39.5 t/s）占据 |

### 行为特性

| 坑 | 规避 |
|---|---|
| 追问改一个字 → 全量重预填（22 万 token ≈ 19 分钟） | 追问前缀必须逐字相同 |
| 262K 池只够一份 22 万 token 文档 | 第二份大文档会挤掉第一份缓存 |
| 大预填速度递减 | 709→220 t/s（GDN 循环状态成本随上下文增长），224K 全程均值 ~193 t/s，**首填后缓存追问 5 秒** |
| 中文请求乱码 500 | 客户端必须发 UTF-8（curl 默认 GBK） |
| 长上下文 decode 变慢 | 225K 上下文 decode 15.4 vs 短上下文 25，长注意力固有代价 |

### 运维

| 坑 | 规避 |
|---|---|
| ModelManager 读 `%APPDATA%\ModelManager\servers.json`，不是仓库里的 `config/servers.json` | 改配置两边同步；仓库版是 git 固化的参考 |
| ModelManager 停止按钮 | `Kill(entireProcessTree)`，对 powershell 包装脚本（SYCL 环境变量注入用）有效 |
| llama-cli 诊断会挂死驱动 | 排查看服务器 `-lv 4` 日志，别再起第二个 Vulkan 进程对撞 |

---

## 五、快速验证命令

```bash
curl -s http://localhost:8088/health                                   # 200
curl -s http://localhost:8088/props | python -m json.tool | head -20   # 槽位/上下文
# 任意请求看响应里的 timings：prompt_ms=预填, predicted_per_second=解码
# GPU 实测占用（WDDM 计数器对 Vulkan 有效、对 SYCL 不可见）：
powershell -c "(Get-Counter '\GPU Process Memory(*)\Dedicated Usage').CounterSamples"
```

---

## 六、更新策略

- 本机 `bin/sycl` 停在 `prism-b10787`；**仓库已 pin 到 `prism-b12178-03ec600`**
  （Bonsai 2.5 发布随附，2026-11-24）。**b12178 已在 B50 实测为回归**（解码 -11%、
  预填 -23%、MTP 路径坏，见第八节），继续用 b10787。
- **b12220 复测（2026-11-26，仓库 pin 分支）：解码回归仍在**（tg128 24.0→22.3），
  pp512 稳态 472（b10787 是 727，-35%）；**MTP 路径已修好**（draft-mtp 可用，
  探针 29.7/36.7 t/s，与 b10787 的 30-32 持平）——但裸解码和预填都更差，
  整体仍不升。包留在 `bin/sycl-b12220/` 供后续回归测试。
- 升级触发条件：release 说明或提交里出现 `ggml-vulkan` / `ggml-sycl` / `ternsycl` / 官方小型 drafter。
- 下载走本机代理 `127.0.0.1:7897`（github.com/hf 直连被重置），release 资产用 api.github.com 核对 SHA256；
  HF 权重核对用响应头的 `X-Linked-ETag`（即官方 SHA256）。

---

## 七、配套文件清单

（`scripts/` 三个启动脚本随本笔记入库；其余为本地测试/实验文件，未入库）

| 文件 | 作用 |
|---|---|
| `scripts/start_sycl_server.ps1` | SYCL 主服务器（Bonsai 2.5 + 内置 MTP，调优终态，`-Port` 可改） |
| `scripts/start_sycl_mtp.ps1` | MTP 实验（含 LLAMA_MTP_CHAIN，等小 drafter） |
| `scripts/start_vulkan_server.ps1` | Vulkan 兜底服务器（8089，参数同 ModelManager 实测版） |
| `.claude/launch.json` | Claude 应用启动面板三条配置（8088/8089） |
| `longdoc_test.py` + `moby.txt` | 256K 长文档/探针测试（22.5 万 token 标准负载） |
| `models/bonsai25-gguf/27B/` | Bonsai 2.5 权重（`Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf` 等） |
| `mtp_matrix.sh` / `mtp_round3.sh` + `*.log` | MTP 服务器矩阵与 llama-bench 原始输出（报告数据源） |
| `bin/sycl-b12178/` | b12178 CPU+SYCL 包（实测回归，留作后续回归测试） |
| `bin/sycl-b12220/` | b12220 CPU+SYCL 包（解码回归仍在、MTP 已修，见第六节） |

---

## 八、Bonsai 2.5 27B（2026-11-24 起仓库默认家族）

**SYCL 路径对 2.5 完全兼容，调优配方不变。** 2.5 用与 Bonsai 2 相同的三种打包
（PTQ1_0/PQ2_0/Q2_0）和相同架构（qwen35 27B），SYCL 的原生内核（PQ2_0/PTQ1_0
转换 + Hadamard + TernSYCL XMX）原样适用——见 BACKEND-SUPPORT.md 的 SYCL 行，
未变。`scripts/common.sh` 的家族选择逻辑：SYCL 下载 **PQ2_0-mtp** 档
（PTQ1_0 只在 CUDA 类 GPU 上被优先，SYCL 上 XMX 把两者展开成同布局、同速）。

### 文件选择

| 文件 | 大小 | 说明 |
|---|---|---|
| `Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf` | 7.0 GB | ✅ 推荐档（SYCL 默认下载的就是它） |
| `Ternary-Bonsai-2.5-27B-PTQ1_0-mtp.gguf` | 5.8 GB | SYCL 上同速（XMX 展开 2-bit 布局），无优先理由 |
| `Ternary-Bonsai-2.5-27B-mmproj-Q8_0.gguf` | ~0.6 GB | 视觉投影器，用法同前 |

`-mtp` 后缀 = **内置 MTP 草稿头**（+0.2 GiB），无 sidecar、无转换步骤；
不开草稿时行为与普通文件完全一致。官方 SHA256（PQ2_0-mtp）：
`ededc9fc0a8a6a8dd30914d107b2d2ce7674d789f1d05a1a481f240609aa6c23`。

### 启动

环境变量与参数同第二节配方，只换模型路径；**采样档变了**：2.5 官方 thinking 档是
`min_p 0`（Bonsai 2 是 0.05），temp/top-p/top-k 不变：

```powershell
-m models\bonsai25-gguf\27B\Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf
--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --jinja
```

### MTP：2.5 上值得开（与第三节对 Bonsai 2 的结论相反）

- 第三节"MTP 不要开"的前提是 Bonsai 2 的 drafter 是 **7.6 GB 全尺寸 Q8_0 sidecar**；
  2.5 的内置头只有 +0.2 GiB，且**不破坏跨请求前缀缓存**（DSpark 路径才会破坏）。
- 官方对 SYCL 的 MTP 状态：**未测量、默认关**——SPECULATIVE.md 的表只列
  CUDA/ROCm（开 1.5-1.8x）、Metal（开 1.1x）、Vulkan/CPU（关），SYCL 未入表；
  `common.sh` 的 `bonsai_mtp_default_on` 只含 `cuda|rocm|hip|mac`。
- 同代 Xe2（Arc B580）社区实测（`community-benchmarks/bonsai2/sycl-arc-b580-12gb-windows.md`，
  注意是社区 fork `Torchit1/llama.cpp` arc-b580 而非 PrismML 包）：内置头 +
  `--spec-type draft-mtp,ngram-mod` 短提示解码 45.9 → ~63 t/s（约 1.4x）。
- 启用方法：`--spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1`；
  验证生效看响应 `timings.draft_n > 0`。
- ✅ **实测（2026-11-26，b10787）：内置头在 b10787 直接可用**——`draft-mtp` 无 sidecar
  即生效，24.4 → 30-32 t/s（+26-31%）。b10787 也能加载 `-mtp` 文件（llama-bench 跑通）。
  完整数字见 `community-benchmarks/bonsai25/sycl-arc-pro-b50-16gb-windows.md`。

### llama.cpp 侧：b12178 在 B50 上是回归，别升（2026-11-26 提交审计 + 实测）

b10787→b12178 共 1391 提交，SYCL 相关 47 个，与 B50 相关的要点：

| 提交 | 日期 | 内容 | 对你的影响 |
|---|---|---|---|
| `7097bb48` + #372 | 10-20 | 修复"Hadamard 列表点名了未加载张量（如关草稿时的 MTP 头）导致模型加载失败" | 实测 b10787 加载 2.5 `-mtp` 无碍，此修复对本机不必要 |
| `f2855c3e` | 11-23 | `GGML_SYCL_T2_VGEMM_MIN=k`：k..8 行 PTQ1_0 batch 走 GemmMT（bit-exact） | **SYCL 的 MTP 多 token 验证内核**——白皮书 Core Ultra iGPU MTP 2.08x 的出处 |
| `05648dc1` | 11-22 | `LLAMA_MTP_PREFILL_LEAN=1` 草稿头 lean 预填 | 缓解 MTP 的预填劣化 |
| `7377bada` | 10-23 | SYCL graph record & replay | 解码每步启动开销下降，裸速也赚 |
| `d81d0d8f` | 10-22 | XMX multi-column 重构 | TernSYCL 路径底层重构 |
| `63f16c40` | 10-25 | batched scheduler 每解码步省 ~55-65 µs host 时间 | 后端无关的解码提速 |
| `0a9ef006` | 10-23 | fattn-mkl 去 host 等待 | FA 路径提速 |
| `0756e83f`/`13de11e7` | 10-21/16 | q8 快速去量化、q4_K/q5_K 宽存储 | 杂项提速 |
| `8c86d6e2` + #384 | 10-21 | PTQ1_0/PQ2_0 scratch 走 device allocator（修双卡 DEVICE_LOST） | 单卡 B50 无感 |
| b12178 新功能 | 11-24 | **`pq2_0m` 2-bit KV（`-ctk pq2_0m`）**，比 q4_0 省 22-44%；Metal 不支持，SYCL 支持待验证 | 若 SYCL 可用，262K KV 池再缩一半档 |

**实测结论（llama-bench + 服务器探针，见 `community-benchmarks/bonsai25/`）：b12178 在 B50 上全面变慢——**
裸解码 25.2→22.3（-11%），pp512 737→557（-23%），`GGML_SYCL_ENABLE_GRAPH=1` 只回 1 t/s；
且 b12178 的 MTP 路径在这张卡上坏（服务器能加载 spec，请求失败；8/0.6 档起不来）。
**停在 b10787 是对的**，2.5 的内置 MTP 在 b10787 上直接可用（+26-31%），不需要新 runtime。
b12178 包留在 `bin/sycl-b12178/` 供后续版本回归测试。

### 2.5 vs 2 速览

| | Bonsai 2 27B | Bonsai 2.5 27B |
|---|---|---|
| agentic | 编码为 FP16 的 63% | 工具调用 FP16 级（77.2/77.7），编码 90% |
| 尺寸（PQ2_0 / PTQ1_0） | 7.2 / 5.9 GB | 7.0 / 5.8 GB（B50 的 16 GB 配方照用） |
| 投机解码 | 无官方 drafter | 内置 MTP 头（`-mtp` 文件） |
| thinking 采样 | min_p 0.05 | **min_p 0** |
| 尺寸线 | 2B/4B/9B/27B | 仅 27B（小模型仍 `BONSAI_FAMILY=bonsai2`） |
