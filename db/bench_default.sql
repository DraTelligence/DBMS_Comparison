\pset pager off
\pset tuples_only on
\pset format unaligned
\pset footer off
\timing on
SET client_min_messages TO warning;

-- 内存
\echo === WORK_MEM (_DEFAULT_) ===
SELECT current_setting('work_mem');

-- 数据量
\echo === DATASET_SIZE (yellow_trips) ===
SELECT COUNT(*) FROM yellow_trips;

-- Q1：
\echo === Q1: hourly agg (pc>=2 & 2019-07) ===
SELECT COUNT(*) FROM (
  SELECT date_trunc('hour', tpep_pickup_datetime) AS hr
  FROM yellow_trips
  WHERE passenger_count >= 2
    AND tpep_pickup_datetime >= '2019-07-01'
    AND tpep_pickup_datetime <  '2019-08-01'
  GROUP BY 1
) AS q1;

-- Q2：Top-100
\echo === Q2: top-100 by trip_distance DESC ===
SELECT COUNT(*) FROM (
  SELECT tpep_pickup_datetime, trip_distance, total_amount
  FROM yellow_trips
  ORDER BY trip_distance DESC
  LIMIT 100
) AS q2;

-- Q3：分组后的前 20 行数
\echo === Q3: pulocationid agg where 1.0<=distance<=3.0 ===
SELECT COUNT(*) FROM (
  SELECT pulocationid, COUNT(*) AS c
  FROM yellow_trips
  WHERE trip_distance BETWEEN 1.0 AND 3.0
  GROUP BY pulocationid
  ORDER BY c DESC
  LIMIT 20
) AS q3;

-- U1：小范围（索引驱动）
\echo === U1: small-range UPDATE (uses time index) ===
\echo TARGET_ROWS:
SELECT COUNT(*) FROM yellow_trips
WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11'
  AND passenger_count >= 2 AND tip_amount < 20;

BEGIN;
UPDATE yellow_trips
   SET tip_amount = ROUND(COALESCE(tip_amount,0.00)+0.01,2)
 WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11'
   AND passenger_count >= 2 AND tip_amount < 20;
ROLLBACK;

-- U2：中范围（全扫过滤）
\echo === U2: medium-range UPDATE (full scan filter) ===
\echo TARGET_ROWS:
SELECT COUNT(*) FROM yellow_trips WHERE trip_distance BETWEEN 1.0 AND 3.0;

BEGIN;
UPDATE yellow_trips
   SET total_amount = ROUND(COALESCE(total_amount,0.00)+0.01,2)
 WHERE trip_distance BETWEEN 1.0 AND 3.0;
ROLLBACK;

-- U3：大范围
\echo === U3: sandboxed full-table-like UPDATE (commit then drop) ===
DROP TABLE IF EXISTS yellow_trips_u3_sandbox;
CREATE TABLE yellow_trips_u3_sandbox AS
SELECT * FROM yellow_trips
WHERE tpep_pickup_datetime >= '2019-07-10' AND tpep_pickup_datetime < '2019-07-11';

\echo SANDBOX_ROWS:
SELECT COUNT(*) FROM yellow_trips_u3_sandbox;

BEGIN;
UPDATE yellow_trips_u3_sandbox
   SET improvement_surcharge = ROUND(COALESCE(improvement_surcharge,0.00)+0.01,2);
COMMIT;

DROP TABLE yellow_trips_u3_sandbox;
