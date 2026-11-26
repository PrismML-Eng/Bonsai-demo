# Bonsai 2.5 27B server on Intel Arc via SYCL (XMX/TernSYCL kernels).
# Model: models\bonsai25-gguf\27B\Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf (built-in MTP head).
# Measured on Arc Pro B50 (b10787, 2026-11-26): plain tg128 24.2, pp512 727;
# with MTP 3/0.1 decode 30-32 t/s (+26-31%). Do NOT raise n-max past 3 at 262K
# context: 5 + chain crashes with UR_RESULT_ERROR_DEVICE_LOST on 16 GB.
# Requires q4_0 KV cache for the XMX decode attention path.
# Usage: powershell -NoProfile -File .\scripts\start_sycl_server.ps1 [-Port N]   (Ctrl+C to stop)
# ModelManager's SYCL entry passes -Port 8088; direct use defaults to 8080.
# BONSAI_SYCL_MTP=0 disables the built-in MTP draft head (plain decoding).
param(
    [int]$Port = 8080,
    [string]$BindHost = '0.0.0.0',
    # Everything the launcher appends after the known params (e.g. ModelManager's
    # EngineApiKey injection: --api-key <key>) is passed through to llama-server.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$Demo = Split-Path $PSScriptRoot -Parent
Set-Location $Demo

$env:GGML_SYCL_PTQ1_T2        = 'all'     # repack PQ2_0/PTQ1_0 to 2-bit for TernSYCL kernels (Xe2: faster pp AND tg)
$env:GGML_SYCL_FA_DEC_DPAS    = '1'       # XMX decode attention reading the q4_0 KV cache directly
$env:GGML_SYCL_FA_ONEDNN_MAX_KV = '98304'
$env:GGML_SYCL_T2_W8A8_MIN    = '1024'
$env:LLAMA_ARG_SPEC_DRAFT_UBATCH = '512'

$ModelDir = Join-Path $Demo 'models\bonsai25-gguf\27B'

# Built-in MTP draft head (the *-mtp.gguf carries it; no sidecar, no -md, no -ngld).
# On by default; measured +26-31% decode at 3, 0.1. Verify engagement via the
# response timings.draft_n (> 0). LLAMA_MTP_CHAIN=1 measured no gain; n-max 5
# crashes at 262K on 16 GB — keep 3.
$SpecArgs = @()
if ($env:BONSAI_SYCL_MTP -ne '0') {
    $SpecArgs = @(
        '--spec-type', 'draft-mtp',
        '--spec-draft-n-max', '3',
        '--spec-draft-p-min', '0.1'
    )
    Write-Host '  Speculative: built-in MTP head (draft-mtp, n-max 3, p-min 0.1)' -ForegroundColor Green
}

& "$Demo\bin\sycl\llama-server.exe" `
    -m "$ModelDir\Ternary-Bonsai-2.5-27B-PQ2_0-mtp.gguf" `
    --mmproj "$ModelDir\Ternary-Bonsai-2.5-27B-mmproj-Q8_0.gguf" `
    --host $BindHost --port $Port `
    -c 262144 -ngl 99 -fa on `
    -ctk q4_0 -ctv q4_0 `   # do NOT add --load-mode mlock: 262K + mlock + MTP crashes at load (DEVICE_LOST); mlock only safe at <=131K
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --jinja `
    --image-max-tokens 1024 `
    --webui-config-file "$Demo\scripts\webui-config.json" `
    @SpecArgs @Rest
