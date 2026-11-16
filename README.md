# JobPilot

**A self-hosted job-hunt pipeline: European + global boards, Adzuna, and your own job-alert emails → normalise → fingerprint dedupe → deterministic score → daily digest → optional AI cover letter.**

Built with n8n Community Edition, PostgreSQL and Docker. No paid subscription, no scraping of sites that forbid it, no "AI magic" you can't explain.

```
 Remotive ──┐
Arbeitnow ──┤
 RemoteOK ──┼─┐
   Jobicy ──┘ │
   Adzuna ────┤  (free API key, country=in)
 LinkedIn ─┐  │
  Indeed ──┼──┤  (your own alert emails, IMAP)
  Naukri ──┘  │
             ▼
        normalise ─► fingerprint ─► INSERT … ON CONFLICT DO NOTHING
             │                              │
             │                              ▼
             │                      jobs (Postgres)
             │                              │
             ├──────────────► score (0-100) ─┤  deterministic, explainable
             │                              ▼
             │                     daily digest (HTML in DB)
             │                              │
             │                    Telegram (optional)
             │                              │
             └──────────► cover letter (Groq, optional, grounded in facts only)
```

---

## The problem

Job hunting is a relevance problem dressed up as a volume problem. Boards are noisy, the same role is syndicated three times, and the good listings are gone in 48 hours. Reading 200 listings a day to find 5 worth applying to does not scale, and neither does an LLM that says "great match!" about everything.

JobPilot makes three things true:

1. **No duplicates.** A role re-posted tomorrow, or listed on two boards, is one row. Dedupe is enforced by a unique constraint, not by hope.
2. **Ranking you can audit.** Each score is a sum of named components with a stored reason list. You can argue with the policy; you cannot argue with a black box.
3. **Nothing runs unattended into your inbox.** The pipeline stops at a reviewable digest.

---

> **First time here?** `docs/ONE_DAY_PLAN.md` is the hour-by-hour path from clone to demo video.

## Quickstart (about 10 minutes)

```powershell
# 1. stack up (Postgres + n8n, schema auto-created)
cp .env.example .env
docker compose up -d

# 2. import the seven workflows
./scripts/import-workflows.ps1

# 3. open the editor
start http://localhost:5678
```

Then, one time in the UI:

- **Credentials → New → Postgres** (name it `JobPilot Postgres`):
  `host=postgres  port=5432  database=n8n  user=n8n  password=<POSTGRES_PASSWORD>`
- Run **01 · Ingest Jobs** → **02 · Score Jobs** manually once.
- Toggle both workflows **Active**.

Check the result:

```powershell
docker compose exec postgres psql -U n8n -d n8n -c "SELECT score, title, company FROM jobs ORDER BY score DESC LIMIT 10;"
```

Optional integrations are env-gated — leave the keys blank and the matching branch is skipped cleanly, not broken:

