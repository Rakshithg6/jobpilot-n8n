# Import every workflow into the running n8n container.
# Usage:  ./scripts/import-workflows.ps1
#
# The workflows reference a Postgres credential named "JobPilot Postgres".
# If the import shows "Credential not found", open each Postgres node and pick
# the credential you created once in the UI (Credentials > New > Postgres).

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host 'Checking stack...' -ForegroundColor Cyan
docker compose ps --status running | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker compose failed. Is Docker Desktop running?' }

Write-Host 'Importing workflow JSON from /workflows ...' -ForegroundColor Cyan
docker compose exec -T n8n n8n import:workflow --separate --input=/workflows

Write-Host ''
Write-Host 'Imported. Next steps:' -ForegroundColor Green
Write-Host '  1. Open http://localhost:5678'
Write-Host '  2. Create the "JobPilot Postgres" credential if you have not yet:'
Write-Host '     host=postgres  port=5432  database=n8n  user=n8n  password=<POSTGRES_PASSWORD from .env>'
Write-Host '  3. Run 01 then 02 manually once, then toggle both to Active.'
