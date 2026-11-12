-- JobPilot schema. Idempotent: safe to re-run against an existing database.
-- Applied automatically on first `docker compose up` via initdb.

CREATE TABLE IF NOT EXISTS jobs (
  id              BIGSERIAL PRIMARY KEY,
  source          TEXT        NOT NULL,
  external_id     TEXT        NOT NULL,
  title           TEXT        NOT NULL,
  company         TEXT        NOT NULL,
  location        TEXT,
  url             TEXT,
  description     TEXT,
  salary_text     TEXT,
  tags            JSONB       NOT NULL DEFAULT '[]'::jsonb,
  -- sha256(company|title|location), normalised. This is the dedupe key:
  -- the same role re-posted tomorrow or syndicated to another board collapses
  -- onto one row instead of flooding the pipeline.
  fingerprint     TEXT        NOT NULL,
  score           INTEGER,
  score_reasons   JSONB,
  matched_keywords JSONB,
  missing_keywords JSONB,
  status          TEXT        NOT NULL DEFAULT 'new',
  cover_letter    TEXT,
  posted_at       TIMESTAMPTZ,
  first_seen      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT jobs_fingerprint_key UNIQUE (fingerprint),
  CONSTRAINT jobs_status_check CHECK (status IN ('new','shortlisted','applied','interview','rejected','skipped'))
);

CREATE INDEX IF NOT EXISTS jobs_rank_idx     ON jobs (score DESC NULLS LAST, first_seen DESC);
CREATE INDEX IF NOT EXISTS jobs_unscored_idx ON jobs (first_seen DESC) WHERE score IS NULL;
CREATE INDEX IF NOT EXISTS jobs_status_idx   ON jobs (status);
CREATE INDEX IF NOT EXISTS jobs_title_trgm   ON jobs USING gin (to_tsvector('english', title || ' ' || company));

-- Every digest we render, kept so the pipeline is auditable after the fact.
CREATE TABLE IF NOT EXISTS digests (
  id           BIGSERIAL PRIMARY KEY,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  job_count    INTEGER     NOT NULL,
  html         TEXT        NOT NULL,
  delivered_via TEXT       NOT NULL DEFAULT 'none'
);

-- Manual + automatic bookkeeping. WF4 writes here; you can also just use SQL.
CREATE TABLE IF NOT EXISTS applications (
  id          BIGSERIAL PRIMARY KEY,
  job_id      BIGINT REFERENCES jobs(id) ON DELETE CASCADE,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  channel     TEXT,
  outcome     TEXT NOT NULL DEFAULT 'pending',
  follow_up_on DATE,
  notes       TEXT,
  CONSTRAINT applications_outcome_check CHECK (outcome IN ('pending','screening','interview','offer','rejected','ghosted'))
);

CREATE INDEX IF NOT EXISTS applications_followup_idx ON applications (follow_up_on)
  WHERE outcome IN ('pending','screening');

-- Failure log. WF5 appends here so errors survive the execution log rotation.
CREATE TABLE IF NOT EXISTS incidents (
  id          BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  workflow    TEXT,
  message     TEXT,
  execution_url TEXT
);

-- One row per day: the funnel that goes on your resume.
CREATE OR REPLACE VIEW v_funnel AS
SELECT
  date_trunc('day', first_seen)::date          AS day,
  count(*)                                     AS jobs_seen,
  count(*) FILTER (WHERE score >= 70)          AS shortlisted,
  count(*) FILTER (WHERE status = 'applied')   AS applied,
  count(*) FILTER (WHERE status = 'interview') AS interviews
FROM jobs
GROUP BY 1
ORDER BY 1 DESC;

-- Precision-friendly export for eval/evaluate.mjs
CREATE OR REPLACE VIEW v_ranked AS
SELECT rank() OVER (ORDER BY score DESC, first_seen DESC) AS position,
       id, score, title, company, location, url, fingerprint
FROM jobs
WHERE score IS NOT NULL;
