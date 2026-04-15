$ErrorActionPreference = "Stop"

$BonsaiModel = if ($env:BONSAI_MODEL) { $env:BONSAI_MODEL } else { "8B" }
if ($BonsaiModel -notin @("8B", "4B", "1.7B")) {
    Write-Host "[ERR] Unknown BONSAI_MODEL='$BonsaiModel'. Valid values: 8B, 4B, 1.7B" -ForegroundColor Red
    exit 1
}

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

$ModelDir = Join-Path $DemoDir "models\gguf\$BonsaiModel"
$Model = Get-ChildItem -Path $ModelDir -Filter *.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Model) {
    Write-Host "[ERR] GGUF model not found for Bonsai-$BonsaiModel in $ModelDir" -ForegroundColor Red
    Write-Host "      Run .\setup.ps1 first." -ForegroundColor Yellow
    exit 1
}

$BinCandidates = @(
    "bin\cuda\llama-cli.exe",
    "bin\hip\llama-cli.exe",
    "bin\vulkan\llama-cli.exe",
    "bin\cpu\llama-cli.exe",
    "llama.cpp\build\bin\Release\llama-cli.exe",
    "llama.cpp\build\bin\llama-cli.exe"
)
$BinRel = $BinCandidates | Where-Object { Test-Path (Join-Path $DemoDir $_) } | Select-Object -First 1
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

$ContextFlags = @("-c", "--ctx-size")
$HasContextArg = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -in $ContextFlags) {
        $HasContextArg = $true
        break
    }
}

$CommonArgs = @(
    "-m", $Model.FullName,
    "-ngl", $Ngl,
    "--log-disable",
    "--temp", "0.5",
    "--top-p", "0.85",
    "--top-k", "20",
    "--min-p", "0",
    "--reasoning-budget", "0",
    "--reasoning-format", "none",
    "--chat-template-kwargs", '{"enable_thinking": false}'
)

Write-Host "[OK] Model:  $($Model.FullName)" -ForegroundColor Green
Write-Host "[OK] Binary: $Bin" -ForegroundColor Green
Write-Host "[OK] Using -ngl $Ngl, -c 0 (auto-fit to available memory)" -ForegroundColor Green

$RunArgs = $CommonArgs + @("-c", "0") + $args
& $Bin @RunArgs
$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0 -and $ExitCode -notin @(130, -1073741510) -and -not $HasContextArg) {
    Write-Host "[WARN] Auto-fit not supported, falling back to -c 8192" -ForegroundColor Yellow
    $FallbackArgs = $CommonArgs + @("-c", "8192") + $args
    & $Bin @FallbackArgs
    exit $LASTEXITCODE
}

exit $ExitCode
