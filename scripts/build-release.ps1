<#
.SYNOPSIS
wmv をリリース用に publish する（自己完結・単一ファイル）。

.PARAMETER Configuration
ビルド構成。既定は Release。

.PARAMETER Runtime
ランタイム識別子。既定は win-x64。

.PARAMETER Clean
publish 出力ディレクトリを削除してから publish する。

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

# このリポジトリの bin 配下から起動中の wmv.exe があると、出力ファイルを上書きできず publish が失敗する
# (GenerateBundle: Access to the path ... is denied)。インストール済みの wmv.exe は対象外。
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

# 自己完結・単一ファイルで publish する。.NET ランタイム未導入の PC でも動作させるため。
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
