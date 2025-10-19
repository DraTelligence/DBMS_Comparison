\pset pager off
\pset tuples_only on
\pset format unaligned
\pset footer off
\timing off
SET client_min_messages TO warning;

\echo === WORK_MEM (DEFAULT) ===
SELECT current_setting('work_mem');

-- Q1
\echo === PLAN Q1: hourly agg (DEFAULT) ===
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT date_trunc('hour', tpep_pickup_datetime) AS hr, COUNT(*)
FROM yellow_trips
WHERE passenger_count >= 2
  AND tpep_pickup_datetime >= '2019-07-01'
  AND tpep_pickup_datetime <  '2019-08-01'
GROUP BY 1 ORDER BY 1;

-- Q2
\echo === PLAN Q2: top-100 by trip_distance DESC (DEFAULT) ===
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT tpep_pickup_datetime, trip_distance, total_amount
FROM yellow_trips
ORDER BY trip_distance DESC
LIMIT 100;

-- Q3
\echo === PLAN Q3: pulocationid agg where 1.0<=distance<=3.0 (DEFAULT) ===
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT pulocationid, COUNT(*)
FROM yellow_trips
WHERE trip_distance BETWEEN 1.0 AND 3.0
GROUP BY pulocationid
ORDER BY COUNT(*) DESC
LIMIT 20;

-- U1：小范围 UPDATE
\echo === PLAN U1: UPDATE small-range (ANALYZE, ROLLBACK, DEFAULT) ===
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, TIMING)
UPDATE yellow_trips
   SET tip_amount = ROUND(COALESCE(tip_amount,0.00)+0.01,2)
 WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11'
   AND passenger_count >= 2 AND tip_amount < 20;
ROLLBACK;

-- U2：中等范围 UPDATE
\echo === PLAN U2: UPDATE medium-range (ANALYZE, ROLLBACK, DEFAULT) ===
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, TIMING)
UPDATE yellow_trips
   SET total_amount = ROUND(COALESCE(total_amount,0.00)+0.01,2)
 WHERE trip_distance BETWEEN 1.0 AND 3.0;
ROLLBACK;

-- U3：主表看形态 沙箱表做 ANALYZE
\echo === PLAN U3-main: UPDATE whole-table shape (NO-ANALYZE, DEFAULT) ===
EXPLAIN (BUFFERS)
UPDATE yellow_trips
   SET improvement_surcharge = ROUND(COALESCE(improvement_surcharge,0.00)+0.01,2);

\echo === PLAN U3-sandbox: UPDATE sandbox slice (ANALYZE, DEFAULT) ===
DROP TABLE IF EXISTS yellow_trips_u3_sandbox;
CREATE TABLE yellow_trips_u3_sandbox AS
SELECT * FROM yellow_trips
WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11';

\echo SANDBOX_ROWS:
SELECT COUNT(*) FROM yellow_trips_u3_sandbox;

EXPLAIN (ANALYZE, BUFFERS, TIMING)
UPDATE yellow_trips_u3_sandbox
   SET improvement_surcharge = ROUND(COALESCE(improvement_surcharge,0.00)+0.01,2);

DROP TABLE yellow_trips_u3_sandbox;
