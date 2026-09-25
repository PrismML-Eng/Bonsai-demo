$ErrorActionPreference = "Stop"


$BonsaiModel  = if ($env:BONSAI_MODEL)  { $env:BONSAI_MODEL.ToUpperInvariant() } else { "27B" }
$BonsaiFamily = if ($env:BONSAI_FAMILY) { $env:BONSAI_FAMILY.ToLowerInvariant() } else { "bonsai2" }

if ($BonsaiModel -notin @("27B", "8B", "4B", "1.7B")) {
    Write-Host "[ERR] Unknown BONSAI_MODEL='$BonsaiModel'. Valid values: 27B, 8B, 4B, 1.7B" -ForegroundColor Red
    exit 1
}
if ($BonsaiFamily -notin @("bonsai2", "bonsai", "ternary")) {
    Write-Host "[ERR] Unknown BONSAI_FAMILY='$BonsaiFamily'. Valid values: bonsai2, bonsai, ternary" -ForegroundColor Red
    exit 1
}
# Bonsai 2 is 27B. Without this, another size walks into a directory that was
# never going to exist and the error blames setup. Mirrors BONSAI2_SIZES in
# scripts/common.sh.
$Bonsai2Sizes = if ($env:BONSAI2_SIZES) { $env:BONSAI2_SIZES -split '\s+' } else { @("27B") }
if ($BonsaiFamily -eq "bonsai2" -and $BonsaiModel -notin $Bonsai2Sizes) {
    Write-Host "[ERR] Bonsai 2 is 27B." -ForegroundColor Red
    Write-Host "      Bonsai 2:     `$env:BONSAI_MODEL='27B'; .\scripts\run_llama.ps1" -ForegroundColor Yellow
    Write-Host "      Other sizes:  `$env:BONSAI_FAMILY='ternary'; .\scripts\run_llama.ps1" -ForegroundColor Yellow
    exit 1
}

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

if ($BonsaiFamily -eq "bonsai2") {
    $ModelDir = Join-Path $DemoDir "models\bonsai2-gguf\$BonsaiModel"
    $FamilyDisplay = "Bonsai-2"
} elseif ($BonsaiFamily -eq "ternary") {
    $ModelDir = Join-Path $DemoDir "models\ternary-gguf\$BonsaiModel"

    $FamilyDisplay = "Ternary-Bonsai"
} else {
    $ModelDir = Join-Path $DemoDir "models\gguf\$BonsaiModel"
    $FamilyDisplay = "Bonsai"
}

# Select exactly the demo quant for the family (a leftover F16 or g64 file
# must never be picked up).
$BinCandidates = @(
    "bin\cuda\llama-cli.exe",
    "bin\hip\llama-cli.exe",
    "bin\vulkan\llama-cli.exe",
    "bin\cpu\llama-cli.exe",
    "llama.cpp\build\bin\Release\llama-cli.exe",
    "llama.cpp\build\bin\llama-cli.exe"
)
$Model = $null
$BinRel = $null
foreach ($cand in $BinCandidates) {
    if (Test-Path (Join-Path $DemoDir $cand)) { $BinRel = $cand; break }
}
$Pq2Ready = $BinRel -notlike "bin\vulkan\*"
if ($BonsaiFamily -eq "bonsai2") {
    # Every Bonsai 2 band needs the fork's kernels, so there is no group-64 fallback.
    $tryPatterns = @("*-PQ2_0.gguf", "*-PTQ1_0.gguf")
} elseif ($BonsaiFamily -eq "ternary") {
    # PQ2_0 where the backend has kernels (see MODEL-FORMATS.md); official group-64
    # otherwise (*g64 on pre-v7 repos, plain *-Q2_0 on newer repos).
    # BONSAI_FORCE_G64=1 skips PQ2_0 regardless of backend.
    $tryPatterns = if ($env:BONSAI_FORCE_G64 -eq "1" -or -not $Pq2Ready) { @("*g64.gguf", "*-Q2_0.gguf") }
                   else { @("*-PQ2_0.gguf", "*g64.gguf", "*-Q2_0.gguf") }
} else {
    $tryPatterns = @("*-Q1_0.gguf")
}
foreach ($qp in $tryPatterns) {
    # plain *-Q2_0.gguf is only trusted with the downloader's .official-q2_0 marker
    # (newer repos); otherwise it is a deprecated legacy leftover v7 refuses to load
    if ($qp -eq "*-Q2_0.gguf" -and -not (Test-Path (Join-Path $ModelDir ".official-q2_0"))) { continue }
    $Model = Get-ChildItem -Path $ModelDir -Filter $qp -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*mmproj*" -and $_.Name -notlike "*dspark*" -and $_.Name -notlike "*kv-bias*" } |
        Select-Object -First 1
    if ($Model) { break }
}
if (-not $Model) {
    Write-Host "[ERR] GGUF model not found for $FamilyDisplay-$BonsaiModel in $ModelDir" -ForegroundColor Red
    Write-Host "      Run .\setup.ps1 first." -ForegroundColor Yellow
    exit 1
}

