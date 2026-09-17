#
# Release export: publishes Screenish (Release, self-contained win-x64) with the
# build number derived from git history, packages it as an MSI with WiX, optionally
# code-signs, and drops Screenish-<version>-b<build>.msi in ~\Downloads.
#
# Versioning (see CLAUDE.md):
#   <Version> in Screenish.csproj - app version (semver), bumped by hand and
#                                   committed before each release
#   BuildNumber                   - git commit count, injected here at build time
#                                   (never edited by hand)
#
# Signing:
#   Set SIGN_CERT_THUMBPRINT to the SHA-1 thumbprint of a code-signing certificate
#   in the user/machine store to sign Screenish.exe and the MSI (signtool from the
#   Windows SDK must be on PATH). Unsigned builds work, but SmartScreen will warn on
#   other PCs, and the export is clearly marked as such.
#
# Requirements: .NET 8 SDK (WiX is restored from NuGet by the installer project).
#
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot          # ...\windows
Set-Location $root

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = Join-Path $env:USERPROFILE '.dotnet\dotnet.exe' }
if (-not (Test-Path $dotnet)) { throw 'dotnet SDK not found. Install the .NET 8 SDK.' }

if (git status --porcelain) {
    Write-Warning 'uncommitted changes - build number reflects committed history only'
}
$buildNumber = (git rev-list --count HEAD).Trim()
$version = ([xml](Get-Content "$root\Screenish\Screenish.csproj")).Project.PropertyGroup.Version |
    Where-Object { $_ } | Select-Object -First 1
$version = "$version".Trim()

$publishDir = "$root\build\publish"
if (Test-Path "$root\build") { Remove-Item "$root\build" -Recurse -Force }

# --- Publish the app (self-contained: no .NET install needed on the target PC) ---
& $dotnet publish "$root\Screenish\Screenish.csproj" -c Release -r win-x64 --self-contained true `
    -p:BuildNumber=$buildNumber -p:PublishReadyToRun=true -p:DebugType=none -o $publishDir -nologo
if ($LASTEXITCODE -ne 0) { throw 'publish failed' }

$suffix = ''
$thumbprint = $env:SIGN_CERT_THUMBPRINT
function Sign($path) {
    & signtool sign /sha1 $thumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $path
    if ($LASTEXITCODE -ne 0) { throw "signing failed: $path" }
}
if ($thumbprint) { Sign "$publishDir\Screenish.exe" } else {
    Write-Warning 'SIGN_CERT_THUMBPRINT not set - unsigned build; SmartScreen will warn on other PCs.'
    $suffix = '-unsigned'
}

# --- Package the MSI -------------------------------------------------------
& $dotnet build "$root\Installer\Screenish.Installer.wixproj" -c Release -nologo `
    -p:ProductVersion=$version "-p:PublishDir=$publishDir" -o "$root\build\msi"
if ($LASTEXITCODE -ne 0) { throw 'MSI build failed' }

$msi = "$root\build\msi\Screenish-$version.msi"
if ($thumbprint) { Sign $msi }

$target = Join-Path $env:USERPROFILE "Downloads\Screenish-$version-b$buildNumber$suffix.msi"
Copy-Item $msi $target -Force
Write-Host ''
Write-Host "Exported: $target (version $version, build $buildNumber)"
