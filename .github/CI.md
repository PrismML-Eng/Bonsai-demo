# CI Workflows

## Workflows

| Workflow | Runs automatically | PR label trigger | Manual trigger |
|----------|-------------------|-----------------|----------------|
| **Platform smoke tests** | No | `smoke-test` | Actions > Manual platform smoke tests > Run workflow |
| **Build from source** | No | `build-test` | Actions > Build from source smoke tests > Run workflow |
| **Em-dash check** | Push to `master` | `check-em-dash` | Actions > Check scripts for em dashes > Run workflow |

## PR Labels

Add these labels to a PR to trigger the corresponding workflow. Only fires when the label is added, not on PR creation or push. To re-run after new commits, remove the label and add it back.

| Label | What it runs |
|-------|-------------|
| `smoke-test` | All always-on platform smoke tests (Linux x86/ARM, Windows x86/ARM, macOS Metal/Intel) |
| `build-test` | Build from source on all platforms (Linux x86/ARM, macOS Metal/Intel) |
| `check-em-dash` | Scans PowerShell scripts for em dash characters |

## Smoke Test Platform Matrix

Always-on (run every time):

| Job | Runner | OS | Arch |
|-----|--------|----|------|
| `linux-x86-cpu` | `ubuntu-latest` | Linux | x64 |
| `linux-arm-cpu` | `ubuntu-24.04-arm` | Linux | arm64 |
| `windows-x86-cpu` | `windows-latest` | Windows | x64 |
| `windows-arm-cpu` | `windows-11-arm` | Windows | arm64 |
| `macos-metal` | `macos-14` | macOS | arm64 (M1) |
| `macos-intel-cpu` | `macos-15-intel` | macOS | x64 |
| `linux-x86-vulkan` | `ubuntu-latest` + lavapipe | Linux | x64 (Vulkan on CPU) |

Optional self-hosted (manual dispatch only, toggle in UI):

| Job | Input toggle | Runner labels |
|-----|-------------|---------------|
| `linux-cuda` | `enable_linux_cuda` | `[self-hosted, Linux, X64, cuda]` |
| `windows-cuda` | `enable_windows_cuda` | `[self-hosted, Windows, X64, cuda]` |
| `linux-amd` | `enable_linux_amd` | `[self-hosted, Linux, X64, amd]` |
| `windows-amd` | `enable_windows_amd` | `[self-hosted, Windows, X64, amd]` |
| `linux-vulkan` | `enable_linux_vulkan` | `[self-hosted, Linux, X64, vulkan]` |
| `windows-vulkan` | `enable_windows_vulkan` | `[self-hosted, Windows, X64, vulkan]` |

## Manual Dispatch Options

When triggering smoke tests via Actions > Run workflow:

| Option | Default | What it does |
|--------|---------|-------------|
| `force_fresh_download` | off | Each job downloads its own model via `setup.sh` instead of using the shared artifact. Use to test the full download path. |
| `enable_linux_cuda` | off | Run on self-hosted Linux CUDA runner |
| `enable_windows_cuda` | off | Run on self-hosted Windows CUDA runner |
| `enable_linux_amd` | off | Run on self-hosted Linux AMD/ROCm runner |
| `enable_windows_amd` | off | Run on self-hosted Windows AMD/HIP runner |
| `enable_linux_vulkan` | off | Run on self-hosted Linux Vulkan runner |
| `enable_windows_vulkan` | off | Run on self-hosted Windows Vulkan runner |

## Build from Source

Tests the `build_*.sh` / `build_*.ps1` scripts by cloning llama.cpp and compiling from source.

Always-on (run every time):

| Job | Runner | Script | What it builds |
|-----|--------|--------|---------------|
| `linux-cpu` | `ubuntu-latest` | `build_cpu_linux.sh` | CPU only (x64) |
| `linux-arm-cpu` | `ubuntu-24.04-arm` | `build_cpu_linux.sh` | CPU only (arm64) |
| `macos-metal` | `macos-14` | `build_mac.sh` | Metal + CPU (Apple Silicon) |
| `macos-intel` | `macos-15-intel` | `build_mac.sh` | CPU only (Intel) |

