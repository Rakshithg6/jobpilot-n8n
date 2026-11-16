# JobPilot, explained from zero

Written for someone who has not used n8n before. Read top to bottom; everything here maps to a file in this repo.

---

## 1. The one-paragraph version

Four job boards publish jobs as JSON over HTTP. A scheduled n8n workflow downloads them, converts four different shapes into one shape, throws away anything it has already seen, and writes the rest into PostgreSQL. A second workflow scores every new row 0–100 against a rubric you control. A third workflow emails/texts you the top 20 each morning. Nothing here is magic: it is a cron job, four HTTP calls, some JavaScript, and SQL.

---

## 2. Mental model: what n8n actually is

n8n is a program that runs **workflows**. A workflow is a chain of **nodes**. Each node does one thing and passes data to the next.

Four node types carry this whole project:

| Node type | What it does | Analogy |
| --- | --- | --- |
| **Trigger** | Starts the workflow (clock, webhook, manual click, error) | the alarm clock |
| **HTTP Request** | Calls a URL and gets JSON back | `curl` |
| **Code** | Runs JavaScript you wrote | a function |
| **Postgres** | Runs a SQL query against the database | `psql` |

Data between nodes is a **list of items**, each item looks like `{ "json": { ...fields... } }`. Every node receives `$input.all()` — the array of items from the previous node. That's the only data model you need to understand.

An **execution** is one run of a workflow. n8n stores every execution, so you can click it later and inspect exactly what each node received and produced.

---

## 3. The three flows in plain English

### Flow A — collect (workflow 01)

```
alarm (every 6h)
   ├─ GET remotive.com/api/remote-jobs   → { jobs: [ … ] }
   ├─ GET arbeitnow.com/api/job-board-api → { data: [ … ] }
   ├─ GET remoteok.com/api                → [ … ]        (array!)
   └─ GET jobicy.com/api/v2/remote-jobs   → { jobs: [ … ] } (different field names)
        ↓
   one JavaScript block turns all four into the same 11 fields
        ↓
   one JavaScript block turns those rows into INSERT statements
        ↓
   Postgres runs them; duplicates are silently skipped by the database
```

### Flow B — rank (workflow 02)

```
alarm (every 6h)
   ↓
SELECT … WHERE score IS NULL LIMIT 150      ← only new rows
   ↓
JavaScript: 40 pts skills + 15 stack + 20 title + 10 remote + 15 recency − 30 penalties
   ↓
one UPDATE statement writes score + reasons + matched/missing keywords
```

### Flow C — deliver (workflow 03)

```
alarm (09:00 daily)
   ↓
SELECT top 20 WHERE score >= 55 AND status = 'new' AND digested_at IS NULL
   -- Europe/EEA rows sort first, then by score, so German roles are not
   -- crowded out by remote or US postings.
   ↓
JavaScript builds an HTML table and a plain-text message
   ↓
save the HTML into the digests table
   ↓
if TELEGRAM_CHAT_ID is set  →  POST to Telegram
else                        →  skip, green workflow
   ↓
stamp digested_at on those rows (only if the message was actually delivered)
   ↓
digest summary
```

Two supporting flows: **04** catches failures (error trigger → incidents table → alert) and **05** generates one cover letter on demand (manual trigger → prompt → Groq → stored).

---

## 4. File by file: what and why

| File | What it is | Why it exists |
| --- | --- | --- |
| `docker-compose.yml` | Recipe for two containers: `n8n` and `postgres` | One command reproduces your whole environment |
| `.env` / `.env.example` | Passwords and optional API keys | Secrets never live in the workflow JSON or git |
| `db/init.sql` | Table definitions, indexes, a view | Postgres runs this automatically on first boot, so the schema always exists |
| `workflows/01-ingest-jobs.json` | Flow A | The only workflow that talks to the internet's job boards |
| `workflows/02-score-jobs.json` | Flow B | Ranking policy, editable in one block |
| `workflows/03-daily-digest.json` | Flow C | The part you actually look at |
| `workflows/04-error-handler.json` | Failure path | So a 3 a.m. failure leaves a row behind, not silence |
| `workflows/05-ai-cover-letter.json` | Optional AI | Only place an LLM is used |
| `workflows/06-ingest-adzuna.json` | Adzuna, one request per country | The only source you can point at a named country (Europe/India) |
| `workflows/07-ingest-job-alerts.json` | IMAP → LinkedIn/Indeed/Naukri links | The legal way to cover those three sites |
| `scripts/start.ps1` | Boot + wait for readiness | Removes the "is it up yet?" guesswork |
| `scripts/import-workflows.ps1` | Loads the 5 JSONs into n8n | The JSON files are the source of truth, not the UI |
| `scripts/reset.ps1` | Deletes both volumes | Clean slate before a demo |
| `scripts/export-scores.ps1` | Dumps the ranking to CSV | Input for evaluation |
| `scripts/validate-workflows.mjs` | Structural lint | Catches broken connections before import; runnable in CI |
| `eval/evaluate.mjs` | precision@k calculator | Turns "it ranks well" into a number |
| `README.md` | The recruiter-facing document | Six-second scan + interview prep |