| Variable | Unlocks | Cost |
| --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` | 03 digest + 04 error alerts | free |
| `GROQ_API_KEY` | 05 AI cover letter | free tier |
| `ADZUNA_APP_ID` + `ADZUNA_APP_KEY` | 06 Adzuna search — Europe plus the US when configured; `ADZUNA_COUNTRIES` / `ADZUNA_QUERIES` control the rest | free |
| IMAP credential (in n8n) | 07 job-alert emails from LinkedIn/Indeed/Naukri | free |

---

## Why not just scrape LinkedIn, Indeed and Naukri?

Because you would be breaking their terms, and they are good at detecting it. Concretely, as of today:

| Site | Public job-search API? | What actually works |
| --- | --- | --- |
| LinkedIn | **No.** The Job Posting API is partner-only (for employers/ATS). Scraping breaches the User Agreement. | Your own LinkedIn **job-alert emails** → workflow 07 |
| Indeed | **No** self-serve search API. Publisher access is approval-only, affiliate feeds are restricted. | Your own Indeed **alert emails** → workflow 07 |
| Naukri | **No** public API. Employer/partner integrations only. | Your own Naukri **alert emails** → workflow 07 |
| Adzuna | **Yes**, free key, 19 countries incl. `de`, `gb`, `nl`, `fr` | workflow 06 |
| Remotive / Arbeitnow / RemoteOK / Jobicy | **Yes**, open endpoints, no key | workflow 01 |

The pattern is: **if you can legally get the data, automate it; if you can't, automate the part you legitimately own.** Your alert inbox is something you own. That's why 07 exists — it parses the emails those three sites already send you, so you still get LinkedIn/Indeed/Naukri coverage without a single forbidden request.

Workflow 07 works on links, not on scraping: it extracts `linkedin.com/jobs/view/<id>`, `indeed.com/viewjob?jk=<id>` and `naukri.com/job-listings-…-<id>`, takes the title and company from the anchor text, and fingerprints on `source + job id`. Duplicate alerts collapse. There is no job description in an alert email, so those rows score on title alone — they are a safety net, not your primary feed.

**Two messages, by design.** 07 sends its own short Telegram message the moment an alert lands — "New job alert from your Gmail - apply now", with the label, company and the direct link for every job newly inserted by that run. Only rows that were actually inserted are announced, so a re-delivered alert never repeats a link. The 09:00 digest (03) is separate: it scores everything, mixes sources, and ranks by region.

**After re-importing 07, run `scripts\fix-imap-credential.ps1`.** The file targets a fresh install and references credential id `jobpilot-imap`; a credential you created in the UI has a different id, and publishing fails with *"Credential JobPilot IMAP no longer exists"*. The script re-points both the live workflow and its version snapshot at the real credential.

## Running 24/7

A laptop that sleeps stops the pipeline: no inbox polling, no 09:00 digest, no Telegram message. To keep it alive, move it to a small server. The server Docker compose file is in `deploy/docker-compose.server.yml`, and `scripts/export-db.ps1` produces the dump that migrates your jobs and workflows.

Run **one** instance at a time. Two copies read the same Gmail inbox and post to the same Telegram chat, so you would receive duplicates.

**One honest limitation:** because there is no description, a LinkedIn row maxes out lower than an Adzuna row with a full snippet. That's expected. If you want depth from those three sites, open the link — the pipeline's job is to make sure you see it.

---

## Region coverage: Europe, Germany, remote, and the US

Every row gets a `country` tag derived from its location text (`Berlin, Germany` → `de`, `London, UK` → `gb`, `Remote` → `remote`). That means "show me only German roles" is one `WHERE`, not a manual scan.

Live sample from the four open boards, checked on 2026-11-13:

| Region tag | Rows |
| --- | --- |
| `remote` | 90 |
| unmatched (unclear location) | 89 |
| `de` | 81 |
| `fr` | 46 |
| `nl` | 42 |
| `gb` | 39 |
| `us` | 26 |
| `ch` | 24 |
| `ca` | 17 |
| **Europe total** | **235 of 461** |

Adzuna adds depth on top of that, because it is the only source here that can be pointed at a named country:

```powershell
# .env
ADZUNA_COUNTRIES=de,at,ch,nl,fr,gb,pl,es,it,us
ADZUNA_QUERIES=software engineer
ADZUNA_MAX_REQUESTS=12
```

`06` builds one request per country × term, applies `category=it-jobs`, and caps the total at `ADZUNA_MAX_REQUESTS` so the free quota survives. Add or remove countries to match your target market.

Useful queries once the data is in:

```sql
-- Germany, shortlisted only
SELECT score, title, company, location, url
FROM jobs
WHERE country = 'de' AND score >= 70
ORDER BY score DESC LIMIT 20;

-- Europe-wide, grouped by how much is shortlisted per country
SELECT country, count(*) AS jobs, count(*) FILTER (WHERE score >= 70) AS shortlisted
FROM jobs
WHERE country IN ('de','at','ch','nl','fr','es','it','pl','ie','gb','se','dk','no','fi','pt','cz','ro')
GROUP BY 1 ORDER BY 3 DESC, 2 DESC;

-- AI / SDE-flavoured roles anywhere in Europe
SELECT country, score, title, company, url
FROM jobs
WHERE score >= 70
  AND country NOT IN ('in')
  AND (title ILIKE '%ai%' OR title ILIKE '%machine learning%'
       OR title ILIKE '%sde%' OR title ILIKE '%software engineer%')
