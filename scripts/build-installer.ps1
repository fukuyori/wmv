<#
.SYNOPSIS
wmv の Inno Setup インストーラーを作成する。-Sign で実行ファイル・インストーラー・アンインストーラーに電子署名する。

.DESCRIPTION
1. scripts\build-release.ps1 で自己完結・単一ファイルの wmv.exe を publish する（-SkipPublish で省略可）。
2. -Sign 指定時は signtool.exe で wmv.exe に署名する。
3. Inno Setup (ISCC.exe) で installer.iss をコンパイルする。バージョンは wmv.csproj の <Version> から取得する。
   -Sign 指定時は /DSIGN と /Swmvsign=... を渡し、Inno Setup の SignTool / SignedUninstaller 機能で
   インストーラー本体とアンインストーラーの両方に署名する。
4. -Sign 指定時は署名を signtool verify で検証する。

.PARAMETER Sign
電子署名を行う。証明書は環境変数 CODESIGN_CERT で指定する（以下のいずれか）。
  - 証明書ファイル (.pfx / .p12) のパス。パスワードは CODESIGN_PASSWORD
  - 証明書ストア内の証明書の SHA-1 拇印（40 桁）
  - 証明書ストア内の証明書のサブジェクト名（signtool /n）
タイムスタンプサーバーは CODESIGN_TIMESTAMP_URL（既定: http://timestamp.digicert.com）。

.PARAMETER SkipPublish
publish を省略し、既存の publish 出力を使う。

.PARAMETER IsccPath
ISCC.exe のパス。省略時は PATH と既定のインストール先から探す。

.PARAMETER SignToolPath
signtool.exe のパス。省略時は PATH と Windows SDK から探す。

.EXAMPLE
.\scripts\build-installer.ps1
.\scripts\build-installer.ps1 -Sign
$env:CODESIGN_CERT = "0123456789ABCDEF0123456789ABCDEF01234567"; .\scripts\build-installer.ps1 -Sign
#>
param(
    [switch]$Sign,
    [switch]$SkipPublish,
    [string]$IsccPath,
    [string]$SignToolPath
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProjectPath = Join-Path $RepoRoot "wmv.csproj"
$ReleaseScript = Join-Path $PSScriptRoot "build-release.ps1"
$InstallerScript = Join-Path $RepoRoot "installer.iss"
$InstallerOutputDir = Join-Path $RepoRoot "installer_output"
$PublishExePath = Join-Path $RepoRoot "bin\Release\net10.0-windows\win-x64\publish\wmv.exe"
$InnoSignToolName = "wmvsign"

function Get-ProjectVersion {
    [xml]$project = Get-Content -LiteralPath $ProjectPath
    $version = ($project.Project.PropertyGroup | ForEach-Object { $_.Version } | Where-Object { $_ } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "<Version> was not found in $ProjectPath"
    }
    return $version.Trim()
}

function Resolve-SignToolPath {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        if (-not (Test-Path $Preferred)) {
            throw "signtool.exe was not found: $Preferred"
        }
        return (Resolve-Path $Preferred).Path
    }

    $command = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $candidates = Get-ChildItem -Path $root -Filter "signtool.exe" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending

        # x64 版を優先し、無ければ x86 版にフォールバックする。
        $found = $candidates | Where-Object { $_.Directory.Name -eq "x64" } | Select-Object -First 1
        if (-not $found) {
            $found = $candidates | Where-Object { $_.Directory.Name -eq "x86" } | Select-Object -First 1
        }

        if ($found) {
            return $found.FullName
        }
    }

    throw "signtool.exe was not found. Install the Windows SDK or pass -SignToolPath `"C:\Path\To\signtool.exe`"."
}

function Resolve-IsccPath {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        if (-not (Test-Path $Preferred)) {
            throw "ISCC.exe was not found: $Preferred"
        }
        return (Resolve-Path $Preferred).Path
    }

    $command = Get-Command "iscc.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        return $found
    }

    throw "Inno Setup compiler was not found. Install Inno Setup 6 or pass -IsccPath `"C:\Path\To\ISCC.exe`"."
}

