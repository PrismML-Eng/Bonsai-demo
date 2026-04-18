$ErrorActionPreference = "Stop"

$BonsaiModel = if ($env:BONSAI_MODEL) { $env:BONSAI_MODEL } else { "8B" }
if ($BonsaiModel -notin @("8B", "4B", "1.7B")) {
    Write-Host "[ERR] Unknown BONSAI_MODEL='$BonsaiModel'. Valid values: 8B, 4B, 1.7B" -ForegroundColor Red
    exit 1
}

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

$HostAddress = "0.0.0.0"
$Port = 8080

try {
    $null = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 2
    Write-Host "[WARN] Health endpoint responded on port $Port; llama-server may already be running." -ForegroundColor Yellow
    exit 1
} catch {}

$ModelDir = Join-Path $DemoDir "models\gguf\$BonsaiModel"
$Model = Get-ChildItem -Path $ModelDir -Filter *.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Model) {
    Write-Host "[ERR] GGUF model not found for Bonsai-$BonsaiModel in $ModelDir" -ForegroundColor Red
    Write-Host "      Run .\setup.ps1 first." -ForegroundColor Yellow
    exit 1
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

$ChatTemplateKwargs = if ($IsWindows) { '{\"enable_thinking\": false}' } else { '{"enable_thinking": false}' }

$ServerArgs = @(
    "-m", $Model.FullName,
    "--host", $HostAddress,
    "--port", "$Port",
    "-ngl", $Ngl,
    "-c", "0",
    "--temp", "0.5",
    "--top-p", "0.85",
    "--top-k", "20",
    "--min-p", "0",
    "--reasoning-budget", "0",
    "--reasoning-format", "none",
    "--chat-template-kwargs", $ChatTemplateKwargs
)

& $Bin @ServerArgs @args
exit $LASTEXITCODE
