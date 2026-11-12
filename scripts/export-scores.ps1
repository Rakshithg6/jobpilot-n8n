# Export the current ranking so eval/evaluate.mjs can score it.
# Usage:  ./scripts/export-scores.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$sql = "COPY (SELECT position, score, title, company, fingerprint FROM v_ranked) TO STDOUT WITH CSV HEADER"

$rows = docker compose exec -T postgres psql -U n8n -d n8n -c $sql
if ($LASTEXITCODE -ne 0) { throw 'psql export failed. Is the stack running?' }

$rows | Out-File -FilePath 'eval/scores.csv' -Encoding utf8
Write-Host "Wrote eval/scores.csv ($(($rows | Measure-Object).Count - 1) rows). Next: node eval/evaluate.mjs" -ForegroundColor Green
