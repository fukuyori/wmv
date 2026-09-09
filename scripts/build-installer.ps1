<#
.SYNOPSIS
Build the wmv Inno Setup installer. With -Sign, code-sign the executable, the installer and the uninstaller.

.DESCRIPTION
1. Publish a self-contained single-file wmv.exe via scripts\build-release.ps1 (skip with -SkipPublish).
2. With -Sign, sign wmv.exe using signtool.exe.
3. Compile installer.iss with Inno Setup (ISCC.exe). The version is read from <Version> in wmv.csproj.
   With -Sign, /DSIGN and /Swmvsign=... are passed so Inno Setup's SignTool / SignedUninstaller
   features sign both the installer and the uninstaller.
4. With -Sign, verify the signatures with signtool verify.

.PARAMETER Sign
Enable code signing. The certificate is taken from the CODESIGN_CERT environment variable (one of):
  - Path to a certificate file (.pfx / .p12). Password in CODESIGN_PASSWORD.
  - SHA-1 thumbprint (40 hex digits) of a certificate in the certificate store.
  - Subject name of a certificate in the certificate store (signtool /n).
Timestamp server: CODESIGN_TIMESTAMP_URL (default: http://timestamp.digicert.com).

.PARAMETER SkipPublish
Reuse the existing publish output instead of publishing.

.PARAMETER IsccPath
Path to ISCC.exe. If omitted, PATH and the default install locations are searched.

.PARAMETER SignToolPath
Path to signtool.exe. If omitted, PATH and the Windows SDK are searched.

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

        # Prefer the x64 build; fall back to x86.
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

    # 1) Path to a certificate file (.pfx / .p12)
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

    # 2) 40-digit thumbprint (whitespace and colon separators are tolerated)
    $thumbprint = ($cert -replace '[\s:]', '')
    if ($thumbprint -match '^[0-9a-fA-F]{40}$') {
        return [pscustomobject]@{
            Mode         = "Thumbprint"
            Certificate  = $thumbprint
            Password     = $null
            TimestampUrl = $timestampUrl
        }
    }

    # 3) Otherwise treat it as a subject name in the certificate store (signtool /n)
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

    # Inno Setup replaces $q with a double quote and $f with the file to sign.
    # Keeping quotes out of the PowerShell side makes argument passing reliable.
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
    # /DSIGN enables the SignTool / SignedUninstaller directives in installer.iss and
    # /S registers the sign command, so both the installer and the uninstaller get signed.
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
