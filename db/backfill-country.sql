-- One-time migration for databases created before the `country` column existed.
-- Safe to re-run: it only touches rows where country IS NULL.

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS country TEXT;
CREATE INDEX IF NOT EXISTS jobs_country_idx ON jobs (country) WHERE country IS NOT NULL;

UPDATE jobs
SET country = CASE
  WHEN location ~* 'germany|deutschland|berlin|munich|münchen|munchen|hamburg|frankfurt|cologne|köln|koln|stuttgart|düsseldorf|dusseldorf|leipzig|dresden' THEN 'de'
  WHEN location ~* 'austria|österreich|osterreich|vienna|wien|graz|linz' THEN 'at'
  WHEN location ~* 'switzerland|schweiz|zurich|zürich|geneva|genf|basel|lausanne' THEN 'ch'
  WHEN location ~* 'netherlands|nederland|amsterdam|rotterdam|utrecht|eindhoven' THEN 'nl'
  WHEN location ~* 'france|paris|lyon|toulouse|nantes|bordeaux|lille' THEN 'fr'
  WHEN location ~* 'spain|españa|espana|madrid|barcelona|valencia|seville' THEN 'es'
  WHEN location ~* 'italy|italia|milan|milano|rome|roma|turin|torino|bologna' THEN 'it'
  WHEN location ~* 'poland|polska|warsaw|warszawa|krakow|kraków|wroclaw|gdańsk|gdansk' THEN 'pl'
  WHEN location ~* 'ireland|dublin|cork|galway' THEN 'ie'
  WHEN location ~* 'united kingdom|great britain|england|scotland|wales|london|manchester|edinburgh|birmingham|leeds|bristol|glasgow' THEN 'gb'
  WHEN location ~* 'sweden|stockholm|gothenburg|malmö|malmo' THEN 'se'
  WHEN location ~* 'denmark|copenhagen|aarhus' THEN 'dk'
  WHEN location ~* 'norway|oslo|bergen' THEN 'no'
  WHEN location ~* 'finland|helsinki|espoo' THEN 'fi'
  WHEN location ~* 'portugal|lisbon|lisboa|porto' THEN 'pt'
  WHEN location ~* 'czech|prague|praha|brno' THEN 'cz'
  WHEN location ~* 'romania|bucharest|cluj' THEN 'ro'
  WHEN location ~* 'canada|toronto|vancouver|montreal|ottawa|calgary' THEN 'ca'
  WHEN location ~* 'united states|usa|u\.s\.|new york|san francisco|seattle|austin|boston|chicago|denver|atlanta' THEN 'us'
  WHEN location ~* 'india|bangalore|bengaluru|hyderabad|pune|chennai|mumbai|delhi|noida|gurgaon|gurugram|ahmedabad|kolkata' THEN 'in'
  WHEN location ~* 'australia|sydney|melbourne|brisbane|perth' THEN 'au'
  WHEN location ~* 'singapore' THEN 'sg'
  WHEN location ~* 'dubai|abu dhabi|uae' THEN 'ae'
  WHEN location ~* 'japan|tokyo|osaka' THEN 'jp'
  WHEN location ~* 'worldwide|anywhere|global' THEN 'remote'
  WHEN location ~* 'remote' THEN 'remote'
  ELSE country
END
WHERE country IS NULL AND location IS NOT NULL;

SELECT country, count(*) FROM jobs GROUP BY 1 ORDER BY 2 DESC;