ORDER BY score DESC LIMIT 25;
```

**The part no pipeline can fix:** most EU roles require existing work authorization. The pipeline gets you the shortlist; whether a company sponsors a visa is a per-application question, and you should filter aggressively rather than apply blindly. Look for "visa sponsorship", "relocation support", or an EU entity in the posting.

---

## Design decisions (the interview material)

**Dedupe by fingerprint, enforced in the database.**
`fingerprint = sha256(company | title | location)` after lowercasing, stripping legal suffixes (`Inc`, `Pvt Ltd`, `GmbH`) and punctuation. The column is `UNIQUE`, and every insert is `ON CONFLICT (fingerprint) DO NOTHING`. Consequence: the ingest workflow is **idempotent** — running it twice, or twice at once, cannot create duplicates. Dedupe in application code would have been a race condition.

**Sources fail independently.**
Every HTTP node is `retryOnFail` with a bounded retry and `continueRegularOutput`. One board returning 500 produces a warning and zero items; the other two still land.

**Ranking is deterministic, and the weights are visible.**
40 points skills coverage, 15 bonus stack, 20 title match, 10 remote, 15 recency, −30 for explicit negatives (`commission only`, `10+ years`). Scores are clamped 0–100 and every row stores `score_reasons`, `matched_keywords` and `missing_keywords`. The last one is the useful one: it is a live **resume gap report** — the skills JDs keep asking for that your CV never mentions.

**The LLM is fenced in.**
Cover-letter generation is a separate, optional workflow. The prompt receives a fixed `FACTS` block and is instructed to use nothing else; the missing facts are stated as limitations so the model cannot "helpfully" invent a Kubernetes migration. Prompts are versioned in the row (`prompt_version`) so a quality change is attributable.

**Cost is bounded.**
Zero LLM calls in the ingest and scoring path. One call per approved application. Scoring 1,200 jobs/month costs nothing but HTTP requests.

**Errors are a first-class path.**
`04 · Error Handler` logs to an `incidents` table before alerting, so a failed Telegram call cannot lose the error.

---

## Verified on this machine

Numbers from the first real run, not estimates:

| Check | Result |
| --- | --- |
| Postings fetched from 4 boards | 457 (Arbeitnow 296, RemoteOK 98, Jobicy 50, Remotive 13) |
| SQL statements generated | 7, 1.7 MB total, inserted in one pass |
| Replayed the same ingest immediately | **457 → 457 rows, 0 duplicates** |
| Scored | 457/457, average 34, **41 roles ≥ 70 (9%)** |
| Double-encoded source text found and repaired | 3 rows, 0 remaining |
| Workflow JSON imports | 7/7 clean, 0 structural errors |
| Alert-email parser (synthetic alerts) | 3/3 sources extracted correctly; duplicate link collapsed; unrelated email ignored |
| Region tagging (live sample, 2026-11-13) | 235/461 rows tagged Europe (de 81, fr 46, nl 42, gb 39, ch 24); 158 software/AI/SDE titles |
| Adzuna multi-country builder | 10 countries × 1 term capped to 12 requests; failed country skipped, `category=it-jobs` applied |
| Adzuna live pull (2026-11-14) | 500 results across `de,at,ch,nl,fr,gb,pl,es,it,us`; 489 Adzuna rows after fingerprint dedupe |
| Regional digest | 20 slots: 6 held for intern/junior roles, then 6 Europe + 4 United States + 4 Remote/Global, then backfill from the best remaining; NULL-country rows are handled safely |
| Fresher / contract / OSS slots | `seniority` (intern / junior / mid / senior) and `work_type` (contract / open_source / standard) are both generated from the text. 6 of the 20 slots are held for junior/graduate, contract and open-source roles; internships are excluded. Score bars: 40 junior, 50 contract/OSS, 55 otherwise |
| Visa signal (`visa_signal`) | Generated column over title + description: `sponsor` / `relocation` / `no_sponsor` / `unknown`. Ads that explicitly refuse sponsorship are dropped, sponsored ones rank first, and every digest line is badged ✅ / 🌍 / ❓ |
| Adzuna normaliser (documented response shape) | backend role scored 79, commission-only sales role scored 0 |

That 9% is the point: the boards are ~90% noise, and the ranking is what turns them into twenty applications a day.

---

## Evaluation

"AI ranks my jobs" is a claim until you measure it. So:

```powershell
./scripts/export-scores.ps1        # current ranking -> eval/scores.csv
# hand-label 20 jobs in eval/labels.csv (1 = you'd apply)
node eval/evaluate.mjs
```

Output is precision@5/10/20 and a threshold sweep. Format:

```
Labeled jobs in ranking: 20   relevant: 9

