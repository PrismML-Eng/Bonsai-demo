$ErrorActionPreference = "Stop"


$BonsaiModel  = if ($env:BONSAI_MODEL)  { $env:BONSAI_MODEL.ToUpperInvariant() } else { "27B" }
$BonsaiFamily = if ($env:BONSAI_FAMILY) { $env:BONSAI_FAMILY.ToLowerInvariant() } else { "ternary" }

if ($BonsaiModel -notin @("27B", "8B", "4B", "1.7B")) {
    Write-Host "[ERR] Unknown BONSAI_MODEL='$BonsaiModel'. Valid values: 27B, 8B, 4B, 1.7B" -ForegroundColor Red
    exit 1
}
if ($BonsaiFamily -notin @("bonsai", "ternary")) {
    Write-Host "[ERR] Unknown BONSAI_FAMILY='$BonsaiFamily'. Valid values: bonsai, ternary" -ForegroundColor Red
    exit 1
}

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

# Bind to localhost by default; override with BONSAI_HOST=0.0.0.0 for LAN/remote.
$HostAddress = if ($env:BONSAI_HOST) { $env:BONSAI_HOST } else { "127.0.0.1" }
$Port = 8080

try {
    $null = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 2
    Write-Host "[WARN] Health endpoint responded on port $Port; llama-server may already be running." -ForegroundColor Yellow
    exit 1
} catch {}

if ($BonsaiFamily -eq "ternary") {
    $ModelDir = Join-Path $DemoDir "models\ternary-gguf\$BonsaiModel"

    $FamilyDisplay = "Ternary-Bonsai"
} else {
    $ModelDir = Join-Path $DemoDir "models\gguf\$BonsaiModel"
    $FamilyDisplay = "Bonsai"
}

$Display = "$FamilyDisplay-$BonsaiModel"
# Select exactly the demo quant for the family (a leftover F16 or g64 file
# must never be picked up).
$QuantPattern = if ($BonsaiFamily -eq "ternary") { "*-Q2_0.gguf" } else { "*-Q1_0.gguf" }
$Model = Get-ChildItem -Path $ModelDir -Filter $QuantPattern -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*mmproj*" -and $_.Name -notlike "*dspark*" -and $_.Name -notlike "*kv-bias*" } |
    Select-Object -First 1
