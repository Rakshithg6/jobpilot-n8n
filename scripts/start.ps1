# Boot the stack from a cold laptop and print exactly what to do next.
# Usage:  ./scripts/start.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
    Write-Host 'Created .env from .env.example (defaults are fine for local use).' -ForegroundColor Yellow
}

Write-Host 'Starting Postgres + n8n...' -ForegroundColor Cyan
docker compose up -d

Write-Host 'Waiting for n8n to answer...' -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:5678/healthz' -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 3 }
}

if ($ready) {
    Write-Host ''
    Write-Host 'n8n is up:      http://localhost:5678' -ForegroundColor Green
    Write-Host 'Postgres:       localhost:5433  (db/user: see .env)' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Then run:  ./scripts/import-workflows.ps1'
} else {
    Write-Host 'n8n did not answer in time. Check: docker compose logs n8n --tail 50' -ForegroundColor Red
}
