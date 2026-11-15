# Re-points workflow 07 at the IMAP credential that actually exists in this
# n8n instance, then publishes it.
#
# Why this is needed: the workflow file in git targets a fresh install and
# references credential id "jobpilot-imap". A credential created through the
# n8n UI has a different id, so publishing fails with
# "Cannot publish workflow: Credential JobPilot IMAP no longer exists."
#
# Usage:  .\scripts\fix-imap-credential.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

# 1. Patch the live workflow and its version snapshot using a join, so no id
#    has to be passed through PowerShell quoting.
$sql = @'
UPDATE credentials_entity SET name = 'JobPilot IMAP' WHERE type = 'imap';

UPDATE workflow_entity w
SET nodes = jsonb_set(w.nodes::jsonb, '{0,credentials}',
      jsonb_build_object('imap',
        jsonb_build_object('id', c.id, 'name', 'JobPilot IMAP')))::json
FROM credentials_entity c
WHERE c.type = 'imap' AND w.name LIKE '07 %';

UPDATE workflow_history h
SET nodes = jsonb_set(h.nodes::jsonb, '{0,credentials}',
      jsonb_build_object('imap',
        jsonb_build_object('id', c.id, 'name', 'JobPilot IMAP')))::json
FROM credentials_entity c, workflow_entity w
WHERE c.type = 'imap' AND h."workflowId" = w.id AND w.name LIKE '07 %';

SELECT coalesce(c.id, 'MISSING') AS imap_credential_id
FROM credentials_entity c
WHERE c.type = 'imap';
'@

$tmp = Join-Path $env:TEMP 'jobpilot-fix-imap.sql'
[IO.File]::WriteAllText($tmp, $sql, (New-Object System.Text.UTF8Encoding($false)))
cmd /c "docker compose exec -T postgres psql -U n8n -d n8n -f - < `"$tmp`""

# 2. Publish so the running instance picks the change up.
$wfId = (cmd /c "docker compose exec -T postgres psql -U n8n -d n8n -t -A -c ""SELECT id FROM workflow_entity WHERE name LIKE '07 %' LIMIT 1;""") -join ''
$wfId = $wfId.Trim()

if (-not $wfId) {
  Write-Host 'Workflow 07 not found - import it first.' -ForegroundColor Red
  exit 1
}

docker compose exec -T n8n n8n publish:workflow --id=$wfId 2>&1 | Select-Object -Last 1
Write-Host 'Workflow 07 points at your real Gmail credential and is published.' -ForegroundColor Green
