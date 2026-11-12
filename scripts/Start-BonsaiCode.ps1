$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ServerScript = Join-Path $PSScriptRoot "start_opencode_server.ps1"
$ModelId = "bonsai2-27b-opencode"
$ModelsUrl = "http://127.0.0.1:8080/v1/models"
$Ready = $false

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Error "OpenCode was not found on PATH. Install it or add its executable to PATH, then retry."
    exit 1
}

$Models = $null
try {
    $Models = Invoke-RestMethod -Uri $ModelsUrl -TimeoutSec 3
} catch {
    # No compatible API is listening yet; start the dedicated local server below.
}

if ($null -ne $Models) {
    if (@($Models.data | Where-Object { $_.id -eq $ModelId }).Count -eq 0) {
        Write-Error "Port 8080 is serving a different model. Stop that server or configure the Bonsai OpenCode profile for its model."
        exit 2
    }
    $Ready = $true
}

$TimeoutSeconds = if ($env:BONSAI_START_TIMEOUT) { $env:BONSAI_START_TIMEOUT } else { "900" }
if ($TimeoutSeconds -notmatch '^\d{1,5}$' -or [int]$TimeoutSeconds -lt 30 -or [int]$TimeoutSeconds -gt 3600) {
    Write-Error "BONSAI_START_TIMEOUT must be between 30 and 3600 seconds."
    exit 1
}

if (-not $Ready) {
    $PowerShellExe = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" })
    if (-not (Test-Path $PowerShellExe)) {
        Write-Error "Could not find the PowerShell executable at $PowerShellExe."
        exit 1
    }

    $QuotedServerScript = '"' + $ServerScript + '"'
    $ServerProcess = Start-Process -FilePath $PowerShellExe `
        -ArgumentList "-NoLogo -NoProfile -File $QuotedServerScript" `
        -WorkingDirectory $RepoRoot `
        -PassThru

    Write-Host "Starting Bonsai 2 27B. Waiting up to $TimeoutSeconds seconds for the model to load..."
    $Deadline = [DateTime]::UtcNow.AddSeconds([int]$TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        $ServerProcess.Refresh()
        if ($ServerProcess.HasExited) {
            Write-Error "The Bonsai server exited before becoming ready. Check its PowerShell window for the startup error."
            exit 3
        }

        try {
            $Models = Invoke-RestMethod -Uri $ModelsUrl -TimeoutSec 3
            if (@($Models.data | Where-Object { $_.id -eq $ModelId }).Count -gt 0) {
                $Ready = $true
                break
            }
        } catch {
            # The server is still loading or has not opened its API port.
        }

        Start-Sleep -Seconds 2
        $Remaining = [math]::Max(0, [int]($Deadline - [DateTime]::UtcNow).TotalSeconds)
        Write-Progress -Activity "Loading Bonsai 2 27B" `
            -Status "$Remaining seconds remaining; server logs are in the other PowerShell window" `
            -PercentComplete (100 * (1 - $Remaining / [int]$TimeoutSeconds))
    }
    Write-Progress -Activity "Loading Bonsai 2 27B" -Completed

    if (-not $Ready) {
        Write-Error "Bonsai did not become ready before the timeout. The server window is left open so you can inspect it."
        exit 4
    }
}

Write-Host "Bonsai is ready. Opening OpenCode in $RepoRoot."
Set-Location $RepoRoot
& opencode .
exit $LASTEXITCODE
