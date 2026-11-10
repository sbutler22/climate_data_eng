-- Schema: creates every table, key, and constraint from scratch.
--
-- What goes here: one CREATE TABLE per table, in an order that works (referenced tables
-- first), each with a comment giving its row unit. Running this file on an empty team
-- schema must succeed. Replace the example with your own tables.
--
-- Run it as your team, so the tables belong to the team and survive the handoff:
--   SET ROLE dasher_write;
--   SET search_path = dasher, course, public;

-- Example: the shared course tables, as a team would write them.

SET ROLE dasher_write;

SET search_path = dasher, course, public;

-- Row unit: one weather station.
CREATE TABLE stations (
  station_id TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  state      CHAR(2) CHECK (state ~ '^[A-Z]{2}$'),
  lat        DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lon        DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
  elevation  NUMERIC(7, 2)                       -- meters
);

-- Row unit: one station on one date.
CREATE TABLE observations (
  obs_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  station_id TEXT NOT NULL REFERENCES stations (station_id),
  date       DATE NOT NULL,
  tmax       NUMERIC,                            -- degrees C
  tmin       NUMERIC,                            -- degrees C
  precip     NUMERIC CHECK (precip >= 0),        -- millimeters
  CHECK (tmax IS NULL OR tmin IS NULL OR tmax >= tmin),
  UNIQUE (station_id, date)
);

-- Row unit: one run of src/refresh.py.
CREATE TABLE ingestion_runs (
  run_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  source        TEXT NOT NULL,
  rows_staged   INTEGER NOT NULL,
  rows_inserted INTEGER NOT NULL,
  rows_updated  INTEGER NOT NULL
);


-- Flood-damage tables: Storm Events plus three helper tables 

-- Row unit: one U.S. state or the District of Columbia.
CREATE TABLE state (
  state_fips CHAR(2) PRIMARY KEY CHECK (state_fips ~ '^[0-9]{2}$'),
  state_abbr CHAR(2) NOT NULL UNIQUE CHECK (state_abbr ~ '^[A-Z]{2}$'),
  state_name TEXT NOT NULL
);

-- Row unit: one NOAA Storm Events event-type name.
-- hazard_group is our own label; a type nobody has classified yet stays 'unmapped'.
CREATE TABLE event_type (
  event_type   TEXT PRIMARY KEY,
  hazard_group TEXT NOT NULL DEFAULT 'unmapped'
    CHECK (hazard_group IN ('flood', 'hail', 'wind', 'tornado', 'tropical', 'winter',
                            'heat_cold', 'fire', 'marine', 'other', 'unmapped'))
);

-- Row unit: one calendar year. BLS CPI-U, all items, U.S. city average,
-- annual average, 1982-84 = 100. Joined to storm_event on begin_year (no foreign key:
-- a new year's events arrive before that year's annual average exists).x
CREATE TABLE cpi_annual (
  year  INTEGER PRIMARY KEY CHECK (year BETWEEN 1990 AND 2100),
  cpi_u NUMERIC(8, 3) NOT NULL CHECK (cpi_u > 0)
);

-- Row unit: one NOAA Storm Events record: one event type in one county or forecast zone.
-- episode_id groups the events of one storm episode.
CREATE TABLE storm_event (
  event_id            BIGINT PRIMARY KEY,
  episode_id          BIGINT NOT NULL,
  state_fips          CHAR(2) NOT NULL REFERENCES state (state_fips),
  event_type          TEXT NOT NULL REFERENCES event_type (event_type),
  begin_date          DATE NOT NULL CHECK (begin_date >= DATE '1996-01-01'),  -- all event types recorded from 1996
  begin_year          INTEGER GENERATED ALWAYS AS (EXTRACT(YEAR FROM begin_date)::INTEGER) STORED,
  damage_property_usd NUMERIC CHECK (damage_property_usd >= 0),              -- dollars as recorded; NULL if blank
  ingestion_run_id    BIGINT REFERENCES ingestion_runs (run_id)
);

-- Starting point for the flood query (state, year, flood types). Check with EXPLAIN once loaded.
-- basically this allows queries about flood to avoid looking through every event, and focusing only
-- on floods (or other storm events), given state and year.
CREATE INDEX storm_event_type_state_year_ix ON storm_event (event_type, state_fips, begin_year);

