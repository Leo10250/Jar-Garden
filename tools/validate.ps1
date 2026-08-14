$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TestManifest = Join-Path $PSScriptRoot "test_suites.txt"

function Resolve-GodotExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        if (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
        }

        $configured = Get-Command $env:GODOT_BIN -ErrorAction SilentlyContinue
        if ($null -ne $configured) {
            return $configured.Source
        }

        throw "GODOT_BIN is set but cannot be resolved: $($env:GODOT_BIN)"
    }

    foreach ($candidate in @("godot", "godot4")) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "Godot was not found. Add Godot to PATH or set GODOT_BIN to the Godot executable."
}

function Get-TestSuites {
    if (-not (Test-Path -LiteralPath $TestManifest -PathType Leaf)) {
        throw "Test manifest is missing: $TestManifest"
    }

    $suites = @(
        Get-Content -LiteralPath $TestManifest |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#") }
    )

    if ($suites.Count -eq 0) {
        throw "Test manifest contains no test entrypoints: $TestManifest"
    }

    return $suites
}

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "==> $Label"
    & $script:Godot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host "FAIL: $Label (exit $exitCode)" -ForegroundColor Red
        exit $exitCode
    }
    Write-Host "PASS: $Label" -ForegroundColor Green
}

try {
    $script:Godot = Resolve-GodotExecutable
    $testSuites = Get-TestSuites

    Write-Host "Jar Garden validation"
    Write-Host "Godot: $script:Godot"
    Write-Host "Repo:  $RepoRoot"
    Write-Host "Tests: $($testSuites.Count)"

    Push-Location $RepoRoot
    try {
        Invoke-GodotStep "project import / parse" @(
            "--headless",
            "--path", $RepoRoot,
            "--import"
        )

        foreach ($suite in $testSuites) {
            Invoke-GodotStep "test $(Split-Path $suite -Leaf)" @(
                "--headless",
                "--path", $RepoRoot,
                "--script", $suite
            )
        }

        Invoke-GodotStep "main scene smoke" @(
            "--headless",
            "--path", $RepoRoot,
            "--quit-after", "2"
        )
    }
    finally {
        Pop-Location
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Jar Garden validation completed successfully." -ForegroundColor Green
exit 0
