#Requires -Version 5.1
<#
.SYNOPSIS
Imports, tests, exports and smoke-tests a standalone Windows x64 package.
.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 -Configuration Release -RenderSmoke
.NOTES
Install the export templates matching the editor in %APPDATA%/Godot/export_templates.
GODOT_EXE or -Godot selects a different engine. All output stays under build/windows.
Each build gets a new directory; existing packages are never deleted or overwritten.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$Godot = $env:GODOT_EXE,
    [switch]$RenderSmoke
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if (-not $Godot) {
    $candidate = Join-Path $env:USERPROFILE 'Tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $candidate) {
        $Godot = $candidate
    } else {
        $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) { throw 'Godot was not found. Set GODOT_EXE or pass -Godot <console.exe>.' }
        $Godot = $command.Source
    }
}
$Godot = (Resolve-Path -LiteralPath $Godot).Path
$engineVersion = ((& $Godot --version) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable\.') {
    throw "This project requires Godot 4.7.2 stable; found '$engineVersion'."
}
$templateRoot = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable'
foreach ($templateName in @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $templateRoot $templateName))) {
        throw "Missing $templateName in $templateRoot. Install official Godot 4.7.2 export templates first."
    }
}

$revision = (& git -C $projectRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Git revision.' }
$sourceStatus = @(& git -C $projectRoot status --porcelain --untracked-files=all -- . ':!.idea')
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Git worktree state.' }
$isDirty = $sourceStatus.Count -gt 0
$shortRevision = $revision.Substring(0, 8)
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$packageName = 'Musubi-' + $shortRevision + $(if ($isDirty) { '-dirty' }) + '-windows-x64-' + $Configuration.ToLowerInvariant()
$buildRoot = Join-Path $projectRoot ('build/windows/' + $Configuration + '/' + $stamp)
$packageRoot = Join-Path $buildRoot $packageName
$logRoot = Join-Path $buildRoot 'logs'
[IO.Directory]::CreateDirectory($packageRoot) | Out-Null
[IO.Directory]::CreateDirectory($logRoot) | Out-Null

function Invoke-CheckedProcess {
    param([string]$FilePath, [string[]]$Arguments, [string]$Name, [int]$TimeoutSeconds = 180, [string]$WorkingDirectory = $projectRoot)
    $stdout = Join-Path $logRoot ($Name + '.stdout.log')
    $stderr = Join-Path $logRoot ($Name + '.stderr.log')
    # Every argument is quoted independently; no shell evaluates source paths.
    $quotedArguments = @($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
    $process = Start-Process -FilePath $FilePath -ArgumentList $quotedArguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Retain the handle before waiting: Windows PowerShell 5.1 can otherwise lose ExitCode.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        $process.WaitForExit()
        $process.Dispose()
        throw "$Name timed out after $TimeoutSeconds seconds. See $logRoot."
    }
    $process.WaitForExit()
    $process.Refresh()
    $exitCode = $process.ExitCode
    $process.Dispose()
    $logText = [IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr)
    if ($exitCode -ne 0 -or $logText -match '(?im)^\s*(SCRIPT ERROR:|ERROR:|USER ERROR:|Parse Error:|Failed to export)') {
        throw "$Name failed (exit $exitCode). See $stdout and $stderr.`n$logText"
    }
    Write-Host "$Name passed."
}

Invoke-CheckedProcess $Godot @('--headless', '--path', $projectRoot, '--import') 'import'
Invoke-CheckedProcess $Godot @('--headless', '--path', $projectRoot, '-s', 'res://tests/run_tests.gd') 'tests'
$exportFlag = '--export-' + $Configuration.ToLowerInvariant()
$executable = Join-Path $packageRoot 'Musubi.exe'
Invoke-CheckedProcess $Godot @('--headless', '--path', $projectRoot, $exportFlag, 'Windows Desktop', $executable) 'export'
if (-not (Test-Path -LiteralPath $executable) -or -not (Test-Path -LiteralPath (Join-Path $packageRoot 'Musubi.pck'))) {
    throw 'Export did not create both Musubi.exe and Musubi.pck.'
}
Invoke-CheckedProcess $executable @('--headless', '--quit-after', '120', '--log-file', (Join-Path $logRoot 'runtime-headless.log')) 'smoke-headless' -WorkingDirectory $packageRoot
if ($RenderSmoke) {
    Invoke-CheckedProcess $executable @('--quit-after', '120', '--log-file', (Join-Path $logRoot 'runtime-rendered.log')) 'smoke-rendered' -WorkingDirectory $packageRoot
}

$metadata = [ordered]@{
    product = 'Musubi'
    platform = 'Windows x64'
    configuration = $Configuration
    engineVersion = $engineVersion
    gitRevision = $revision
    sourceDirty = $isDirty
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    headlessSmokePassed = $true
    renderedSmokePassed = [bool]$RenderSmoke
    files = @(Get-ChildItem -LiteralPath $packageRoot -File | Sort-Object Name | ForEach-Object {
        [ordered]@{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
    })
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $packageRoot 'build-info.json'), ($metadata | ConvertTo-Json -Depth 5) + "`n", $utf8)
$readme = @"
Musubi - Windows x64 prototype

Double-click Musubi.exe. Keep Musubi.pck next to it.
No Godot editor installation is required on the test computer.

Left drag: shape rope or orbit empty space. Right/middle drag: pan.
Wheel: zoom, or move the grabbed rope in depth. Grab an endpoint to free it.
Release: hold shape. Esc: cancel grab. R: reset. F: restore view.
Space: pause/resume. F11: full screen. Ctrl+S / Ctrl+O: save/open creation.
B: other side. Rope menu: new length or fix/release A/B.
Ctrl+Z: undo. Ctrl+Shift+Z / Ctrl+Y: redo. Loading clears edit history.
F9: export performance JSON/CSV and scene snapshot to the reports data folder.

Build: $revision ($Configuration); local changes: $isDirty
Engine: $engineVersion
Build details and payload checksums: build-info.json
Application data: %APPDATA%\Godot\app_userdata\Musubi
Runtime log: %APPDATA%\Godot\app_userdata\Musubi\logs\godot.log
"@
[IO.File]::WriteAllText((Join-Path $packageRoot 'README.txt'), $readme + "`n", $utf8)
$zipPath = Join-Path $buildRoot ($packageName + '.zip')
Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zipPath + '.sha256'), $zipHash + '  ' + [IO.Path]::GetFileName($zipPath) + "`n", $utf8)
Write-Host "Executable: $executable"
Write-Host "Package: $zipPath"
Write-Host "Logs: $logRoot"
