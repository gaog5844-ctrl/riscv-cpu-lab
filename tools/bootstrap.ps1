$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$linuxRoot = (& wsl -d Ubuntu-24.04 -- wslpath -u $labRoot).Trim()
if ($LASTEXITCODE -ne 0) { throw 'wslpath failed' }
& wsl -d Ubuntu-24.04 -u root -- bash "$linuxRoot/tools/install-system.sh"
if ($LASTEXITCODE -ne 0) { throw 'System package installation failed' }
& wsl -d Ubuntu-24.04 -- bash "$linuxRoot/tools/install-user.sh"
if ($LASTEXITCODE -ne 0) { throw 'User toolchain installation failed' }
Write-Output 'BOOTSTRAP_PASS'
