param([switch]$SkipSystem)
$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $labRoot 'tools/install-system.sh'))) {
    $labRoot = (Get-Location).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $labRoot 'tools/install-system.sh'))) {
    throw 'Run bootstrap from the riscv-cpu-lab directory'
}
$windowsRoot = $labRoot.Replace('\', '/')
$linuxRoot = (& wsl -d Ubuntu-24.04 -- wslpath -u $windowsRoot).Trim()
if ($LASTEXITCODE -ne 0) { throw 'wslpath failed' }
if (-not $SkipSystem) {
    & wsl -d Ubuntu-24.04 -u root -- bash "$linuxRoot/tools/install-system.sh"
    if ($LASTEXITCODE -ne 0) { throw 'System package installation failed' }
}
$downloadDir = Join-Path $labRoot 'build/downloads'
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
$archive = Join-Path $downloadDir 'spike-f8a060b7.tar.gz'
$expected = '25efb028e472a86deaa40eba01f624f64ae25c16509a29f454c375638b5743d4'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri 'https://api.github.com/repos/riscv-software-src/riscv-isa-sim/tarball/f8a060b7bea8da6f738f193ed1b66b665978d092' -OutFile $archive
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Spike source archive checksum mismatch'
}
& wsl -d Ubuntu-24.04 -- bash "$linuxRoot/tools/install-user.sh" "$linuxRoot/build/downloads/spike-f8a060b7.tar.gz"
if ($LASTEXITCODE -ne 0) { throw 'User toolchain installation failed' }
Write-Output 'BOOTSTRAP_PASS'
