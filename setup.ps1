# Bonsai Demo - Setup for Windows (PowerShell)
# Usage:  .\setup.ps1
#   or:   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\setup.ps1
$ErrorActionPreference = "Stop"

$PythonVersion = "3.11"
$VenvDir = Join-Path $PSScriptRoot ".venv"
$VenvPy  = Join-Path $VenvDir "Scripts\python.exe"

$ReleaseTag = "prism-b8796-e2d6742"
$WinAssetTag = "prism-b1-e2d6742"                    # Windows builds use shortened tag
$BaseUrl = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$ReleaseTag"

$BonsaiModel = if ($env:BONSAI_MODEL) { $env:BONSAI_MODEL } else { "8B" }
$HfGgufRepo = "prism-ml/Bonsai-${BonsaiModel}-gguf"

# ── Helpers ──

function Refresh-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $merged  = "$machine;$user;$env:Path"
    $seen = @{}; $unique = @()
    foreach ($p in $merged -split ";") {
        $key = $p.TrimEnd("\").ToLowerInvariant()
        if ($key -and -not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $unique += $p
        }
    }
    $env:Path = $unique -join ";"
}

function Find-CompatiblePython {
    $pyLauncher = Get-Command py -CommandType Application -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        foreach ($minor in @("3.13", "3.12", "3.11")) {
            try {
                $out = & $pyLauncher.Source "-$minor" --version 2>&1 | Out-String
                if ($out -match "Python (3\.1[1-3])\.\d+") {
                    $resolvedExe = (& $pyLauncher.Source "-$minor" -c "import sys; print(sys.executable)" 2>$null | Out-String).Trim()
                    if ($resolvedExe -and (Test-Path $resolvedExe)) {
                        return @{ Version = $Matches[1]; Path = $resolvedExe }
                    }
                }
            } catch {}
        }
    }
    foreach ($name in @("python3", "python")) {
        foreach ($cmd in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
            if (-not $cmd.Source -or $cmd.Source -like "*\WindowsApps\*") { continue }
            try {
                $out = & $cmd.Source --version 2>&1 | Out-String
                if ($out -match "Python (3\.1[1-3])\.\d+") {
                    return @{ Version = $Matches[1]; Path = $cmd.Source }
                }
            } catch {}
        }
    }
    return $null
}

Write-Host ""
Write-Host "========================================="
Write-Host "   Bonsai Demo Setup (Windows)"
Write-Host "   Model: $BonsaiModel"
Write-Host "========================================="
Write-Host ""

# ── 1. Check winget ──
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "[ERR] winget is not available." -ForegroundColor Red
    Write-Host "      Install from https://aka.ms/getwinget or install Python $PythonVersion and uv manually." -ForegroundColor Yellow
    exit 1
}

# ── 2. Python ──
Write-Host "==> Checking Python ..." -ForegroundColor Cyan
$DetectedPython = Find-CompatiblePython
if ($DetectedPython) {
    Write-Host "[OK] Python $($DetectedPython.Version) found." -ForegroundColor Green
} else {
    Write-Host "==> Installing Python $PythonVersion ..." -ForegroundColor Cyan
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { winget install -e --id "Python.Python.$PythonVersion" --accept-package-agreements --accept-source-agreements } catch {}
    $ErrorActionPreference = $prevEAP
    Refresh-SessionPath
    $DetectedPython = Find-CompatiblePython
    if (-not $DetectedPython) {
        Write-Host "[ERR] Python installation failed." -ForegroundColor Red
        Write-Host "      Install Python $PythonVersion from https://www.python.org/downloads/" -ForegroundColor Yellow
        exit 1
    }
}

# ── 3. uv ──
Write-Host "==> Checking uv ..." -ForegroundColor Cyan
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing uv ..." -ForegroundColor Cyan
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { winget install --id=astral-sh.uv -e --accept-package-agreements --accept-source-agreements } catch {}
    $ErrorActionPreference = $prevEAP
    Refresh-SessionPath
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host "    Trying alternative installer ..." -ForegroundColor Yellow
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        Refresh-SessionPath
    }
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "[ERR] uv could not be installed." -ForegroundColor Red
    Write-Host "      Install from https://docs.astral.sh/uv/" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] uv found." -ForegroundColor Green