Workflow JSON files are exported from n8n (or here, written directly). They are the portable, version-controlled form of what you see on the canvas.

---

## 5. The database, table by table

Everything lives in the same Postgres database that n8n uses for itself (database `n8n`, user `n8n`).

### `jobs` — the main table

| Column | Meaning |
| --- | --- |
| `id` | auto number |
| `source` | `remotive` / `arbeitnow` / `remoteok` / `jobicy` |
| `external_id` | the board's own id |
| `title`, `company`, `location`, `url`, `description`, `salary_text`, `tags` | normalised fields |
| `country` | coarse region tag: `de`, `gb`, `nl`, `us`, `in`, `remote`, … |
| `visa_signal` | **generated** from title + description: `sponsor`, `relocation`, `no_sponsor`, `unknown` |
| **`fingerprint`** | `sha256(company + title + location)`, normalised — **UNIQUE** |
| `score` | 0–100, NULL until workflow 02 runs |
| `score_reasons` | JSON array like `["skills 40/40 (api, sql, docker)", …]` |
| `matched_keywords`, `missing_keywords` | what the JD wants vs what your profile claims |
| `status` | `new` → `shortlisted` → `applied` → `interview` / `rejected` |
| `first_seen`, `updated_at`, `posted_at` | timestamps |

The line that makes this project work is this one in `db/init.sql`:

```sql
CONSTRAINT jobs_fingerprint_key UNIQUE (fingerprint)
```

and this one in the INSERT:

```sql
ON CONFLICT (fingerprint) DO NOTHING
```

Read that as: *"if a row with this fingerprint already exists, do nothing and don't error."* That single pair is why running the ingest twice cannot create duplicates. **Idempotency is a database property here, not a code convention.**

### The other tables

| Table | Purpose |
| --- | --- |
| `digests` | every rendered daily digest (HTML + count) — audit trail |
| `applications` | what you applied to, when, outcome, follow-up date |
| `incidents` | every workflow failure, before any alert is attempted |

### The view

`v_funnel` groups `jobs` by day: seen → shortlisted → applied → interviews. Run it once a week and you have a real funnel, not a feeling.

---

## 6. Workflow 01, node by node

| Node | Type | What it does | Why |
| --- | --- | --- | --- |
| `Every 6 hours` | Schedule Trigger | fires on a clock interval | no machine needs to be open |
| `Remotive`, `Arbeitnow`, `RemoteOK`, `Jobicy` | HTTP Request | four GETs, run in parallel | one board down ≠ run fails; each has retry ×2 and continue-on-error |
| `Normalise jobs` | Code | detects which shape arrived, maps to 11 fields, cleans HTML, fixes mojibake, computes fingerprint, dedupes inside the batch | four APIs, one schema |
| `Build SQL chunks` | Code | builds `INSERT … VALUES (…), (…) ON CONFLICT DO NOTHING`, 75 rows per statement | 450 rows in ~7 round trips instead of 450 |
| `Upsert jobs` | Postgres | executes the SQL | the only node that touches the DB |
| `Run summary` | Code | reports fetched / unique / new / duplicates | the numbers you quote in the demo |

Why chunk at 75: one 1.7 MB statement is unwieldy to debug; 450 tiny statements are slow. 75 is the middle.

Why fingerprint rather than the board's id: the same job appears on three boards with three ids. Identity has to come from the content, not the source.

---

## 7. Workflow 02, node by node

| Node | Type | What it does |
| --- | --- | --- |
| `Every 6 hours` | Schedule Trigger | same clock |
| `Unscored jobs` | Postgres | `SELECT … WHERE score IS NULL LIMIT 150` |
| `Score` | Code | the **policy** — `PROFILE` block at the top with titles / mustHave / niceToHave / negative |
| `Build UPDATE` | Code | one `UPDATE … FROM (VALUES …)` for 100 rows |
| `Apply scores` | Postgres | executes it |
| `Scoring summary` | Code | average score, shortlist count, top missing skills |

The scoring maths, exactly:

```
skills   = min(matched mustHave / 3, 1) × 40
bonus    = min(matched niceToHave / 4, 1) × 15
title    = 20 if the title contains a role word, else 0
remote   = 10 if location/description says remote
recency  = 15 / 10 / 5 / 0 for ≤7 / ≤14 / ≤30 / older days
penalty  = −30 if a negative phrase appears ("commission only", "10+ years")
result   = clamp(0, 100, sum)
```

