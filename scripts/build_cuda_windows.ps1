# Build llama.cpp with CUDA on Windows
# Prerequisites: CUDA toolkit (nvcc), CMake, Visual Studio Build Tools (or full VS)
#
# Usage:
#   .\scripts\build_cuda_windows.ps1
#   .\scripts\build_cuda_windows.ps1 -CudaPath "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
#   .\scripts\build_cuda_windows.ps1 -Archs "80;86;89;90"
param(
    [string]$CudaPath = "",
    [string]$Archs = "",
    [string]$RepoDir = ".\llama.cpp",
    [string]$OutputDir = "cuda"
)

$ErrorActionPreference = "Stop"

$Targets = @("llama-cli", "llama-server", "llama-completion", "llama-quantize", "llama-perplexity", "llama-bench")

# ── Clone if needed ──
if (-not (Test-Path $RepoDir)) {
    Write-Host "llama.cpp not found at $RepoDir - cloning from PrismML-Eng ..."
    git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git $RepoDir
}

# ── Find CUDA toolkit ──
if (-not $CudaPath) {
    $nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
    if ($nvcc) {
        $CudaPath = (Split-Path (Split-Path $nvcc.Source))
    } else {
        $defaultPaths = @(
            "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA"
        )
        foreach ($base in $defaultPaths) {
            if (Test-Path $base) {
                $latest = Get-ChildItem $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) {
                    $CudaPath = $latest.FullName
                    break
                }
            }
        }
    }
}

if (-not $CudaPath -or -not (Test-Path $CudaPath)) {
    Write-Host "[ERR] CUDA toolkit not found." -ForegroundColor Red
    Write-Host "      Install from https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
    Write-Host "      Or specify: .\scripts\build_cuda_windows.ps1 -CudaPath 'C:\path\to\cuda'" -ForegroundColor Yellow
    exit 1
}

$Nvcc = Join-Path $CudaPath "bin\nvcc.exe"
if (-not (Test-Path $Nvcc)) {
    Write-Host "[ERR] nvcc not found at $Nvcc" -ForegroundColor Red
    exit 1
}

# ── Detect CUDA version ──
$nvccOutput = & $Nvcc --version 2>&1 | Out-String
if ($nvccOutput -match 'release (\d+)\.(\d+)') {
    $CudaMajor = [int]$Matches[1]
    $CudaMinor = [int]$Matches[2]
    $CudaVersion = "$CudaMajor.$CudaMinor"
} else {
    Write-Host "[ERR] Could not parse CUDA version from nvcc" -ForegroundColor Red
    exit 1
}

# ── Default architectures ──
if (-not $Archs) {
    if ($CudaMajor -ge 13) {
        $Archs = "80;86;89;90;100;120"
    } else {
        $Archs = "80;86;89;90;120"
    }
}

$Dest = Join-Path "bin" $OutputDir
$BuildDir = "build-cuda"

Write-Host ""
Write-Host "=== Building llama.cpp with CUDA $CudaVersion (Windows) ===" -ForegroundColor Cyan
Write-Host "  Repo:   $RepoDir"
Write-Host "  CUDA:   $CudaPath (v$CudaVersion)"
Write-Host "  Archs:  $Archs"
Write-Host "  Output: $Dest"
Write-Host ""

# ── Ensure cmake is available ──
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "[ERR] CMake not found. Install from https://cmake.org/download/" -ForegroundColor Red
    Write-Host "      Or if you ran setup.ps1, activate the venv first:" -ForegroundColor Yellow
    Write-Host "      & .venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    exit 1
}

# ── Configure ──
$env:CUDACXX = $Nvcc
Push-Location $RepoDir

cmake -B $BuildDir `
    -DGGML_CUDA=ON `
    -DCMAKE_CUDA_COMPILER="$Nvcc" `
    -DCMAKE_CUDA_ARCHITECTURES="$Archs" `
    -DCMAKE_BUILD_TYPE=Release

# ── Build ──
$nproc = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildJobs = $nproc

# Detect GPU VRAM; use fewer jobs on low-VRAM machines to avoid OOM during CUDA compilation
try {
    $adapters = Get-CimInstance Win32_VideoController -ErrorAction Stop
    $maxVramBytes = ($adapters | ForEach-Object { [long]$_.AdapterRAM } | Measure-Object -Maximum).Maximum
    if ($maxVramBytes -gt 0) {
        $maxVramGB = [math]::Round($maxVramBytes / 1GB, 1)
        if ($maxVramBytes -lt 16GB) {
            $buildJobs = 2
            Write-Host "  Detected GPU VRAM: ${maxVramGB} GB (< 16 GB) -- limiting CUDA build to -j $buildJobs" -ForegroundColor Yellow
        } else {
            Write-Host "  Detected GPU VRAM: ${maxVramGB} GB -- using -j $buildJobs (logical CPU count)"
        }
    } else {
        Write-Host "  GPU VRAM detection returned 0 or empty -- using -j $buildJobs (logical CPU count)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  GPU VRAM detection failed ($($_.Exception.Message)) -- using -j $buildJobs (logical CPU count)" -ForegroundColor Yellow
}

cmake --build $BuildDir --config Release -j $buildJobs

Pop-Location

# ── Copy binaries ──
Write-Host ""
Write-Host "=== Copying binaries to $Dest ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $Dest -Force | Out-Null

foreach ($bin in $Targets) {
    $src = Join-Path $RepoDir "$BuildDir\bin\Release\$bin.exe"
    if (-not (Test-Path $src)) {
        $src = Join-Path $RepoDir "$BuildDir\bin\$bin.exe"
    }
    if (Test-Path $src) {
        Copy-Item $src -Destination $Dest
        Write-Host "  Copied $bin.exe"
    } else {
        Write-Host "  [WARN] $bin.exe not found" -ForegroundColor Yellow
    }
}

# ── Copy DLLs ──
Write-Host ""
Write-Host "=== Copying shared libraries ===" -ForegroundColor Cyan
$dllPatterns = @("llama.dll", "ggml*.dll")
foreach ($pattern in $dllPatterns) {
    $releasePath = Join-Path $RepoDir "$BuildDir\bin\Release"
    $binPath = Join-Path $RepoDir "$BuildDir\bin"
    foreach ($searchPath in @($releasePath, $binPath)) {
        $dlls = Get-ChildItem -Path $searchPath -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($dll in $dlls) {
            Copy-Item $dll.FullName -Destination $Dest -Force
            Write-Host "  Copied $($dll.Name)"
        }
    }
}

# Copy CUDA runtime DLLs from toolkit
$cudaBinDir = Join-Path $CudaPath "bin"
foreach ($cudaDll in @("cudart64_*.dll", "cublas64_*.dll", "cublasLt64_*.dll")) {
    $found = Get-ChildItem -Path $cudaBinDir -Filter $cudaDll -ErrorAction SilentlyContinue
    foreach ($f in $found) {
        Copy-Item $f.FullName -Destination $Dest -Force
        Write-Host "  Copied $($f.Name) (CUDA runtime)"
    }
}

Write-Host ""
Write-Host "Done! CUDA $CudaVersion Windows binaries are in: $Dest" -ForegroundColor Green
Write-Host ""
Write-Host "Run:" -ForegroundColor Cyan
Write-Host "  `$model = (Get-ChildItem models\gguf\*.gguf | Select-Object -First 1).FullName"
Write-Host "  $Dest\llama-cli.exe -m `$model -ngl 99 -c 0 -p 'Hello'"
