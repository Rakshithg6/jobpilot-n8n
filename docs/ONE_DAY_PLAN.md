# One-day build plan

The repo is already written. This is the sequence to make it *yours* and turn it into something you can show. Times assume a normal laptop and a decent connection.

Be honest with yourself about the goal: today you can ship a working, documented, demoable project. You cannot also run four weeks of tuning. Ship the MVP, then keep the eval loop running in the background over the next two weeks — that's the story.

---

## Block 1 — get it running (60–90 min)

- [ ] Install / start Docker Desktop. Verify: `docker info`
- [ ] `cd jobpilot && cp .env.example .env`
- [ ] `docker compose up -d` → wait for `http://localhost:5678` to load
- [ ] Create owner account in n8n
- [ ] Create the **JobPilot Postgres** credential (`host=postgres`, port 5432, db `n8n`, user `n8n`, password from `.env`)
- [ ] `./scripts/import-workflows.ps1`
- [ ] Open each Postgres node once and confirm the credential is selected (imports can leave it unattached)
- [ ] Run **01 · Ingest Jobs** → expect ~450 rows fetched, ~450 inserted on a clean database
- [ ] Run it again → expect `new_rows: 0`. **If this fails, fix it before anything else** — idempotency is the centrepiece of your story.
- [ ] Run **02 · Score Jobs** → check the summary output

**Checkpoint:** `SELECT count(*), count(*) FILTER (WHERE score >= 70) FROM jobs;` returns sane numbers.

## Block 2 — make it yours (45–60 min)

- [ ] Edit `PROFILE` in workflow 02 (titles, must-have, nice-to-have, negatives) to match *your* stack
- [ ] Re-run 02 with `UPDATE jobs SET score = NULL;` first
- [ ] Look at the top 10 by hand. If a role is wrong, note *which weight* was wrong — that's the bug, not the score
- [ ] Edit the `FACTS` block in workflow 05 with your real background (no embellishment — the prompt will amplify it)
- [ ] Update `README.md`: your name, your stack, the real counts from your run

## Block 3 — Telegram, if you have 20 minutes (optional)

- [ ] @BotFather → `/newbot` → copy token
- [ ] Message your bot once, then `https://api.telegram.org/bot<TOKEN>/getUpdates` → copy `chat.id`
- [ ] Put both in `.env`, `docker compose up -d` (recreates n8n with the new env)
- [ ] Run **03 · Daily Digest** → message arrives
- [ ] Activate 01, 02, 03, and set 04 as the **Error Workflow** in each workflow's settings
- [ ] Trigger a deliberate failure (point an HTTP node at a bad URL) → incident row + alert

## Block 3.5 — India sources (optional, 25 min)

Only if you want LinkedIn/Indeed/Naukri coverage.

- [ ] Sign up at `developer.adzuna.com/signup` → copy `app_id` + `app_key`
- [ ] Add `ADZUNA_APP_ID`, `ADZUNA_APP_KEY`, `ADZUNA_COUNTRY=in`, `ADZUNA_QUERY=<your role>` to `.env`
- [ ] `docker compose up -d --force-recreate n8n` → run **06 · Ingest Adzuna**
- [ ] Gmail: enable 2FA → create an App Password → in n8n, Credentials → New → IMAP (`imap.gmail.com`, 993, SSL, your address + app password)
- [ ] Open **07 · Ingest Job-Alert Emails** → select that credential
- [ ] Make sure you actually receive alerts: LinkedIn "Job alert", Indeed "Email alerts", Naukri "Job alerts"
- [ ] Send yourself/await one alert → run the workflow → check `SELECT source, count(*) FROM jobs GROUP BY source;`

If that last query shows `linkedin` / `indeed` / `naukri` rows, you have the thing you originally asked for.

## Block 4 — evidence (60 min) ← the part people skip

- [ ] `./scripts/export-scores.ps1`
- [ ] Hand-label 20 rows in `eval/labels.csv` (15 minutes, genuinely useful)
- [ ] `node eval/evaluate.mjs` → paste the real numbers into the README
- [ ] Screenshot: n8n canvas, second-run output showing 0 duplicates, a top-10 SQL result, the Telegram digest
- [ ] `node scripts/validate-workflows.mjs` → 0 errors (put it in CI later if you like)
- [ ] `git init && git add . && git commit` → push to GitHub with a real description and the topics `n8n`, `automation`, `postgres`, `docker`, `llm`

## Block 5 — demo (30–45 min)

- [ ] Record 2 minutes following `docs/DEMO_SCRIPT.md`. One take is fine; do the second-run-inserts-zero moment live
- [ ] Upload to YouTube (unlisted) or Loom, link it at the top of the README
- [ ] Add the repo to your resume under Projects, with two bullets:

> Built a self-hosted n8n + PostgreSQL pipeline ingesting job postings from 4 boards, with SHA-256 fingerprint deduplication and idempotent upserts (verified: 457 postings, 0 duplicates on replay).
>
> Designed a transparent ranking policy (precision@10 = 0.__ on 20 hand-labeled listings), a daily digest, and fact-grounded LLM cover-letter generation with prompt versioning and error isolation.

---

## Reality check

A project does not land a job; it makes your resume survive the six-second scan and gives you 40 minutes of real material in the interview. Pair this with:

- applying to 5 well-matched roles a day using the shortlist this produces,
- one thoughtful message to a human per application,
- and being able to answer every question in `docs/INTERVIEW_NOTES.md` without notes.

If you get to the end of Block 5 today, you're ahead of most candidates. The next two weeks are where precision@10 goes from 0.5 to 0.8 — and that improvement *is* the follow-up story you tell in the second interview.
