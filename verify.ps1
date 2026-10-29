#requires -Version 7.0
param(
    [string]$Godot = 'D:\a_my_vibe_coding\codex_work\xiuxian-world\.tools\godot\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$IncludeGui
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Godot 4.7.2 console executable was not found. Set -Godot.' }
$evidenceRoot = Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

function Invoke-S1Engine([string[]]$Arguments) {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Godot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Could not start Godot.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(300000)) {
        $process.Kill($true)
        $process.Dispose()
        throw 'Godot check exceeded five minutes; its test process was stopped.'
    }
    $result = [pscustomobject]@{ code = $process.ExitCode; lines = ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()) -split "`r?`n" }
    $process.Dispose()
    return $result
}

function Invoke-S1Check([string]$Name, [string]$Script, [string]$Marker) {
    $arguments = @('--headless', '--path', $projectRoot, '--log-file', (Join-Path $evidenceRoot ($Name + '.log')), '--script', ('res://tests/' + $Script))
    $execution = Invoke-S1Engine $arguments
    $lines = $execution.lines
    $code = $execution.code
    $lines | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:') -or -not ($lines -match $Marker)) {
        throw "$Name did not pass. Read evidence/$Name.log."
    }
}

Invoke-S1Check 'core' 'test_core.gd' 'CORE_RESULT checks=\d+ failures=0'
Invoke-S1Check 'save' 'test_save.gd' 'SAVE_RESULT checks=\d+ failures=0'
Invoke-S1Check 'acceptance' 'test_acceptance.gd' 'E03 PASS'
Invoke-S1Check 'benchmark' 'benchmark.gd' 'S1-AC24 PASS'

$guiFiles = @()
if ($IncludeGui) {
    foreach ($small in @($false, $true)) {
        $suffix = if ($small) { '-small' } else { '' }
        $arguments = @('--path', $projectRoot, '--log-file', (Join-Path $evidenceRoot ('ui' + $suffix + '.log')), 'res://ui/main.tscn', '--', '--ui-test')
        if ($small) { $arguments += '--small-ui' }
        $execution = Invoke-S1Engine $arguments
        $lines = $execution.lines
        $code = $execution.code
        $lines | ForEach-Object { Write-Host $_ }
        if ($code -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:') -or -not ($lines -match 'S1_UI_PASS')) { throw 'GUI verification failed.' }
        $guiFiles += 'ui' + $suffix + '.json'
    }
}

$acceptance = Get-Content -LiteralPath (Join-Path $evidenceRoot 'acceptance.json') -Raw | ConvertFrom-Json
$benchmark = Get-Content -LiteralPath (Join-Path $evidenceRoot 'benchmark.json') -Raw | ConvertFrom-Json
$results = @()
foreach ($scenario in $acceptance.scenarios) {
    $row = [ordered]@{ scenario_id = $scenario.scenario_id; status = $scenario.status; evidence = 'acceptance.json'; assertions = $scenario.assertions.Count }
    if ($scenario.scenario_id -eq 'S1-AC24') {
        $row.status = $benchmark.status
        $row.evidence = 'benchmark.json'
        $row.assertions = $benchmark.samples.Count
    }
    if ($scenario.scenario_id -eq 'S1-AC23' -and $IncludeGui) {
        $guiPass = $true
        $guiChecks = 0
        foreach ($guiName in $guiFiles) {
            $gui = Get-Content -LiteralPath (Join-Path $evidenceRoot $guiName) -Raw | ConvertFrom-Json
            $guiPass = $guiPass -and ($gui.status -eq 'PASS')
            $guiChecks += $gui.checks.Count
        }
        $row.status = if ($guiPass) { 'PASS' } else { 'FAIL' }
        $row.evidence = $guiFiles
        $row.assertions = $guiChecks
    }
    $results += [pscustomobject]$row
}
$sourceHashes = @()
foreach ($folder in @('core', 'ui', 'tests')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -File -Recurse | Where-Object { $_.Extension -in @('.gd', '.tscn') }) {
        $sourceHashes += [ordered]@{ file = $file.FullName.Substring($projectRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
}
$sourceHashes += [ordered]@{ file = 'project.godot'; sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'project.godot') -Algorithm SHA256).Hash }
$failed = @($results | Where-Object { $_.status -eq 'FAIL' }).Count
$notRun = @($results | Where-Object { $_.status -eq 'NOT_RUN' }).Count
$summary = [ordered]@{
    build = 's1-build.1'; rules = 's1-rules.1'; spec = 's1-spec.1'
    executed_at = (Get-Date).ToString('o'); passed = @($results | Where-Object { $_.status -eq 'PASS' }).Count
    failed = $failed; not_run = $notRun; scenarios = $results; source_hashes = $sourceHashes
    scope = 'S1 foundation and directed fixtures only. Not full gameplay, AI or graphics performance.'
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'summary.json') -Encoding utf8
if ($failed -gt 0) { throw "$failed scenarios failed." }
Write-Host ('S1 verification: {0} PASS, {1} FAIL, {2} NOT_RUN.' -f $summary.passed, $failed, $notRun)
if (-not $IncludeGui) { Write-Host 'Run with -IncludeGui to execute AC23 and capture both window sizes.' }
