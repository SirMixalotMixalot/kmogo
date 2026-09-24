#Requires -Version 5.1
<#
.SYNOPSIS
Validate Kmogo's Docker setup and save evidence under results/.
.DESCRIPTION
Builds/tests the runner, runs three index experiment cycles, then destroys and
recreates ONLY the kmogo-mp1 Compose development database volume. Existing data
in that development database is reset. PostgreSQL remains healthy afterwards.
Run from your normal terminal with Docker Desktop's Linux engine running.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$nl = [Environment]::NewLine
$repo = Split-Path -Parent $PSScriptRoot
$relativeOutput = 'results/docker-validation-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$outputPath = Join-Path $repo $relativeOutput
if (Test-Path -LiteralPath $outputPath) { throw 'Evidence directory already exists; retry in a second.' }
[IO.Directory]::CreateDirectory($outputPath) | Out-Null
$logPath = Join-Path $outputPath 'commands.log'
$composeArgs = @('compose', '--project-name', 'kmogo-mp1', '--project-directory', $repo,
    '--file', (Join-Path $repo 'docker-compose.yml'))
$priorRevision = $env:KMOGO_REVISION
$record = [ordered]@{
    status = 'running'
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    source_revision = $null
    powershell_version = $PSVersionTable.PSVersion.ToString()
    checks = [ordered]@{}
    cycles = @()
}
$exitCode = 0

function Invoke-Docker {
    param([Parameter(Mandatory=$true)][string[]]$Arguments, [switch]$Capture)
    $command = 'docker ' + ($Arguments -join ' ')
    Write-Host ($nl + '> ' + $command) -ForegroundColor Cyan
    Add-Content -LiteralPath $logPath -Value ($nl + (Get-Date).ToUniversalTime().ToString('o') + ' ' + $command)
    # Docker writes normal progress to stderr. Check its actual exit code.
    $priorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = & docker @Arguments 2>&1
        $nativeExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $priorPreference
    }
    $text = (@($lines) | Where-Object { $null -ne $_ } | ForEach-Object { $_.ToString() }) -join $nl
    Add-Content -LiteralPath $logPath -Value $text
    if ($text) { Write-Host $text }
    if ($nativeExit -ne 0) { throw "Docker exited $nativeExit while running: $command" }
    if ($Capture) { return $text.Trim() }
}

function Save-DatabaseState {
    param([string]$Filename)
    $containerPath = $relativeOutput + '/' + $Filename
    $code = "from runner.evaluator import connect, metadata; from runner.metrics import save_json; c=connect(); save_json('$containerPath', metadata(c)); c.close()"
    Invoke-Docker -Arguments ($composeArgs + @(
        'run', '--rm', '-T', '--no-deps', '--entrypoint', 'python', 'runner', '-c', $code))
    return Get-Content -LiteralPath (Join-Path $outputPath $Filename) -Raw | ConvertFrom-Json
}

function Get-DatabaseContainer {
    $id = Invoke-Docker -Arguments ($composeArgs + @('ps', '-q', 'postgres')) -Capture
    if ($id -notmatch '^[0-9a-f]{12,64}$') { throw 'Could not identify the PostgreSQL container.' }
    $health = Invoke-Docker -Arguments @('inspect', '--format', '{{.State.Health.Status}}', $id) -Capture
    if ($health -ne 'healthy') { throw "PostgreSQL health is $health" }
    return $id
}

