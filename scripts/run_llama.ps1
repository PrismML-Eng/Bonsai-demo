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

if ($BonsaiFamily -eq "ternary") {
    $ModelDir = Join-Path $DemoDir "models\ternary-gguf\$BonsaiModel"

    $FamilyDisplay = "Ternary-Bonsai"
} else {
    $ModelDir = Join-Path $DemoDir "models\gguf\$BonsaiModel"
    $FamilyDisplay = "Bonsai"
}

# Select exactly the demo quant for the family (a leftover F16 or g64 file
# must never be picked up).
$QuantPattern = if ($BonsaiFamily -eq "ternary") { "*-Q2_0.gguf" } else { "*-Q1_0.gguf" }
$Model = Get-ChildItem -Path $ModelDir -Filter $QuantPattern -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*mmproj*" -and $_.Name -notlike "*dspark*" -and $_.Name -notlike "*kv-bias*" } |
    Select-Object -First 1
if (-not $Model) {
    Write-Host "[ERR] GGUF model not found for $FamilyDisplay-$BonsaiModel in $ModelDir" -ForegroundColor Red
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

# 27B: reference-demo sampling, thinking stays enabled (model default).
# Older sizes keep the exact flag set they were tested with.
if ($BonsaiModel -eq "27B") {
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

$CtxDefault = if ($env:BONSAI_CTX) { $env:BONSAI_CTX } else {
    $MemGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($MemGB -le 11) { "8192" } elseif ($MemGB -le 23) { "16384" } elseif ($MemGB -le 35) { "32768" } elseif ($MemGB -le 71) { "65536" } elseif ($BonsaiModel -eq "27B") { "131072" } else { "65536" }
}

Write-Host "[OK] Model:  $($Model.FullName)" -ForegroundColor Green
Write-Host "[OK] Binary: $Bin" -ForegroundColor Green
Write-Host "[OK] Using -ngl $Ngl, -c $CtxDefault (override with BONSAI_CTX, 0 = auto-fit)" -ForegroundColor Green

$RunArgs = $CommonArgs + @("-c", $CtxDefault) + $args
& $Bin @RunArgs
$ExitCode = $LASTEXITCODE

# The 8192 retry exists only for builds that reject auto-fit (-c 0); any other
# failure must surface as-is instead of rerunning the prompt.
if ($ExitCode -ne 0 -and $CtxDefault -eq "0" -and $ExitCode -notin @(130, -1073741510) -and -not $HasContextArg) {
    Write-Host "[WARN] Auto-fit not supported, falling back to -c 8192" -ForegroundColor Yellow
    $FallbackArgs = $CommonArgs + @("-c", "8192") + $args
    & $Bin @FallbackArgs
    exit $LASTEXITCODE
}

exit $ExitCode