# ── 4. Create venv ──
Write-Host "==> Setting up Python environment ..." -ForegroundColor Cyan
if (Test-Path $VenvPy) {
    Write-Host "[OK] Existing venv found." -ForegroundColor Green
} else {
    uv venv $VenvDir --python "$($DetectedPython.Path)"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERR] Failed to create venv." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Created venv." -ForegroundColor Green
}

# ── 5. Install Python deps ──
Write-Host "==> Installing Python dependencies ..." -ForegroundColor Cyan
uv pip install --python $VenvPy huggingface-hub
Write-Host "[OK] Dependencies installed." -ForegroundColor Green

# ── 6. Detect GPU: NVIDIA (CUDA) or AMD (HIP) ──
$GpuType = $null
$CudaTag = "12.4"
foreach ($p in @(
    (Get-Command nvidia-smi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
    "$env:SystemRoot\System32\nvidia-smi.exe"
)) {
    if ($p -and (Test-Path $p)) {
        try {
            $out = & $p 2>&1 | Out-String
            if ($out -match 'CUDA Version:\s+(\d+)\.(\d+)') {
                $major = [int]$Matches[1]; $minor = [int]$Matches[2]
                if ($major -gt 12 -or ($major -eq 12 -and $minor -ge 4)) {
                    $CudaTag = "12.4"
                    $GpuType = "cuda"
                } else {
                    Write-Host "[WARN] Detected CUDA $major.$minor - older than 12.4, falling back to CPU." -ForegroundColor Yellow
                    $GpuType = "cpu"
                }
                break
            }
        } catch {}
    }
}
if ($GpuType -eq "cuda") {
    Write-Host "[OK] NVIDIA GPU detected (CUDA $CudaTag)" -ForegroundColor Green
} else {
    # Check for AMD HIP SDK
    $HipPath = $null
    if ($env:HIP_PATH -and (Test-Path $env:HIP_PATH)) {
        $HipPath = $env:HIP_PATH
    }
    if (-not $HipPath) {
        # Check common install locations
        foreach ($candidate in @(
            "$env:ProgramFiles\AMD\ROCm\*\bin\hipcc.exe",
            "$env:ProgramFiles\AMD\ROCm\bin\hipcc.exe"
        )) {
            $found = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $HipPath = $found.DirectoryName; break }
        }
    }
    if (-not $HipPath) {
        $hipCmd = Get-Command hipcc -ErrorAction SilentlyContinue
        if ($hipCmd) { $HipPath = Split-Path $hipCmd.Source }
    }
    if ($HipPath) {
        $GpuType = "hip"
        Write-Host "[OK] AMD HIP/ROCm toolchain found at $HipPath" -ForegroundColor Green
    } elseif (Get-Command vulkaninfo -ErrorAction SilentlyContinue) {
        $GpuType = "vulkan"
        Write-Host "[OK] Vulkan SDK detected." -ForegroundColor Green
    } else {
        $GpuType = "cpu"
        Write-Host "[INFO] No GPU toolchain detected. Will use CPU build." -ForegroundColor Yellow
    }
}

# ── 7. Download GGUF model ──
Write-Host "==> Downloading model ($BonsaiModel) ..." -ForegroundColor Cyan

