param([string]$Vivado='')
$ErrorActionPreference='Stop'
$labRoot=Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $labRoot 'rtl/rv32_core.sv'))) {
    $labRoot=(Get-Location).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $labRoot 'rtl/rv32_core.sv'))) {
    throw 'Run from riscv-cpu-lab, or invoke the repository script directly.'
}
if (-not $Vivado) {
    if ($env:LAB_VIVADO) { $Vivado=$env:LAB_VIVADO }
    elseif (Get-Command vivado.bat -ErrorAction SilentlyContinue) { $Vivado=(Get-Command vivado.bat).Source }
    else { $Vivado='D:\Projects\vivado\2026.1\Vivado\bin\vivado.bat' }
}
if (-not (Test-Path -LiteralPath $Vivado)) { throw 'Set LAB_VIVADO to the installed vivado.bat path.' }
Push-Location $labRoot
try {
    $output=Join-Path $labRoot 'build/synth'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $marker=Join-Path $output 'SYNTH_PASS.txt'
    $previous=Get-Date
    & $Vivado -mode batch -source tools/synth.tcl -notrace -log build/synth/vivado.log -journal build/synth/vivado.jou
    $toolExit=$LASTEXITCODE
    $passed=($toolExit -eq 0) -and (Test-Path -LiteralPath $marker) -and
        ((Get-Item -LiteralPath $marker).LastWriteTime -ge $previous)
    [ordered]@{
        checked_at=(Get-Date -Format o); vivado=$Vivado; exit_code=$toolExit;
        passed=$passed; kind='out-of-context only; no board acceptance';
        log='build/synth/vivado.log'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding utf8
    if (-not $passed) { throw "Vivado synthesis incomplete (exit $toolExit); inspect build/synth/vivado.log." }
    Write-Output 'SYNTH_PASS: out-of-context only'
} finally {
    Pop-Location
}
