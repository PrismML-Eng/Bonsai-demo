# GitHub Actions Runner Reference

Reference for all available GitHub-hosted runner labels, specs, and larger runner options.

Source: [actions/runner-images](https://github.com/actions/runner-images) and [GitHub Docs](https://docs.github.com/en/actions/reference/runners)

## Standard Runners (all plans)

These are available on all GitHub plans. Public repos get more resources than private repos.

### Linux (Ubuntu)

| Label | Arch | vCPU (public / private) | RAM (public / private) | Storage |
|-------|------|-------------------------|------------------------|---------|
| `ubuntu-latest` / `ubuntu-24.04` | x64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `ubuntu-22.04` | x64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `ubuntu-24.04-arm` | arm64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `ubuntu-22.04-arm` | arm64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `ubuntu-slim` | x64 | 1 | 5 GB | 14 GB |

### Windows

| Label | Arch | vCPU (public / private) | RAM (public / private) | Storage |
|-------|------|-------------------------|------------------------|---------|
| `windows-latest` / `windows-2025` | x64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `windows-2022` | x64 | 4 / 2 | 16 GB / 8 GB | 14 GB |
| `windows-11-arm` | arm64 | 4 / 2 | 16 GB / 8 GB | 14 GB |

### macOS

| Label | Arch | vCPU | RAM | Storage |
|-------|------|------|-----|---------|
| `macos-latest` / `macos-15` | arm64 (M1) | 3 | 7 GB | 14 GB |
| `macos-14` | arm64 (M1) | 3 | 7 GB | 14 GB |
| `macos-26` | arm64 (M1) | 3 | 7 GB | 14 GB |
| `macos-15-intel` | x64 (Intel) | 4 | 14 GB | 14 GB |
| `macos-26-intel` | x64 (Intel) | 4 | 14 GB | 14 GB |
| `macos-14-large` | x64 (Intel) | -- | -- | 14 GB |

**Notes:**
- `macos-latest` currently points to `macos-15` (ARM64 M1)
- `macos-13` has been removed; use `macos-15-intel` for Intel macOS
- `macos-14` and `macos-15` without suffix are ARM64 (Apple Silicon)
- Intel macOS is available via `-intel` suffix labels

## Larger Runners (Team / Enterprise plans)

Larger runners provide more vCPU, RAM, and storage. They require a GitHub Team or Enterprise Cloud plan and must be configured in org settings (Settings > Actions > Runners).

### Linux (Ubuntu) - Larger

| vCPU | RAM | Storage | Architectures |
|------|-----|---------|---------------|
| 4 | 16 GB | 150 GB | x64, arm64 |
| 8 | 32 GB | 300 GB | x64, arm64 |
| 16 | 64 GB | 600 GB | x64, arm64 |
| 32 | 128 GB | 1200 GB | x64, arm64 |
| 64 | 256 GB (x64) / 208 GB (arm64) | 2040 GB | x64, arm64 |
| 96 | 384 GB | 2040 GB | x64 only |

Larger runner labels are assigned when you create them in org settings. Naming convention typically follows `ubuntu-latest-N-cores`.

### Windows - Larger

| vCPU | RAM | Storage | Architectures | Notes |
|------|-----|---------|---------------|-------|
| 4 | 16 GB | 150 GB | x64, arm64 | Windows Server 2025 or Windows 11 Desktop only |
| 8 | 32 GB | 300 GB | x64, arm64 | |
| 16 | 64 GB | 600 GB | x64, arm64 | |
| 32 | 128 GB | 1200 GB | x64, arm64 | |
| 64 | 256 GB (x64) / 208 GB (arm64) | 2040 GB | x64, arm64 |
| 96 | 384 GB | 2040 GB | x64 only |

### macOS - Larger

| Size | Arch | vCPU | RAM | Storage | Labels |
|------|------|------|-----|---------|--------|
| Large | x64 (Intel) | 12 | 30 GB | 14 GB | `macos-latest-large`, `macos-14-large`, `macos-15-large`, `macos-26-large` |
| XLarge | arm64 (M2 Pro) | 5 + 8 GPU cores | 14 GB | 14 GB | `macos-latest-xlarge`, `macos-14-xlarge`, `macos-15-xlarge`, `macos-26-xlarge` |

**Notes:**
- The M2 Pro XLarge runner has 5 CPU cores + 8 GPU acceleration cores
- XLarge is in public preview

## GPU Runners (Team / Enterprise plans)

GPU runners must be configured in org settings. You assign a custom label when creating the runner.

| vCPU | GPU | Card | RAM | VRAM | Storage | OS |
|------|-----|------|-----|------|---------|-----|
| 4 | 1 | NVIDIA Tesla T4 | 28 GB | 16 GB | 176 GB | Ubuntu, Windows |

**No AMD GPU runners are currently available as GitHub-hosted options.** For AMD ROCm or HIP testing, self-hosted runners are required.

## Summary: What's Available Without Setup

These runners work out of the box on any GitHub plan:

| Platform | Label | Arch | GPU |
|----------|-------|------|-----|
| Linux x64 | `ubuntu-latest` | x64 | No |
| Linux ARM64 | `ubuntu-24.04-arm` | arm64 | No |
| Windows x64 | `windows-latest` | x64 | No |
| Windows ARM64 | `windows-11-arm` | arm64 | No |
| macOS Apple Silicon | `macos-latest` | arm64 (M1) | Metal |
| macOS Intel | `macos-15-intel` | x64 | No |

## What Requires Org Setup

| What | Requirement | Notes |
|------|-------------|-------|
| Larger CPU runners (4+ cores) | Team / Enterprise plan | Custom labels assigned in org settings |
| macOS Large (12-core Intel) | Team / Enterprise plan | Use `macos-latest-large` label |
| macOS XLarge (M2 Pro) | Team / Enterprise plan | Use `macos-latest-xlarge` label |
| GPU runner (T4) | Team / Enterprise plan | NVIDIA Tesla T4 only; custom label |
| AMD/ROCm GPU | Self-hosted runner | No GitHub-hosted option |
| Multi-GPU | Self-hosted runner | No GitHub-hosted option |
