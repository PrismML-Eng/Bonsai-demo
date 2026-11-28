# Bonsai 2 27B server — Vulkan backend (prism b10787).
# Mirror of start_sycl_server.ps1 for the Vulkan binary. Same tuned flags:
# full 256K context, q4_0 KV cache, mlock, ngram speculative decoding.
# Measured on Arc Pro B50: decode ~16 t/s, pp512 ~326 t/s (SYCL is faster;
# this is the fallback when the SYCL path misbehaves).
# Usage: powershell -NoProfile -File .\scripts\start_vulkan_server.ps1
$ErrorActionPreference = 'Stop'
$Demo = Split-Path $PSScriptRoot -Parent
Set-Location $Demo

$ModelDir = Join-Path $Demo 'models\bonsai2-gguf\27B'

& "$Demo\bin\vulkan\llama-server.exe" `
    -m "$ModelDir\Ternary-Bonsai-2-27B-PQ2_0.gguf" `
    --mmproj "$ModelDir\Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" `
    --host 127.0.0.1 --port 8089 `
    -c 262144 -ngl 99 -fa on `
    -ctk q4_0 -ctv q4_0 `
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --jinja `
    --image-max-tokens 1024 `
    --load-mode mlock `
    --spec-type ngram-simple --spec-draft-n-max 5 `
    --webui-config-file "$Demo\scripts\webui-config.json"