function Download-GgufModel($Size) {
    $repo = "prism-ml/Bonsai-${Size}-gguf"
    $dir = Join-Path $PSScriptRoot "models\gguf\$Size"
    if (Test-Path "$dir\*.gguf") {
        Write-Host "[OK] GGUF $Size already present." -ForegroundColor Green
        return
    }
    $HfCli = Join-Path $VenvDir "Scripts\hf.exe"
    if (-not (Test-Path $HfCli)) {
        $HfCli = Join-Path $VenvDir "Scripts\huggingface-cli.exe"
    }
    if (-not (Test-Path $HfCli)) {
        Write-Host "[ERR] Hugging Face CLI not found in .venv (expected hf.exe or huggingface-cli.exe)." -ForegroundColor Red
        exit 1
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & $HfCli download $repo --local-dir $dir
    $DownloadExitCode = $LASTEXITCODE
    $DownloadedGguf = Get-ChildItem -Path $dir -Filter "*.gguf" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($DownloadExitCode -ne 0 -or -not $DownloadedGguf) {
        Write-Host "[ERR] Failed to download GGUF $Size. Try running '$HfCli download $repo --local-dir $dir' manually." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] GGUF $Size downloaded." -ForegroundColor Green
}

if ($BonsaiModel -eq "all") {
    foreach ($sz in @("8B", "4B", "1.7B")) { Download-GgufModel $sz }
} else {
    Download-GgufModel $BonsaiModel
}

# ── 8. Download pre-built binaries ──
Write-Host "==> Downloading llama.cpp binaries ..." -ForegroundColor Cyan

function Download-Binary($Asset, $BinDir, $RequiredFile = "llama-cli.exe") {
    if (Test-Path (Join-Path $BinDir $RequiredFile)) {
        Write-Host "[OK] Binaries already present in $BinDir." -ForegroundColor Green
        return
    }
    $Url = "$BaseUrl/$Asset"
    $TmpZip = [System.IO.Path]::GetTempFileName() + ".zip"

    Write-Host "    Downloading $Asset ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $TmpZip -UseBasicParsing

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Expand-Archive -Path $TmpZip -DestinationPath $BinDir -Force
    Remove-Item $TmpZip -Force

    Write-Host "[OK] Binaries installed to $BinDir" -ForegroundColor Green
}

# Detect Windows architecture
$WinArch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "arm64" } else { "x64" }

# GPU backends only have x64 builds - fall back to CPU on ARM64
if ($WinArch -eq "arm64" -and $GpuType -ne "cpu") {
    Write-Host "[WARN] $GpuType detected but no ARM64 build available - falling back to CPU." -ForegroundColor Yellow
    $GpuType = "cpu"
}

if ($GpuType -eq "hip") {
    $BinDir = Join-Path $PSScriptRoot "bin\hip"
    Download-Binary "llama-bin-win-hip-radeon-x64.zip" $BinDir
} elseif ($GpuType -eq "cuda") {
    $BinDir = Join-Path $PSScriptRoot "bin\cuda"
    Download-Binary "llama-${WinAssetTag}-bin-win-cuda-${CudaTag}-x64.zip" $BinDir

    # Also download CUDA runtime DLLs
    $DllAsset = "cudart-llama-bin-win-cuda-${CudaTag}-x64.zip"
    $DllUrl = "$BaseUrl/$DllAsset"
    $DllZip = [System.IO.Path]::GetTempFileName() + ".zip"

    Write-Host "    Downloading CUDA runtime DLLs ..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $DllUrl -OutFile $DllZip -UseBasicParsing
        Expand-Archive -Path $DllZip -DestinationPath $BinDir -Force
        Remove-Item $DllZip -Force
    } catch {
        Write-Host "[WARN] Could not download CUDA DLLs. You may need to install CUDA toolkit." -ForegroundColor Yellow
    }
} elseif ($GpuType -eq "vulkan") {
    $BinDir = Join-Path $PSScriptRoot "bin\vulkan"
    Download-Binary "llama-bin-win-cpu-${WinArch}.zip" $BinDir "llama-cli.exe"
    Download-Binary "llama-bin-win-vulkan-x64.zip" $BinDir "ggml-vulkan.dll"
} else {
    # CPU fallback (arch-aware)
    $BinDir = Join-Path $PSScriptRoot "bin\cpu"
    Download-Binary "llama-bin-win-cpu-${WinArch}.zip" $BinDir
}

# ── Done ──
Write-Host ""
Write-Host "========================================="
Write-Host "   Setup complete! (BONSAI_MODEL=$BonsaiModel)"
Write-Host "========================================="
Write-Host ""
Write-Host "  See README.md for usage examples." -ForegroundColor Cyan
Write-Host ""
