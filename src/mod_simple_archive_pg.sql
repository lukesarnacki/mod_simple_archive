DROP TABLE sa_messages;

CREATE TABLE sa_messages (
  id SERIAL PRIMARY KEY,
  from_jid text NOT NULL,
  to_jid text NOT NULL,
  body text NOT NULL,
  utc timestamp without time zone NOT NULL
);
