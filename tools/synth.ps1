param(
    [string]$Vivado='',
    [string]$Part='',
    [ValidateRange(0.1,1000)][double]$ClockPeriodNs=10.0
)
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
if (-not $Part) {
    if ($env:LAB_FPGA_PART) { $Part=$env:LAB_FPGA_PART }
    else { $Part='xc7a35tcsg324-1' }
}
$savedOutput=$env:LAB_SYNTH_OUTPUT
$savedPart=$env:LAB_FPGA_PART
$savedPeriod=$env:LAB_SYNTH_PERIOD_NS
Push-Location $labRoot
try {
    $output=Join-Path $labRoot 'build/synth'
    $runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $run=Join-Path $output "runs/$runId"
    $temp=Join-Path $run 'work'
    if ($temp -match '[^\x00-\x7F]') {
        throw 'Use an ASCII-only repository path for Windows Vivado synthesis (for example D:\Projects\riscv-cpu-lab).'
    }
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $env:LAB_SYNTH_OUTPUT=$run.Replace('\','/')
    $env:LAB_FPGA_PART=$Part
    $env:LAB_SYNTH_PERIOD_NS=$ClockPeriodNs.ToString([Globalization.CultureInfo]::InvariantCulture)
    $previous=Get-Date
    # Keep run artifacts separate; synth.tcl also overrides the RTL engine's temp paths.
    # Vivado embeds this argument in generated Tcl: backslashes become escapes.
    $toolTemp=$temp.Replace('\','/')
    & $Vivado -mode batch -tempDir $toolTemp -source tools/synth.tcl -notrace -log "$run/vivado.log" -journal "$run/vivado.jou"
    $toolExit=$LASTEXITCODE
    $missing=@()
    foreach ($name in @('SYNTH_PASS.txt','rv32_system.dcp','utilization.txt','timing.txt')) {
        $path=Join-Path $run $name
        if (-not (Test-Path -LiteralPath $path)) { $missing+=$name; continue }
        $item=Get-Item -LiteralPath $path
        if ($item.Length -eq 0 -or $item.LastWriteTime -lt $previous) { $missing+=$name }
    }
    $logErrors=@(Select-String -LiteralPath (Join-Path $run 'vivado.log') -Pattern '^ERROR:' | ForEach-Object { $_.Line })
    $passed=($toolExit -eq 0) -and ($missing.Count -eq 0) -and ($logErrors.Count -eq 0)
    $result=[ordered]@{
        checked_at=(Get-Date -Format o); vivado=$Vivado; exit_code=$toolExit;
        passed=$passed; kind='out-of-context synthesis; not routed or board-tested';
        part=$Part; clock_period_ns=$ClockPeriodNs; run_id=$runId;
        output=$run; log=(Join-Path $run 'vivado.log'); missing_artifacts=$missing; errors=$logErrors
    }
    $json=$result | ConvertTo-Json
    $json | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
    $json | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding utf8
    if (-not $passed) { throw "Vivado synthesis incomplete (exit $toolExit); inspect $run/vivado.log." }
    Write-Output "SYNTH_PASS: $Part, out-of-context only; reports: $run"
} finally {
    $env:LAB_SYNTH_OUTPUT=$savedOutput
    $env:LAB_FPGA_PART=$savedPart
    $env:LAB_SYNTH_PERIOD_NS=$savedPeriod
    Pop-Location
}
