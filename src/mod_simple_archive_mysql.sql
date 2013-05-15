CREATE TABLE sa_messages (
  from_jid text NOT NULL,
  to_jid text NOT NULL,
  body text NOT NULL,
  utc timestamp NOT NULL
);
