# Sampling flags for small Bonsai 2 models; caller appends user overrides.
function Get-SmallBonsaiSampling {
    $thinking = if ($env:BONSAI_THINKING) { $env:BONSAI_THINKING } else { "1" }
    if ($thinking -notin @("0", "1")) { throw "BONSAI_THINKING must be 0 or 1" }
    $temp = if ($thinking -eq "0") { "0.7" } else { "1.0" }
    $topP = if ($thinking -eq "0") { "0.8" } else { "0.95" }
    $presence = if ($thinking -eq "0") { "1.5" } else { "1.0" }
    $sampling = @("--temp", $temp, "--top-p", $topP, "--top-k", "20", "--min-p", "0",
        "--presence-penalty", $presence, "--repeat-penalty", "1.0", "--repeat-last-n", "64")
    if ($thinking -eq "0") {
        $template = if ($PSVersionTable.PSEdition -eq 'Desktop') { '{\"enable_thinking\":false}' } else { '{"enable_thinking":false}' }
        $sampling += @("--chat-template-kwargs", $template)
    }
    return $sampling
}