k    precision@k   recall@k
5    4/5 = 0.80    0.44
10   7/10 = 0.70   0.78
20   9/20 = 0.45   1.00
```

Tune the weights until precision@10 is defensible, then put the number in this README. Being able to say *"precision@10 was 0.70 on 20 hand-labeled jobs, and I know why the false positives slipped through"* is worth more than any feature list.

---

## Repo layout

```
docker-compose.yml        n8n + Postgres, healthchecked, env-gated integrations
db/init.sql               schema, indexes, funnel view, constraints
workflows/
  01-ingest-jobs.json     schedule → 4 boards → normalise → dedupe → upsert
  02-score-jobs.json      unscored queue → deterministic score → gap report
  03-daily-digest.json    20 slots: 6 held for fresher/contract/OSS + 6 EU / 4 US / 4 remote, backfilled, sponsorship-aware → HTML → DB → Telegram
  04-error-handler.json   error trigger → incidents table → alert
  05-ai-cover-letter.json manual → grounded prompt → Groq → store
  06-ingest-adzuna.json   Adzuna country-targeted search, env-gated, no key = green skip
  07-ingest-job-alerts.json IMAP trigger → LinkedIn/Indeed/Naukri alert emails
scripts/
  start.ps1               cold boot + readiness wait
  import-workflows.ps1    import all JSON into the container
  export-scores.ps1       ranking export for evaluation
  reset.ps1               wipe volumes and start clean before a demo
  validate-workflows.mjs  structural lint, fails CI on broken connections
eval/
  labels.csv              your hand labels
  evaluate.mjs            precision@k, recall@k, threshold sweep
```

---

## Security and privacy

- Credentials live only in n8n's encrypted store; the database password is in `.env`, which is gitignored.
- No resume PDF is uploaded anywhere. The `FACTS` block is the only personal context sent to a model, and it is yours to edit.
- Only official APIs and public job-board feeds are used. Nothing here scrapes a site whose Terms of Service forbid it — that matters, because the alternative is an account ban and a story you can't tell an interviewer.
- Execution data is local. `N8N_DIAGNOSTICS_ENABLED=false`.
- `.env`, database exports, backups, and personal resume files are intentionally excluded from Git.
- Before publishing a fork, check `git status --ignored` and never commit real API keys, bot tokens, app passwords, or `N8N_ENCRYPTION_KEY`.

## Known limitations

- Fingerprint dedupe catches re-posts and syndication, not near-duplicates with reworded titles. Embedding similarity is the next step.
- Adzuna returns a description *snippet*, not the full advert, and alert-email rows carry no description at all — both rank on title plus whatever text exists.
- Scoring is keyword-based. It cannot read "we'll teach you the stack" as a positive.
- Single-user design: no per-user profiles, no multi-tenant isolation.
- No auto-apply. Deliberate — auto-apply tools burn your reputation with recruiters.

## Roadmap

1. Embedding-based near-duplicate collapse.
2. Gmail trigger: classify replies (rejection / screen / interview) and auto-advance `status`.
3. Follow-up scheduler: `applications.follow_up_on` drives a D+5 / D+10 reminder.
4. Per-source yield metrics — which board actually produces interviews.

---

## What this demonstrates

Dockerised local infrastructure · workflow orchestration · idempotent data ingestion · schema and index design · explainable ranking · LLM grounding and prompt versioning · failure isolation · encoding repair on dirty third-party feeds · evaluation harness · env-gated optional integrations · documentation.
