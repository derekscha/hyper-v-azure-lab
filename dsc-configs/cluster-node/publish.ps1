<#
.SYNOPSIS
    Compiles and publishes DSC .mof and .checksum files to a DSC Pull Server.

.PARAMETER OutputPath
    Optional output path for compiled files. Defaults to ./DSC.

.PARAMETER PublishPath
    Optional publish target path (e.g., UNC path or local IIS Pull Server folder).

.PARAMETER ConfigurationId
    Optional GUID to use as the ConfigurationId for pull mode nodes.
#>

param (
    [string]$OutputPath = "$PSScriptRoot\DSC",
    [string]$PublishPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration",
    [string]$ConfigurationId = ([guid]::NewGuid().ToString())
)

# Ensure paths exist
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

# Import config script
. "$PSScriptRoot\DomainConfig.ps1"

Write-Host "Compiling DSC configuration..." -ForegroundColor Cyan
DomainConfig -OutputPath $OutputPath

Write-Host "Creating checksum files..." -ForegroundColor Cyan
New-DscChecksum -Path $OutputPath -Force

# Rename .mof file using ConfigurationId
$sourceMof = Join-Path $OutputPath "localhost.mof"
$targetMof = Join-Path $OutputPath "$ConfigurationId.mof"
Rename-Item -Path $sourceMof -NewName "$ConfigurationId.mof" -Force

# Rename .checksum file to match
$sourceChecksum = Join-Path $OutputPath "localhost.mof.checksum"
$targetChecksum = Join-Path $OutputPath "$ConfigurationId.mof.checksum"
Rename-Item -Path $sourceChecksum -NewName "$ConfigurationId.mof.checksum" -Force

# Optional: Copy to pull server
if (Test-Path $PublishPath) {
    Write-Host "Publishing to DSC Pull Server at $PublishPath..." -ForegroundColor Green
    Copy-Item -Path $targetMof, $targetChecksum -Destination $PublishPath -Force
} else {
    Write-Warning "Publish path '$PublishPath' not found. Skipping copy."
}

Write-Host "Done. Configuration ID: $ConfigurationId" -ForegroundColor Yellow
