# Wipe the stack and start over - useful before recording a demo.
# Usage:  ./scripts/reset.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host 'This deletes the n8n volume (workflows, credentials) and the Postgres volume (all jobs).' -ForegroundColor Yellow
$answer = Read-Host 'Type yes to continue'
if ($answer -ne 'yes') { Write-Host 'Aborted.'; exit 0 }

docker compose down -v
docker compose up -d
Write-Host 'Fresh stack running. Re-import with ./scripts/import-workflows.ps1' -ForegroundColor Green