Push-Location $repo
try {
    Write-Host 'This resets the kmogo schema and recreates the kmogo-mp1 development volume.' -ForegroundColor Yellow
    Write-Host "Evidence directory: $outputPath"
    Get-Command docker -ErrorAction Stop | Out-Null
    Get-Command git -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath '.env')) {
        Copy-Item -LiteralPath '.env.example' -Destination '.env'
    }
    $revision = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Git revision.' }
    $env:KMOGO_REVISION = $revision.Trim()
    $record.source_revision = $env:KMOGO_REVISION
    $record.source_dirty = [bool](& git status --porcelain --untracked-files=no)

    $version = Invoke-Docker -Arguments @('version', '--format', '{{json .}}') -Capture
    $record.docker_version = $version | ConvertFrom-Json
    $record.checks.engine = 'passed'
    Invoke-Docker -Arguments ($composeArgs + @('config', '--quiet'))
    $record.checks.compose_configuration = 'passed'
    Invoke-Docker -Arguments ($composeArgs + @('up', '-d', '--wait', 'postgres'))
    $initialId = Get-DatabaseContainer
    $record.checks.initial_health = 'passed'
    $record.initial_container_id = $initialId

    $pgImage = Invoke-Docker -Arguments @('inspect', '--format', '{{.Image}}', $initialId) -Capture
    $record.postgres_image_id = $pgImage
    $digests = Invoke-Docker -Arguments @('image', 'inspect', '--format', '{{json .RepoDigests}}', $pgImage) -Capture
    $record.postgres_image_digests = $digests | ConvertFrom-Json
    $mountsJson = Invoke-Docker -Arguments @('inspect', '--format', '{{json .Mounts}}', $initialId) -Capture
    $dataMounts = @($mountsJson | ConvertFrom-Json | Where-Object { $_.Destination -eq '/var/lib/postgresql/data' })
    if ($dataMounts.Count -ne 1 -or $dataMounts[0].Type -ne 'volume') { throw 'Unexpected PostgreSQL data mount.' }
    $volumeName = $dataMounts[0].Name
    if ($volumeName -ne 'kmogo-mp1_postgres_data') { throw "Unexpected database volume: $volumeName" }
    $record.volume_name = $volumeName
    $record.initial_volume_created_at = Invoke-Docker -Arguments @('volume', 'inspect', '--format', '{{.CreatedAt}}', $volumeName) -Capture

    Invoke-Docker -Arguments ($composeArgs + @('build', 'runner'))
    $record.checks.runner_build = 'passed'
    $record.runner_image_id = Invoke-Docker -Arguments @('image', 'inspect', '--format', '{{.Id}}', 'kmogo-mp1-runner') -Capture
    Invoke-Docker -Arguments ($composeArgs + @('run', '--rm', '-T', 'runner', 'reset'))
    $initial = Save-DatabaseState -Filename 'initial-state.json'
    if ($initial.dataset.tables.customers.rows -ne 10000 -or $initial.dataset.tables.orders.rows -ne 200000) {
        throw 'Initial dataset row counts do not match the smoke workload.'
    }
    $record.checks.client_connection_and_load = 'passed'
    $record.initial_fingerprint = $initial.dataset_fingerprint

    Invoke-Docker -Arguments ($composeArgs + @('run', '--rm', '-T', '-e', 'KMOGO_INTEGRATION_TEST=1',
        '--entrypoint', 'python', 'runner', '-m', 'unittest', 'discover', '-s', 'tests', '-v'))
    $record.checks.integration_tests = 'passed'
    foreach ($cycle in 1..3) {
        $cyclePath = $relativeOutput + '/cycle-' + $cycle
        Invoke-Docker -Arguments ($composeArgs + @('run', '--rm', '-T', 'runner', 'experiment',
            '--repeat', '5', '--warmup', '1', '--output-dir', $cyclePath))
        $comparison = Get-Content -LiteralPath (Join-Path $repo ($cyclePath + '/comparison.json')) -Raw | ConvertFrom-Json
        $baseline = Get-Content -LiteralPath (Join-Path $repo ($cyclePath + '/baseline.json')) -Raw | ConvertFrom-Json
        $indexed = Get-Content -LiteralPath (Join-Path $repo ($cyclePath + '/indexed.json')) -Raw | ConvertFrom-Json
        if ($baseline.status -ne 'complete' -or $indexed.status -ne 'complete') { throw "Cycle $cycle is incomplete." }
        if ($baseline.metadata.dataset_fingerprint -ne $initial.dataset_fingerprint) { throw "Cycle $cycle dataset differs." }
        $record.cycles += [ordered]@{cycle=$cycle; comparison=$comparison}
    }
    $record.checks.three_experiment_cycles = 'passed'

    # Scope is fixed by --project-name and this repository's Compose file.
    Invoke-Docker -Arguments ($composeArgs + @('down', '-v'))
    Invoke-Docker -Arguments ($composeArgs + @('up', '-d', '--wait', 'postgres'))
    $recreatedId = Get-DatabaseContainer
    $record.recreated_container_id = $recreatedId
    $record.recreated_volume_created_at = Invoke-Docker -Arguments @('volume', 'inspect', '--format', '{{.CreatedAt}}', $volumeName) -Capture
    if ($initialId -eq $recreatedId -or $record.initial_volume_created_at -eq $record.recreated_volume_created_at) {
        throw 'Container/volume identity does not show recreation.'
    }
    # No reset here: prove initialization ran on the newly created volume.
    $recreated = Save-DatabaseState -Filename 'recreated-state.json'
    if ($initial.dataset_fingerprint -ne $recreated.dataset_fingerprint) { throw 'Data fingerprint differs after recreation.' }
    if ($recreated.dataset.tables.customers.rows -ne 10000 -or $recreated.dataset.tables.orders.rows -ne 200000) {
        throw 'Recreated dataset row counts differ.'
    }
    $initialDefinitions = @($initial.indexes | ForEach-Object { $_.definition }) -join $nl
    $recreatedDefinitions = @($recreated.indexes | ForEach-Object { $_.definition }) -join $nl
    if ($initialDefinitions -ne $recreatedDefinitions) { throw 'Recreated baseline indexes differ.' }
    $record.recreated_fingerprint = $recreated.dataset_fingerprint
    $record.checks.volume_recreation = 'passed'
    $record.status = 'passed'
    Write-Host ($nl + 'All Docker checks passed. PostgreSQL remains healthy with baseline data.') -ForegroundColor Green
} catch {
    $record.status = 'failed'
    $record.error = $_.Exception.Message
    $exitCode = 1
    Write-Host ($nl + "Validation stopped: $($record.error)") -ForegroundColor Red
    Write-Host 'Logs and any completed evidence have been preserved.'
} finally {
    $record.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    [IO.File]::WriteAllText((Join-Path $outputPath 'validation.json'),
        ($record | ConvertTo-Json -Depth 30) + $nl, [Text.UTF8Encoding]::new($false))
    $env:KMOGO_REVISION = $priorRevision
    Pop-Location
    Write-Host "Results: $outputPath"
}
exit $exitCode