-- Seed: 50 states and DC. Check against SELECT DISTINCT state_fips, state from the first load.
INSERT INTO state (state_fips, state_abbr, state_name) VALUES
  ('01', 'AL', 'Alabama'),        ('02', 'AK', 'Alaska'),         ('04', 'AZ', 'Arizona'),
  ('05', 'AR', 'Arkansas'),       ('06', 'CA', 'California'),     ('08', 'CO', 'Colorado'),
  ('09', 'CT', 'Connecticut'),    ('10', 'DE', 'Delaware'),       ('11', 'DC', 'District of Columbia'),
  ('12', 'FL', 'Florida'),        ('13', 'GA', 'Georgia'),        ('15', 'HI', 'Hawaii'),
  ('16', 'ID', 'Idaho'),          ('17', 'IL', 'Illinois'),       ('18', 'IN', 'Indiana'),
  ('19', 'IA', 'Iowa'),           ('20', 'KS', 'Kansas'),         ('21', 'KY', 'Kentucky'),
  ('22', 'LA', 'Louisiana'),      ('23', 'ME', 'Maine'),          ('24', 'MD', 'Maryland'),
  ('25', 'MA', 'Massachusetts'),  ('26', 'MI', 'Michigan'),       ('27', 'MN', 'Minnesota'),
  ('28', 'MS', 'Mississippi'),    ('29', 'MO', 'Missouri'),       ('30', 'MT', 'Montana'),
  ('31', 'NE', 'Nebraska'),       ('32', 'NV', 'Nevada'),         ('33', 'NH', 'New Hampshire'),
  ('34', 'NJ', 'New Jersey'),     ('35', 'NM', 'New Mexico'),     ('36', 'NY', 'New York'),
  ('37', 'NC', 'North Carolina'), ('38', 'ND', 'North Dakota'),   ('39', 'OH', 'Ohio'),
  ('40', 'OK', 'Oklahoma'),       ('41', 'OR', 'Oregon'),         ('42', 'PA', 'Pennsylvania'),
  ('44', 'RI', 'Rhode Island'),   ('45', 'SC', 'South Carolina'), ('46', 'SD', 'South Dakota'),
  ('47', 'TN', 'Tennessee'),      ('48', 'TX', 'Texas'),          ('49', 'UT', 'Utah'),
  ('50', 'VT', 'Vermont'),        ('51', 'VA', 'Virginia'),       ('53', 'WA', 'Washington'),
  ('54', 'WV', 'West Virginia'),  ('55', 'WI', 'Wisconsin'),      ('56', 'WY', 'Wyoming')
ON CONFLICT DO NOTHING;


-- adding the billion $ storm events table
-- i think this along with sam's above created tables are sufficient for the third question
-- Row unit: one NOAA billion-dollar disaster.
CREATE TABLE billion_dollar_disasters (
  disaster_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  disaster_name TEXT NOT NULL, -- I imagine a bil-$ disaster will be named
  disaster_type TEXT NOT NULL,
  begin_date DATE NOT NULL CHECK (begin_date >= DATE '1996-01-01'),  -- all event types recorded from 1996
  end_date DATE, 
  begin_year INTEGER GENERATED ALWAYS AS (EXTRACT(YEAR FROM begin_date)::INTEGER) STORED,
  decade INTEGER GENERATED ALWAYS AS ((EXTRACT(YEAR FROM begin_date)::INTEGER / 10) * 10) STORED,
  estimated_damage_usd NUMERIC CHECK (estimated_damage_usd >= 0),
  states_impacted TEXT NOT NULL, 
  ingestion_run_id BIGINT REFERENCES ingestion_runs (run_id)
);

-- group by decade
CREATE INDEX billion_dollar_disaster_decade on billion_dollar_disasters(decade)



-- CHECKS THAT EVERYTHING ABOVE WORKED

-- 1. Which tables exist (expect cpi_annual, event_type, ingestion_runs, state, storm_event,
--    plus stations and observations if you haven't dropped the example yet)
-- SELECT tablename FROM pg_tables WHERE schemaname = 'dasher' ORDER BY 1;

-- 2. The seed rows (expect 51)
-- SELECT count(*) FROM state;

-- 3. Columns of storm_event (begin_year should show is_generated = ALWAYS)
-- SELECT column_name, data_type, is_nullable, is_generated
-- FROM information_schema.columns
-- WHERE table_schema = 'dasher' AND table_name = 'storm_event'
-- ORDER BY ordinal_position;

-- 4. Every key and constraint you just created, in readable form
-- SELECT conrelid::regclass AS tbl, conname, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE connamespace = 'dasher'::regnamespace
-- ORDER BY 1, 2;
