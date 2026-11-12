# 2-minute demo script

Record with OBS, Loom or the Windows Game Bar (`Win+G`). No talking head — screen + voice. Post it on LinkedIn with the GitHub link, and put the link at the top of your resume.

**Before recording**

- [ ] `.env` filled, stack running, `01` and `02` already executed once
- [ ] `./scripts/reset.ps1` (then re-import) if you want a clean first run
- [ ] Browser zoom 110%, one tab on n8n, one terminal, one tab on the GitHub README
- [ ] Close notifications. Silence your phone.

---

### 0:00–0:15 — the hook

> "I was spending about two hours a day reading job listings to find five worth applying to. So I built a pipeline that does the reading and hands me a ranked shortlist. It runs on my laptop, self-hosted, and it costs nothing per month."

Show the README architecture diagram.

### 0:15–0:45 — ingest + dedupe

Run **01 · Ingest Jobs**. While it executes:

> "Four boards — Remotive, Arbeitnow, RemoteOK and Jobicy — pull in different JSON shapes. One returns an array, two wrap it in an object, and one names the fields completely differently. I normalise all of them to one schema and compute a fingerprint from company, title and location after stripping legal suffixes. The fingerprint is a unique column, so every insert is `ON CONFLICT DO NOTHING`. That makes the whole workflow idempotent — I can run it a hundred times and never see a duplicate."

Open the execution output: `fetched`, `new_rows`, `duplicates_skipped`.

> "On my machine that's 457 postings from four boards, and the second run inserts zero. The numbers come from the run summary node, not from a slide."

Run it **again** live, same second run shows `new_rows: 0`. **This is the moment that lands.** Do not skip it.

### 0:45–1:15 — scoring

Run **02 · Score Jobs**, then show one row:

```sql
SELECT score, title, company, score_reasons FROM jobs ORDER BY score DESC LIMIT 3;
```

> "Ranking is deterministic on purpose. Skills coverage is 40 points, stack bonus 15, title match 20, remote 10, recency 15, and a hard −30 for things like 'commission only'. Every score stores its own reasoning, so when it's wrong I can see which weight is wrong — instead of an LLM telling me 'great match' about a sales role."

Show `missing_keywords`.

> "This column is the one I actually use: the skills the market keeps asking for that my resume never mentions."

### 1:15–1:40 — digest + guardrail

Run **03 · Daily Digest**, show the Telegram message (or the HTML in the `digests` table).

> "Top ten by score, once a day, to my phone. It never applies for me — auto-apply tools burn your reputation with recruiters, and I'd rather spend ninety seconds reviewing than undo a bad application."

### 1:40–2:00 — the engineering bit and the close

Show `04 · Error Handler` and `eval/`.

> "Every HTTP node has bounded retries and continue-on-fail, so one board going down doesn't kill the run. Errors get logged to an incidents table before any alert is sent. And because 'the AI ranks my jobs' is just a claim, the repo ships an eval script: I hand-label listings, export the ranking, and get precision@10 plus a threshold sweep. The whole thing is Dockerised and runs with `docker compose up`."

---

## Things to say if they ask follow-ups

- **"Why n8n and not Zapier?"** — self-hosted, no per-task pricing, real Code/Postgres nodes, and I can read every execution trace. For a personal tool with no budget, that's decisive.
- **"Why deterministic scoring instead of an LLM score?"** — reproducibility and debuggability. An LLM score changes when the model changes; mine changes when I change a weight, and I can show you the diff.
- **"What breaks first at scale?"** — the fingerprint dedupe stops being enough: reworded titles create near-duplicates. Next step is embeddings plus a similarity threshold, and I'd move the insert to a queue-mode worker.