`missing_keywords` = must-have skills the JD never mentions. That is a **resume gap report**: if "docker" is missing from 60% of the good roles, that is a sentence to add to your CV — truthfully.

**First run note:** the limit is 150 per execution, so after the first ingest run workflow 02 three or four times until the queue is empty. After that, 6-hourly runs keep up.

---

## 8. Workflow 03, node by node

| Node | Type | What it does |
| --- | --- | --- |
| `Every day at 09:00` | Schedule Trigger | Asia/Kolkata (from `TZ`) |
| `Top matches` | Postgres | top 20 (8 Europe / 6 US / 6 Remote) with `score >= 55 AND status = 'new'` and `digested_at IS NULL`, skipping `visa_signal = 'no_sponsor'`; sponsorship/relocation rows rank before plain score |
| `Build digest` | Code | HTML table + Telegram text + the INSERT for the audit row |
| `Store digest` | Postgres | saves it, so the digest survives even if Telegram is down |
| `Telegram configured?` | IF | checks `$env.TELEGRAM_CHAT_ID` |
| `Split messages` | Code | one item per message, so a 20-job digest is never cut off by Telegram's 4096-character cap |
| `Send to Telegram` | HTTP Request | `POST api.telegram.org/bot<token>/sendMessage`, once per item |
| `Digest summary` | Code | one-line result |

Order matters: **store first, send second.** If the messenger fails you still have the digest.

**Visa sponsorship is a data problem, not a filter.** Adzuna publishes no sponsorship flag, and only about 1% of postings mention immigration at all — so "sponsored roles only" would return an empty list most days. Instead `jobs.visa_signal` is a **generated column** (`db/add-visa-signal.sql`): Postgres reads the ad text and stores `sponsor` (✅), `relocation` (🌍), `unknown` (❓, the normal case) or `no_sponsor` (⛔). The digest drops the ⛔ rows, ranks ✅/🌍 first and badges every line, and because the column is generated it can never drift out of sync with the job text.

---

## 9. Workflows 04 and 05

**04** uses an Error Trigger — a special trigger that n8n fires when *another* workflow fails. It formats the failure, writes `incidents`, then alerts. You attach it per workflow in that workflow's **Settings → Error Workflow**.

**05** is manual-only by design. It picks the highest-scoring job without a letter, builds a prompt containing a `FACTS` block you edit, calls Groq (OpenAI-compatible API), extracts `choices[0].message.content`, and saves it to `jobs.cover_letter`. If `GROQ_API_KEY` is empty, an IF node routes to an "explain skip" node instead of failing.

---

## 10. The APIs: what to connect, and what costs money

### Nothing to connect (no key, no signup)

| Source | Endpoint | Shape |
| --- | --- | --- |
| Remotive | `https://remotive.com/api/remote-jobs?limit=50` | `{ jobs: [...] }` |
| Arbeitnow | `https://www.arbeitnow.com/api/job-board-api` | `{ data: [...] }` |
| RemoteOK | `https://remoteok.com/api` | `[ ... ]` (first element is a legal notice) |
| Jobicy | `https://jobicy.com/api/v2/remote-jobs?count=50` | `{ jobs: [...] }` with `jobTitle`/`companyName` |

### Required, created once inside n8n (not an API key — a DB login)

**Postgres credential**, name `JobPilot Postgres`:

| Field | Value |
| --- | --- |
| Host | `postgres` (the container name — not `localhost`) |
| Port | `5432` (the container's port; `5433` is the host's) |
| Database | `n8n` |
| User | `n8n` |
| Password | whatever is in `.env` → default `jobpilot` |
| SSL | off |

Every Postgres node needs this selected. If you see "Credential not found" after import, open the node and pick it from the dropdown.

### Optional, free, env-gated

| Key | Where to get it | Enables | Without it |
| --- | --- | --- | --- |
| `GROQ_API_KEY` | console.groq.com/keys (no card) | workflow 05 | IF routes to "Explain skip", workflow stays green |
| `TELEGRAM_BOT_TOKEN` | @BotFather → `/newbot` | 03 and 04 | digest stored in DB only |
| `TELEGRAM_CHAT_ID` | message your bot, then `api.telegram.org/bot<TOKEN>/getUpdates` | 03 and 04 | same |

**Two different mechanisms, don't mix them up:**

- `.env` → container environment → read in nodes as `$env.NAME`. Used for optional integrations.
- n8n credential store → encrypted in n8n's database → attached to a node. Used for Postgres.

After editing `.env` you must recreate the container: `docker compose up -d --force-recreate n8n`.

### Why the pipeline doesn't fetch LinkedIn, Indeed or Naukri directly

It isn't missing. It is deliberately not doing something that would get your account banned.

