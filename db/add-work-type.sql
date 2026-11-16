-- One-time migration for databases created before the `work_type` column.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS is a no-op once it is there.
--
-- Generated, like visa_signal and seniority: no backfill, no workflow node,
-- never out of sync with the text it is derived from.
--
--   open_source  the role is at an open-source project / OSS-first company
--                (title says "open source", or the ad talks about building or
--                maintaining open-source software)
--   contract     title says contract / contractor / freelance / fixed-term, or
--                the ad offers a contract role or a freelance engagement
--   standard     everything else

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS work_type TEXT GENERATED ALWAYS AS (
  CASE
    WHEN lower(coalesce(title, '')) ~ 'open.?source'
      OR lower(coalesce(title, '') || ' ' || coalesce(description, ''))
         ~ 'open.?source (project|community|software|ecosystem)|we are (an )?open.?source|our open.?source|open.?source (first|maintainer|contributors?)|contribut\w* to open.?source'
      THEN 'open_source'
    WHEN lower(coalesce(title, '')) ~ '\mcontract\M|contractor|freelance|fixed.?term'
      OR lower(coalesce(description, '')) ~ 'contract (role|position|basis)|fixed.?term contract|freelance (role|contract)'
      THEN 'contract'
    ELSE 'standard'
  END
) STORED;

SELECT work_type, count(*) FROM jobs GROUP BY 1 ORDER BY 2 DESC;
