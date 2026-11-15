# Exports the JobPilot database so it can be restored on the cloud server.
#
# Produces: deploy\jobpilot-db.sql
# Usage:    .\scripts\export-db.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

$outDir = Join-Path $root 'deploy'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir 'jobpilot-db.sql'

Write-Host 'Dumping the n8n/JobPilot database...' -ForegroundColor Cyan

# cmd /c keeps the output as raw bytes; PowerShell's ">" would re-encode it.
cmd /c "docker compose exec -T postgres pg_dump -U n8n -d n8n --no-owner --no-privileges --clean --if-exists > `"$outFile`""

if (-not (Test-Path $outFile)) {
  Write-Host 'Dump failed - is the postgres container running?' -ForegroundColor Red
  exit 1
}

$mb = [math]::Round((Get-Item $outFile).Length / 1MB, 2)
Write-Host "Wrote $outFile ($mb MB)" -ForegroundColor Green

# Sanity check: the dump must contain your jobs and workflows.
$head = Get-Content $outFile -TotalCount 20
$hasJobs = Select-String -Path $outFile -Pattern 'CREATE TABLE public.jobs' -Quiet
$hasWf = Select-String -Path $outFile -Pattern 'CREATE TABLE public.workflow_entity' -Quiet
if ($hasJobs -and $hasWf) {
  Write-Host 'Dump contains the jobs and workflow tables.' -ForegroundColor Green
} else {
  Write-Host 'WARNING: dump looks incomplete - check the psql user/database names.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next: copy the whole project folder (including this file and .env) to the server.' -ForegroundColor Cyan
Write-Host 'The server must use the SAME N8N_ENCRYPTION_KEY, or saved credentials cannot decrypt.' -ForegroundColor Yellow
