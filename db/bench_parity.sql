\pset pager off
\pset tuples_only on
\pset format unaligned
\pset footer off
\timing on
SET client_min_messages TO warning;

\echo === WORK_MEM (_DEFAULT_) ===
SELECT current_setting('work_mem');

\echo === DATASET_SIZE (yellow_trips) ===
SELECT COUNT(*) FROM yellow_trips;

\echo === Q1 (wm=:wm) ===
BEGIN; SET LOCAL work_mem = :'wm';
SELECT COUNT(*) FROM (
  SELECT date_trunc('hour', tpep_pickup_datetime) AS hr
  FROM yellow_trips
  WHERE passenger_count >= 2
    AND tpep_pickup_datetime >= '2019-07-01'
    AND tpep_pickup_datetime <  '2019-08-01'
  GROUP BY 1
) AS q1;
COMMIT;

\echo === Q2 (wm=:wm) ===
BEGIN; SET LOCAL work_mem = :'wm';
SELECT COUNT(*) FROM (
  SELECT tpep_pickup_datetime, trip_distance, total_amount
  FROM yellow_trips
  ORDER BY trip_distance DESC
  LIMIT 100
) AS q2;
COMMIT;

\echo === Q3 (wm=:wm) ===
BEGIN; SET LOCAL work_mem = :'wm';
SELECT COUNT(*) FROM (
  SELECT pulocationid, COUNT(*) AS c
  FROM yellow_trips
  WHERE trip_distance BETWEEN 1.0 AND 3.0
  GROUP BY pulocationid
  ORDER BY c DESC
  LIMIT 20
) AS q3;
COMMIT;

\echo === U1 (wm=:wm, small-range, ROLLBACK) ===
\echo TARGET_ROWS:
SELECT COUNT(*) FROM yellow_trips
WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11'
  AND passenger_count >= 2 AND tip_amount < 20;

BEGIN; SET LOCAL work_mem = :'wm';
UPDATE yellow_trips
   SET tip_amount = ROUND(COALESCE(tip_amount,0.00)+0.01,2)
 WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11'
   AND passenger_count >= 2 AND tip_amount < 20;
ROLLBACK;

\echo === U2 (wm=:wm, medium-range, ROLLBACK) ===
\echo TARGET_ROWS:
SELECT COUNT(*) FROM yellow_trips WHERE trip_distance BETWEEN 1.0 AND 3.0;

BEGIN; SET LOCAL work_mem = :'wm';
UPDATE yellow_trips
   SET total_amount = ROUND(COALESCE(total_amount,0.00)+0.01,2)
 WHERE trip_distance BETWEEN 1.0 AND 3.0;
ROLLBACK;

\echo === U3 (wm=:wm, sandbox commit) ===
DROP TABLE IF EXISTS yellow_trips_u3_sandbox;
CREATE TABLE yellow_trips_u3_sandbox AS
SELECT * FROM yellow_trips
WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11';

\echo SANDBOX_ROWS:
SELECT COUNT(*) FROM yellow_trips_u3_sandbox;

BEGIN; SET LOCAL work_mem = :'wm';
UPDATE yellow_trips_u3_sandbox
   SET improvement_surcharge = ROUND(COALESCE(improvement_surcharge,0.00)+0.01,2);
COMMIT;

DROP TABLE yellow_trips_u3_sandbox;
