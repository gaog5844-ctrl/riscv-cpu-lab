param(
    [ValidateSet('doctor','test','unit','lint','bench','wave','synth')]
    [string]$Task='test'
)
$ErrorActionPreference='Stop'
if ($Task -eq 'synth') {
    & (Join-Path $PSScriptRoot 'tools/synth.ps1')
    exit $LASTEXITCODE
}
$windowsRoot=$PSScriptRoot.Replace('\','/')
$linuxRoot=(& wsl -d Ubuntu-24.04 -- wslpath -u $windowsRoot).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve project path in WSL' }
& wsl -d Ubuntu-24.04 --cd $linuxRoot -- make $Task
exit $LASTEXITCODE
