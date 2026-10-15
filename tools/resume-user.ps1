$ErrorActionPreference = 'Stop'
& (Join-Path (Get-Location).Path 'tools/bootstrap.ps1') -SkipSystem
exit $LASTEXITCODE
