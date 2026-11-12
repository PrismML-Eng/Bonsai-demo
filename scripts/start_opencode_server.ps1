$ErrorActionPreference = "Stop"

if (-not $env:BONSAI_FAMILY) { $env:BONSAI_FAMILY = "bonsai2" }
if (-not $env:BONSAI_MODEL) { $env:BONSAI_MODEL = "27B" }
if ($env:BONSAI_FAMILY -ne "bonsai2" -or $env:BONSAI_MODEL -ne "27B") {
    Write-Error "The OpenCode profile requires BONSAI_FAMILY=bonsai2 and BONSAI_MODEL=27B."
    exit 1
}

# Match the OpenCode model profile's declared usable input budget.
if (-not $env:BONSAI_CTX -or $env:BONSAI_CTX -eq "0") { $env:BONSAI_CTX = "262144" }
$Budget = if ($env:BONSAI_OPENCODE_REASONING_BUDGET) { $env:BONSAI_OPENCODE_REASONING_BUDGET } else { "2048" }
if ($Budget -notmatch '^\d+$' -or [int64]$Budget -lt 1) {
    Write-Error "BONSAI_OPENCODE_REASONING_BUDGET must be a positive integer."
    exit 1
}

Write-Host "=== OpenCode profile: context $env:BONSAI_CTX, reasoning budget $Budget, single slot ==="
Write-Host "  OpenCode model id: bonsai2-27b-opencode"
Write-Host "  Start OpenCode from this repository so its .opencode profile is loaded."
& (Join-Path $PSScriptRoot "start_llama_server.ps1") `
    --reasoning-format deepseek `
    --reasoning-budget $Budget `
    --parallel 1 `
    --alias "bonsai2-27b-opencode" `
    @args
exit $LASTEXITCODE
