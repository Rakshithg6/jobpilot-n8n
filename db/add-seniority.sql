-- One-time migration for databases created before the `seniority` column.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS is a no-op once it is there.
--
-- Title-only and GENERATED, for the same reason as visa_signal: no backfill,
-- no extra workflow node, and it can never drift from the row it describes.
--
--   intern   intern / internship / trainee / working student / apprentice
--   junior   junior / jr / entry level / graduate / fresher
--   senior   senior / sr / lead / staff / principal / architect / head / manager
--   mid      everything else

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS seniority TEXT GENERATED ALWAYS AS (
  CASE
    WHEN lower(coalesce(title, ''))
      ~ '\m(intern|internship|trainee|working student|werkstudent|apprentice)\M' THEN 'intern'
    WHEN lower(coalesce(title, ''))
      ~ '\m(junior|jr|entry level|entry-level|graduate|grad|fresher)\M' THEN 'junior'
    WHEN lower(coalesce(title, ''))
      ~ '\m(senior|sr|lead|staff|principal|architect|head|manager|director|vp|chief)\M' THEN 'senior'
    ELSE 'mid'
  END
) STORED;

SELECT seniority, count(*) FROM jobs GROUP BY 1 ORDER BY 2 DESC;