if (-not $BinRel) {
    Write-Host "[ERR] llama-cli.exe not found. Run .\setup.ps1 first." -ForegroundColor Red
    exit 1
}

$Bin = Join-Path $DemoDir $BinRel
$BinDir = Split-Path $Bin -Parent
$env:Path = "$BinDir;$env:Path"

$Ngl = if ($env:BONSAI_NGL) {
    $env:BONSAI_NGL
} elseif ($BinRel -like "bin\cpu\*") {
    "0"
} else {
    "99"
}

# Bonsai 2: the base model's own sampling defaults, thinking stays enabled.
# 27B of the earlier families: reference-demo sampling, thinking also stays on.
# Older sizes keep the exact flag set they were tested with.
if ($BonsaiFamily -eq "bonsai2") {
    $CommonArgs = @(
        "-m", $Model.FullName,
        "-ngl", $Ngl, "-fa", "on",
        "--log-disable",
        "--temp", "1.0",
        "--top-p", "0.95",
        "--top-k", "20",
        "--min-p", "0.05"
    )
} elseif ($BonsaiModel -eq "27B") {
    $CommonArgs = @(
        "-m", $Model.FullName,
        "-ngl", $Ngl, "-fa", "on",
        "--log-disable",
        "--temp", "0.7",
        "--top-p", "0.95",
        "--top-k", "20",
        "--min-p", "0"
    )
} else {
    $CommonArgs = @(
        "-m", $Model.FullName,
        "-ngl", $Ngl, "-fa", "on",
        "--log-disable",
        "--temp", "0.5",
        "--top-p", "0.85",
        "--top-k", "20",
        "--min-p", "0",
        "--reasoning-budget", "0",
        "--reasoning-format", "none",
        "--chat-template-kwargs", $(if ($PSVersionTable.PSEdition -eq 'Desktop') { '{\"enable_thinking\": false}' } else { '{"enable_thinking": false}' })
    )
}

# BONSAI_CTX=0 or unset both mean "auto" -> RAM-tiered default (never -c 0,
# which would use the model's full training context and OOM constrained boxes).
$CtxDefault = if ($env:BONSAI_CTX -and $env:BONSAI_CTX -ne "0") { $env:BONSAI_CTX } else {
    $MemGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $Ctx0 = if ($MemGB -le 11) { 8192 } elseif ($MemGB -le 23) { 16384 } elseif ($MemGB -le 35) { 32768 } elseif ($MemGB -le 71) { 65536 } elseif ($BonsaiModel -eq "27B") { 131072 } else { 65536 }
    # Best-effort VRAM cap (not a fit guarantee; BONSAI_CTX overrides it). With
    # full GPU offload the KV cache lives in VRAM (27B: ~8.3 GiB fixed + 0.5 GiB
    # FP16 KV per 8192 tokens). Only for a bundled CUDA build with full offload
    # (-ngl >= 99), and only when exactly one NVIDIA GPU is listed. Mirrors
    # bonsai_ctx_default in common.sh.
    $NglInt = 0
    if ($BinRel -like "bin\cuda\*" -and [int]::TryParse($Ngl, [ref]$NglInt) -and $NglInt -ge 99 -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        $VramMiB = 0
        $VramLines = @(& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null)
        if ($VramLines.Count -eq 1 -and [int]::TryParse("$($VramLines[0])".Trim(), [ref]$VramMiB) -and $VramMiB -gt 0) {
            $VCap = if ($VramMiB -lt 10000) { 8192 } elseif ($VramMiB -lt 12000) { 16384 } elseif ($VramMiB -lt 16000) { 32768 } elseif ($VramMiB -lt 24000) { 65536 } else { 0 }
            if ($VCap -gt 0 -and $VCap -lt $Ctx0) { $Ctx0 = $VCap }
        }
    }
    "$Ctx0"
}

Write-Host "[OK] Model:  $($Model.FullName)" -ForegroundColor Green
Write-Host "[OK] Binary: $Bin" -ForegroundColor Green
Write-Host "[OK] Using -ngl $Ngl, -c $CtxDefault (override with BONSAI_CTX, 0 = auto)" -ForegroundColor Green

# A prompt given with -p is a one-shot request, so finish and exit. Without -st,
# llama-cli drops into an interactive session after answering and never returns.
$OneShot = if ($args | Where-Object { $_ -in @("-p", "--prompt") }) { @("-st") } else { @() }

$RunArgs = $CommonArgs + @("-c", $CtxDefault) + $OneShot + $args
& $Bin @RunArgs
exit $LASTEXITCODE
