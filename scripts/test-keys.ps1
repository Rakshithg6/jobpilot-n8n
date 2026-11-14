# Checks the optional API keys in .env without ever printing them.
# Usage:  .\scripts\test-keys.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent (Get-Location).Path }
$envFile = Join-Path $root '.env'

if (-not (Test-Path $envFile)) {
  Write-Host "No .env found at $envFile" -ForegroundColor Red
  exit 1
}

function Get-EnvValue([string]$name) {
  foreach ($line in [IO.File]::ReadAllLines($envFile)) {
    if ($line -match "^\s*$([regex]::Escape($name))\s*=\s*(.*)$") { return $Matches[1].Trim() }
  }
  return ''
}

function Describe([string]$v) {
  if ([string]::IsNullOrWhiteSpace($v)) { return 'MISSING' }
  return 'set (' + $v.Length + ' chars, starts ' + $v.Substring(0, [Math]::Min(4, $v.Length)) + '...)'
}

$adzId  = Get-EnvValue 'ADZUNA_APP_ID'
$adzKey = Get-EnvValue 'ADZUNA_APP_KEY'
$groq   = Get-EnvValue 'GROQ_API_KEY'

Write-Host ''
Write-Host 'JobPilot key check' -ForegroundColor Cyan
Write-Host ('  ADZUNA_APP_ID  ' + (Describe $adzId))
Write-Host ('  ADZUNA_APP_KEY ' + (Describe $adzKey))
Write-Host ('  GROQ_API_KEY   ' + (Describe $groq))

$failures = 0

# ---------------------------------------------------------------- Adzuna
Write-Host ''
if (-not $adzId -or -not $adzKey) {
  Write-Host 'Adzuna: SKIP - keys not set (workflow 06 will skip itself, green).' -ForegroundColor Yellow
} else {
  $url = 'https://api.adzuna.com/v1/api/jobs/de/search/1' +
         '?app_id=' + [uri]::EscapeDataString($adzId) +
         '&app_key=' + [uri]::EscapeDataString($adzKey) +
         '&results_per_page=2&what=software%20engineer&content-type=application/json'
  try {
    $r = Invoke-RestMethod -Uri $url -TimeoutSec 25
    $n = @($r.results).Count
    Write-Host "Adzuna: PASS - Germany search returned $n job(s) for 'software engineer'." -ForegroundColor Green
  } catch {
    $failures++
    $body = $_.ErrorDetails.Message
    Write-Host ('Adzuna: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    if ($body) { Write-Host ('  ' + $body) -ForegroundColor DarkGray }
    Write-Host '  Check: app_id is the short id, app_key the long one. Re-run after fixing .env.' -ForegroundColor DarkGray
  }
}

# ---------------------------------------------------------------- Groq
Write-Host ''
if (-not $groq) {
  Write-Host 'Groq: SKIP - GROQ_API_KEY not set (workflow 05 will skip, green).' -ForegroundColor Yellow
} else {
  $payload = @{
    model = 'openai/gpt-oss-120b'
    temperature = 0.4
    reasoning_effort = 'low'
    max_tokens = 40
    messages = @(@{ role = 'user'; content = 'Reply with exactly: OK' })
  } | ConvertTo-Json -Depth 6

  try {
    $r = Invoke-RestMethod -Uri 'https://api.groq.com/openai/v1/chat/completions' -Method Post `
      -Headers @{ Authorization = "Bearer $groq" } -ContentType 'application/json' -Body $payload -TimeoutSec 40
    Write-Host ('Groq: PASS - ' + $r.model + ' replied: ' + $r.choices[0].message.content) -ForegroundColor Green
  } catch {
    $failures++
    Write-Host ('Groq: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('  ' + $_.ErrorDetails.Message) -ForegroundColor DarkGray
  }
}

Write-Host ''
if ($failures -eq 0) {
  Write-Host 'All configured keys work.' -ForegroundColor Green
} else {
  Write-Host "$failures check(s) failed - see above." -ForegroundColor Red
  exit 1
}
