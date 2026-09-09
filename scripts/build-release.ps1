<#
.SYNOPSIS
Publish wmv for release (self-contained, single file).

.PARAMETER Configuration
Build configuration. Default: Release.

.PARAMETER Runtime
Runtime identifier. Default: win-x64.

.PARAMETER Clean
Delete the publish output directory before publishing.

.EXAMPLE
.\scripts\build-release.ps1
.\scripts\build-release.ps1 -Clean
#>
param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProjectPath = Join-Path $RepoRoot "wmv.csproj"
$PublishDir = Join-Path $RepoRoot "bin\$Configuration\net10.0-windows\$Runtime\publish"
$ExePath = Join-Path $PublishDir "wmv.exe"

# A wmv.exe running from this repository's bin folder locks the output file and makes publish fail
# (GenerateBundle: Access to the path ... is denied). An installed wmv.exe is left alone.
Get-Process -Name "wmv" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith("$RepoRoot\", [System.StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object {
        Write-Host "Stopping running wmv.exe from the repository: $($_.Path)"
        Stop-Process -Id $_.Id -Force
    }
Start-Sleep -Milliseconds 500

if ($Clean -and (Test-Path $PublishDir)) {
    Remove-Item -LiteralPath $PublishDir -Recurse -Force
}

dotnet restore $ProjectPath
if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed ($LASTEXITCODE)." }

# Self-contained single-file publish so the app runs on PCs without the .NET runtime installed.
dotnet publish $ProjectPath -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -o $PublishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)." }

if (-not (Test-Path $ExePath)) {
    throw "Release executable was not created: $ExePath"
}

Write-Host "Release build created:"
Write-Host $ExePath
