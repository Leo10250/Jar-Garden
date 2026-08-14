$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TestSuites = @(
    "content_asset_tests.gd",
    "environment_provider_tests.gd",
    "phase2_tests.gd",
    "mvp_simulation_tests.gd",
    "plant_visual_tests.gd",
    "main_integration_tests.gd",
    "main_visual_tests.gd",
    "stall_ui_tests.gd"
)

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
    Write-Host "Jar Garden validation"
    Write-Host "Godot: $script:Godot"
    Write-Host "Repo:  $RepoRoot"

    Push-Location $RepoRoot
    try {
        Invoke-GodotStep "project import / parse" @(
            "--headless",
            "--path", $RepoRoot,
            "--import"
        )

        foreach ($suite in $TestSuites) {
            Invoke-GodotStep "test $suite" @(
                "--headless",
                "--path", $RepoRoot,
                "--script", "res://tests/$suite"
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
