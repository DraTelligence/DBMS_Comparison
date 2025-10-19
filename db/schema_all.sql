-- schema_all.sql — 19 columns aligned with NYC Yellow 2019-07 CSV
DROP TABLE IF EXISTS yellow_trips;

CREATE TABLE yellow_trips(
  vendorid                int,
  tpep_pickup_datetime    timestamp,
  tpep_dropoff_datetime   timestamp,
  passenger_count         int,
  trip_distance           numeric(10,3),
  ratecodeid              int,
  store_and_fwd_flag      char(1),
  pulocationid            int,
  dolocationid            int,
  payment_type            int,
  fare_amount             numeric(10,2),
  extra                   numeric(10,2),
  mta_tax                 numeric(10,2),
  tip_amount              numeric(10,2),
  tolls_amount            numeric(10,2),
  improvement_surcharge   numeric(10,2),
  total_amount            numeric(10,2),
  congestion_surcharge    numeric(10,2),
  airport_fee             numeric(10,2)
);

CREATE INDEX IF NOT EXISTS idx_pickup_time ON yellow_trips (tpep_pickup_datetime);
CREATE INDEX IF NOT EXISTS idx_pulocation  ON yellow_trips (pulocationid);