if (-not $Model) {
    Write-Host "[ERR] No $QuantPattern model found for $Display in $ModelDir" -ForegroundColor Red

    Write-Host "      Run .\setup.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Vision: use the multimodal projector when present (27B is a VLM).
$Mmproj = Get-ChildItem -Path $ModelDir -Filter *mmproj*.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($BonsaiModel -eq "27B" -and -not $Mmproj) {
    Write-Host "[WARN] No mmproj file found in $ModelDir - image input disabled." -ForegroundColor Yellow
    Write-Host "       Re-run setup.ps1 to fetch it." -ForegroundColor Yellow
}

$BinCandidates = @(
    "bin\cuda\llama-server.exe",
    "bin\hip\llama-server.exe",
    "bin\vulkan\llama-server.exe",
    "bin\cpu\llama-server.exe",
    "llama.cpp\build\bin\Release\llama-server.exe",
    "llama.cpp\build\bin\llama-server.exe"
)
$BinRel = $BinCandidates | Where-Object { Test-Path (Join-Path $DemoDir $_) } | Select-Object -First 1
if (-not $BinRel) {
    Write-Host "[ERR] llama-server.exe not found. Run .\setup.ps1 first." -ForegroundColor Red
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

Write-Host ""
Write-Host "=== llama.cpp server (GGUF) ==="
Write-Host "  Model:   $($Model.Name)"
Write-Host "  Binary:  $Bin"
Write-Host "  Context: auto-fit (-c 0)"
Write-Host ""
Write-Host "  Open http://localhost:$Port in your browser to chat."
Write-Host "  API:  http://localhost:$Port/v1/chat/completions"
Write-Host "  Press Ctrl+C to stop."
Write-Host ""

$ChatTemplateKwargs = if ($PSVersionTable.PSEdition -eq 'Desktop') { '{\"enable_thinking\": false}' } else { '{"enable_thinking": false}' }

$ServerArgs = @(
    "-m", $Model.FullName,
    "--host", $HostAddress,
    "--port", "$Port",
    "-ngl", $Ngl, "-fa", "on",
    "-c", "0",
    "--temp", "0.5",
    "--top-p", "0.85",
    "--top-k", "20",
    "--min-p", "0",
    "--reasoning-budget", "0",
    "--reasoning-format", "none",
    "--chat-template-kwargs", $ChatTemplateKwargs
)

# 27B: --jinja enables native OpenAI-style tool calling; --mmproj enables
# image input; sampling matches the 27B reference demo (temp 0.7, top-p 0.95);
# thinking stays enabled (reasoning overrides removed).
# Older sizes keep the exact flag set they were tested with.
if ($BonsaiModel -eq "27B") {
    # Speculative decoding (opt-in, BONSAI_SPECULATIVE=1): pair the target with
    # its dspark drafter for ~1.8-2x decode on code/reasoning. Disables
    # prompt-cache reuse and forces a single slot, so it is off by default and
    # lives on this standalone server, not the agentic Open WebUI path.
    $Ctx = "0"
    $SpecArgs = @()
    if ($env:BONSAI_SPECULATIVE -eq "1") {
        $Drafter = Get-ChildItem -Path $ModelDir -Filter *dspark-Q4_1*.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Drafter) {
            $Nmax = if ($env:BONSAI_SPEC_NMAX) { $env:BONSAI_SPEC_NMAX } else { "4" }
            $SpecArgs = @("-md", $Drafter.FullName, "--spec-type", "draft-dspark", "--spec-draft-n-max", $Nmax, "-ngld", "999", "-np", "1")
            # dspark re-prefills every request; give the model room to think.
            $Ctx = "16384"
            Write-Host "  Speculative: $($Drafter.Name) (draft-dspark, n-max $Nmax)" -ForegroundColor Green
        } else {
            Write-Host "[WARN] BONSAI_SPECULATIVE=1 but no *dspark-Q4_1*.gguf drafter in $ModelDir - running without speculation." -ForegroundColor Yellow
        }
    }
    $ServerArgs = @(
        "-m", $Model.FullName,
        "--host", $HostAddress,
        "--port", "$Port",
        "-ngl", $Ngl, "-fa", "on",
        "-c", $Ctx,
        "--temp", "0.7",
        "--top-p", "0.95",
        "--top-k", "20",
        "--min-p", "0",
        "--jinja"
    )
    if ($Mmproj) { $ServerArgs += @("--mmproj", $Mmproj.FullName) }
    if ($SpecArgs.Count -gt 0) { $ServerArgs += $SpecArgs }
    # Image-token cap: big images cost minutes of prefill on slower hardware.
    # Capped at 1024 unless running the CUDA/HIP build; override with
    # BONSAI_IMAGE_MAX_TOKENS (a number, or 0 to disable the cap).
    $ImageMaxTokens = if ($env:BONSAI_IMAGE_MAX_TOKENS) {
        if ($env:BONSAI_IMAGE_MAX_TOKENS -eq "0") { $null } else { $env:BONSAI_IMAGE_MAX_TOKENS }
    } elseif ($BinRel -like "bin\cuda\*" -or $BinRel -like "bin\hip\*") {
        $null
    } else {
        "1024"
    }
    if ($ImageMaxTokens) { $ServerArgs += @("--image-max-tokens", $ImageMaxTokens) }
    # Default MCP tool servers for the built-in web UI (user can still edit
    # them in Settings -> MCP Client).
    $WebuiConfig = Join-Path $PSScriptRoot "webui-config.json"
    if (Test-Path $WebuiConfig) { $ServerArgs += @("--webui-config-file", $WebuiConfig) }
}

& $Bin @ServerArgs @args
exit $LASTEXITCODE