function Get-CodeSignSettings {
    $cert = $env:CODESIGN_CERT
    if ([string]::IsNullOrWhiteSpace($cert)) {
        throw "-Sign was specified but the CODESIGN_CERT environment variable is not set."
    }

    $timestampUrl = $env:CODESIGN_TIMESTAMP_URL
    if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
        $timestampUrl = "http://timestamp.digicert.com"
    }

    # 1) 証明書ファイル (.pfx / .p12) のパス
    if (Test-Path -LiteralPath $cert) {
        return [pscustomobject]@{
            Mode         = "File"
            Certificate  = (Resolve-Path -LiteralPath $cert).Path
            Password     = $env:CODESIGN_PASSWORD
            TimestampUrl = $timestampUrl
        }
    }

    if ($cert -match '\.(pfx|p12)$') {
        throw "CODESIGN_CERT points to a certificate file that does not exist: $cert"
    }

    # 2) 40 桁の拇印 (空白やコロン区切りも許容)
    $thumbprint = ($cert -replace '[\s:]', '')
    if ($thumbprint -match '^[0-9a-fA-F]{40}$') {
        return [pscustomobject]@{
            Mode         = "Thumbprint"
            Certificate  = $thumbprint
            Password     = $null
            TimestampUrl = $timestampUrl
        }
    }

    # 3) それ以外は証明書ストア内のサブジェクト名 (signtool /n) とみなす
    return [pscustomobject]@{
        Mode         = "Subject"
        Certificate  = $cert
        Password     = $null
        TimestampUrl = $timestampUrl
    }
}

function Invoke-CodeSign {
    param(
        [string]$SignTool,
        [object]$Settings,
        [string]$TargetPath
    )

    $signArgs = @("sign", "/fd", "SHA256", "/tr", $Settings.TimestampUrl, "/td", "SHA256")

    switch ($Settings.Mode) {
        "File" {
            $signArgs += @("/f", $Settings.Certificate)
            if (-not [string]::IsNullOrWhiteSpace($Settings.Password)) {
                $signArgs += @("/p", $Settings.Password)
            }
        }
        "Thumbprint" { $signArgs += @("/sha1", $Settings.Certificate) }
        "Subject"    { $signArgs += @("/n", $Settings.Certificate) }
    }

    $signArgs += @("/v", $TargetPath)

    & $SignTool @signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Code signing failed ($LASTEXITCODE): $TargetPath"
    }
}

function Get-InnoSignCommand {
    param(
        [string]$SignTool,
        [object]$Settings
    )

    # $q は Inno Setup が二重引用符に、$f は署名対象ファイル名に置き換える。
    # PowerShell 側で引用符を含めないことで、引数の受け渡しを安定させる。
    $command = "`$q$SignTool`$q sign /fd SHA256 /tr $($Settings.TimestampUrl) /td SHA256"

    switch ($Settings.Mode) {
        "File" {
            $command += " /f `$q$($Settings.Certificate)`$q"
            if (-not [string]::IsNullOrWhiteSpace($Settings.Password)) {
                $command += " /p `$q$($Settings.Password)`$q"
            }
        }
        "Thumbprint" { $command += " /sha1 $($Settings.Certificate)" }
        "Subject"    { $command += " /n `$q$($Settings.Certificate)`$q" }
    }

    return $command + " /v `$f"
}

# ---- main ----

$Version = Get-ProjectVersion
Write-Host "wmv version: $Version"

$SignSettings = $null
$SignTool = $null

if ($Sign) {
    $SignSettings = Get-CodeSignSettings
    $SignTool = Resolve-SignToolPath -Preferred $SignToolPath
    Write-Host "Code signing enabled."
    Write-Host "  signtool   : $SignTool"
    Write-Host "  certificate: $($SignSettings.Certificate) ($($SignSettings.Mode))"
    Write-Host "  timestamp  : $($SignSettings.TimestampUrl)"
}

$Iscc = Resolve-IsccPath -Preferred $IsccPath

if (-not $SkipPublish) {
    & $ReleaseScript
}

if (-not (Test-Path $PublishExePath)) {
    throw "Executable was not found: $PublishExePath (run without -SkipPublish)"
}

if ($Sign) {
    Write-Host "Signing application executable..."
    Invoke-CodeSign -SignTool $SignTool -Settings $SignSettings -TargetPath $PublishExePath
}

$IsccArgs = @("/DMyAppVersion=$Version")

if ($Sign) {
    # /DSIGN で installer.iss の SignTool / SignedUninstaller 指令を有効化し、
    # /S で署名コマンドを登録する。これによりインストーラー本体とアンインストーラーの双方が署名される。
    $IsccArgs += "/DSIGN"
    $IsccArgs += "/S$InnoSignToolName=$(Get-InnoSignCommand -SignTool $SignTool -Settings $SignSettings)"
}

$IsccArgs += $InstallerScript

& $Iscc @IsccArgs
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed ($LASTEXITCODE)."
}

$setupFile = Get-ChildItem -Path $InstallerOutputDir -Filter "wmv_Setup_$Version.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $setupFile) {
    throw "Installer was not created in $InstallerOutputDir"
}

Write-Host "Installer output:"
Write-Host $setupFile.FullName

if ($Sign) {
    Write-Host "Verifying signatures..."
    & $SignTool verify /pa /all $PublishExePath
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $PublishExePath" }
    & $SignTool verify /pa /all $setupFile.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($setupFile.FullName)" }
}
