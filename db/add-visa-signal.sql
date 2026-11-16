-- One-time migration for databases created before the `visa_signal` column.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS is a no-op once it is there.
--
-- The column is GENERATED, so it needs no workflow change and no backfill:
-- PostgreSQL recomputes it from title + description on every insert or update.
--
--   no_sponsor  the ad explicitly refuses sponsorship / demands a pre-existing
--               right to work  -> excluded from the digest
--   sponsor     the ad explicitly offers visa sponsorship
--   relocation  the ad offers relocation support (money, help, package)
--   unknown     the ad says nothing (the common case: ~98% of postings)

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS visa_signal TEXT GENERATED ALWAYS AS (
  CASE
    WHEN lower(coalesce(title, '') || ' ' || coalesce(description, ''))
      ~ 'no (visa )?sponsorship|unable to sponsor|not able to sponsor|cannot sponsor|can not sponsor|will not sponsor|does not sponsor|do not sponsor|not sponsor|without sponsorship|sponsorship is not available|no c2c|must (be|already) (authorized|eligible) to work|right to work in|must have the right to work|authorized to work in'
      THEN 'no_sponsor'
    WHEN lower(coalesce(title, '') || ' ' || coalesce(description, ''))
      ~ 'visa sponsorship|sponsorship available|sponsorship provided|sponsorship offered|visa sponsored|we (do )?sponsor|willing to sponsor|able to sponsor|can sponsor|blue card|skilled worker visa|work permit'
      THEN 'sponsor'
    WHEN lower(coalesce(title, '') || ' ' || coalesce(description, ''))
      ~ 'relocation (support|package|assistance|bonus|help|allowance)|we support relocation|relocation offered|relocation is (available|provided)'
      THEN 'relocation'
    ELSE 'unknown'
  END
) STORED;

SELECT visa_signal, count(*) FROM jobs GROUP BY 1 ORDER BY 2 DESC;
