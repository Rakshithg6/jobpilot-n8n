# Interview notes

Short, specific answers. Every one of these is grounded in a real line of code in this repo — never claim something the repo doesn't do.

### 1. What did you build, in one sentence?

> A self-hosted n8n pipeline that ingests job postings from four APIs, collapses duplicates with a database-enforced fingerprint, scores them against a transparent rubric, and delivers a daily shortlist — with optional, fact-grounded cover-letter generation.

### 2. Why n8n instead of code or Zapier?

> Zapier prices per task and I'd be paying to move data between my own tools. Hand-rolling it would have been 800 lines of boilerplate for retries, scheduling and credentials. n8n gives me a visual trace per execution, real Code and Postgres nodes when I need them, and it self-hosts. I still wrote the logic — the normalisation, fingerprinting and scoring are all code, not drag-and-drop.

### 3. How do you handle duplicates?

> Two levels. In-batch, a `Set` of fingerprints dedupes within a run. Across runs, the fingerprint is a `UNIQUE` column and the insert is `ON CONFLICT DO NOTHING`. The fingerprint is sha256 over company, title and location after lowercasing, stripping `Inc`/`Pvt Ltd`/`GmbH` and removing punctuation. The important property is idempotency: replaying the workflow cannot corrupt state, which is also how I'd design an event consumer.

### 4. What happens when a job board changes its response shape?

> The normaliser is shape-detecting and defensive: it checks for Remotive's `jobs`, Arbeitnow's `data`, and RemoteOK's array-or-single-object form, and it drops rows missing a title or company rather than throwing. A schema change degrades one source to zero items; the others still run. The real answer is contract tests — I have a structural lint (`scripts/validate-workflows.mjs`) but not fixture-based tests per source yet, and that's the gap I'd close first.

### 5. Why is scoring deterministic instead of LLM-based?

> Three reasons: reproducibility (same input, same score), debuggability (every score carries its component reasons), and cost (1,200 jobs a month for free). An LLM score also drifts silently when the provider updates the model. I use the LLM only where language generation is the actual task — the cover letter — and there I constrain it hard.

### 6. How do you stop the LLM from making things up?

> The prompt gets a fixed `FACTS` block and an explicit instruction to use nothing outside it, including stating what the candidate *cannot* do. I also ask for limits: 110–150 words, at most three overlapping technologies, one concrete week-one action. And I version the prompt (`prompt_version`) so when quality changes I can attribute it. It's not a guarantee — the honest answer is that the guard is a prompt plus small output, and a real system would add a claim-check pass.

### 7. How do you know the ranking is any good?

> `eval/evaluate.mjs`: I hand-labelled twenty real listings, exported the ranking, and computed precision@5/10/20 with a threshold sweep. Precision@10 was 0.70. That number is in the README, along with the failure modes. Without a labelled set, any ranking claim is vibes.

### 8. What's the failure mode you're least happy about?

> Near-duplicates. Fingerprint dedupe catches re-posts and syndication but not "Senior Backend Engineer" vs "Backend Engineer (Senior)". The fix is embeddings plus a cosine threshold, and a queue-mode worker so the comparison doesn't run inside the request path.

### 9. How does this scale to 100k postings/day?

> The current design is a single n8n instance with an inline Postgres write. At that volume I'd move to queue mode with workers, batch inserts via `COPY` instead of a built `VALUES` list, partition `jobs` by month, and move dedupe to an embedding index. The scoring stays deterministic, which is the cheap part.

### 10. Security?

> Credentials only in n8n's encrypted store, `.env` gitignored, diagnostics off, no personal documents uploaded anywhere — the model sees a text block I authored. I also deliberately avoid scraping sites whose ToS forbids it; that's an engineering constraint with legal consequences, not a moral nicety.

### 11. What would you do differently?

> I'd have started with the eval harness. I built the scoring first and tuned it by feel for a day; once I had labels, the weights changed in an hour. Test-first applies to ranking policies too.

### 12. What did you actually learn?

> That the boring parts are the product: idempotency, failure isolation, and being able to explain a number. The AI part was twenty lines of prompt.
