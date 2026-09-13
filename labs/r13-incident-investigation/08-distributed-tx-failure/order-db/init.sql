CREATE TABLE orders (
  id varchar(255) PRIMARY KEY,
  status varchar(50) NOT NULL,
  fail_payment boolean NOT NULL DEFAULT false,
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now()
);

-- Debezium's documented default outbox-table schema (real, standard pattern,
-- not invented here - https://debezium.io/documentation/reference/transformations/outbox-event-router.html)
CREATE TABLE outbox (
  id uuid PRIMARY KEY,
  aggregatetype varchar(255) NOT NULL,
  aggregateid varchar(255) NOT NULL,
  type varchar(255) NOT NULL,
  payload jsonb,
  createdat timestamp NOT NULL DEFAULT now()
);

CREATE TABLE processed_events (
  event_id uuid PRIMARY KEY,
  processed_at timestamp NOT NULL DEFAULT now()
);