| Site | Public search API | Legal path |
| --- | --- | --- |
| LinkedIn | No (partner-only posting API, scraping forbidden) | your alert emails |
| Indeed | No (publisher access is approval-only) | your alert emails |
| Naukri | No (employer integrations only) | your alert emails |
| Adzuna | **Yes**, free key, `country=in` | workflow 06 |
| Remotive / Arbeitnow / RemoteOK / Jobicy | **Yes**, open, no key | workflow 01 |

Workflow 07 is the answer to "but I want those three": set up job alerts on each site, let the emails arrive, and parse the links out of them. You are reading your own mail — nothing forbidden, no bot detection, no CAPTCHA arms race.

What it extracts: `linkedin.com/jobs/view/<id>`, `indeed.com/viewjob?jk=<id>`, `naukri.com/job-listings-…-<id>`. Title and company come from the link text ("Backend Engineer at Acme Corp"); Naukri titles are reconstructed from the URL slug. Identity is `source + job id`, so the same alert arriving twice inserts once.

### Adzuna in one minute

1. Sign up at `developer.adzuna.com/signup` → you get `app_id` and `app_key`.
2. Put both in `.env`, then set the coverage you want:
   `ADZUNA_COUNTRIES=de,at,ch,nl,fr,gb,pl,es,it`, `ADZUNA_QUERIES=software engineer`, `ADZUNA_MAX_REQUESTS=12`.
3. `docker compose up -d --force-recreate n8n`, then run workflow 06.

Workflow 06 builds **one request per country × search term**, filters with `category=it-jobs`, and stops at `ADZUNA_MAX_REQUESTS` so the free quota lasts. The combos are term-major, so when the cap bites it drops extra search terms before it drops countries. A failed country (bad code, quota) is skipped and the rest still insert — the same failure isolation as workflow 01.

No key? Workflow 06 takes the false branch and reports "skipped" — green, not red.

---

## 11. Run order, with what you should see

1. `docker compose ps` → two containers `Up`, postgres `(healthy)`.
2. open `http://localhost:5678`, create the owner account.
3. create the `JobPilot Postgres` credential, test it, save.
4. `./scripts/import-workflows.ps1` → "Successfully imported 5 workflows".
5. open **01 · Ingest Jobs** → **Execute workflow**.
   - Expect ~450 fetched, ~450 new on a clean DB.
   - Click a node, look at **Output** — that is the actual JSON flowing through.
6. execute **01** again → `new_rows: 0`, `duplicates_skipped: ~450`. **This is the proof.**
7. open **02 · Score Jobs** → execute three or four times until `scored: 0`.
8. open **03 · Daily Digest** → execute → `matches: 20`.
9. `./scripts/export-scores.ps1` → `node eval/evaluate.mjs` after labelling.

Between steps, this query is your ground truth:

```sql
SELECT count(*) AS total,
       count(*) FILTER (WHERE score IS NULL) AS unscored,
       count(*) FILTER (WHERE score >= 70) AS shortlist
FROM jobs;
```

---

## 12. What I ran that you didn't see

During the build I also ran the workflow's **code** outside n8n, against the live APIs, to prove the logic before you touched the UI. That's where the 457/41/0-duplicates numbers come from, and it's why the `exports/` folder has `.sql` and `.json` files. It is a test harness, not part of the product.

What that proved: the four API shapes parse; 457 unique rows come out; the generated SQL is valid; replaying it inserts nothing; the score SQL updates 457 rows; the digest HTML renders; the error formatter produces a valid incident insert; the cover-letter prompt builds.

What it did **not** prove: your n8n credential wiring and your click-through. That's step 11.

---

## 13. Glossary you'll be asked about

| Term | Meaning here |
| --- | --- |
| **Workflow / node / execution** | the program / one step / one run |
| **Trigger** | what starts a run |
| **Upsert** | insert, or update if it exists — here, insert-or-skip |
| **Idempotent** | running it twice equals running it once |
| **Fingerprint** | a short hash that stands in for the identity of a job |
| **Dedupe** | collapsing repeats to one row |
| **Normalisation** | forcing different sources into one schema |
| **Env-gated** | feature off unless an environment variable is set |
| **Error workflow** | a workflow that runs when another one fails |
| **Precision@10** | of the 10 you'd be shown, how many were actually relevant |

---

## 14. The three-sentence explanation

> I built a self-hosted n8n pipeline that pulls job postings from four public APIs, normalises them into one Postgres schema, and deduplicates with a unique SHA-256 fingerprint so re-running is idempotent. A deterministic scoring policy ranks each role against my profile and reports which skills the market keeps asking for that my CV omits. A daily digest surfaces the top twenty, and an optional LLM writes a cover letter that is constrained to a fixed facts block.
