CREATE TABLE payments (
  id varchar(255) PRIMARY KEY,
  order_id varchar(255) NOT NULL,
  status varchar(50) NOT NULL,
  created_at timestamp NOT NULL DEFAULT now()
);

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
