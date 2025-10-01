CREATE SCHEMA IF NOT EXISTS request_tracker;

CREATE TABLE IF NOT EXISTS request_tracker.tickets
(
    id          SERIAL primary key,
    ticket_id   int,
    insert_date timestamp default now()
);

CREATE TABLE IF NOT EXISTS request_tracker.ticket_to_history_map
(
    id          SERIAL primary key,
    history_id  INT,
    ticket_id   INT,
--     subject     text,
    insert_date TIMESTAMP DEfAULT now()
);

CREATE TABLE IF NOT EXISTS request_tracker.ticket_meta
(

    id                  SERIAL primary key,
    ticket_id           INT,
    queue               TEXT,
    owner               TEXT,
    creator             TEXT,
    subject             TEXT,
    status              TEXT,
    priority            INTEGER,
    initial_priority    INTEGER,
    final_priority      INTEGER,
    requestors          TEXT,
    cc                  TEXT,
    admin_cc            TEXT,
    created             TIMESTAMP,
    starts              TEXT,
    started             TIMESTAMP,
    due                 TIMESTAMP,
    resolved            TIMESTAMP,
    told                TIMESTAMP,
    last_updated        TIMESTAMP,
    time_estimated      INTEGER,
    time_worked         INTEGER,
    time_left           INTEGER,
    requesting_entity   TEXT,
    severity_level      TEXT,
    emergency_change    TEXT,
    ebsco_ticket_number TEXT,
    module              TEXT,
    build_ai_summary    BOOLEAN,
    embedding           TEXT
);

CREATE TABLE IF NOT EXISTS request_tracker.ticket_content
(
    id          SERIAL primary key,
    history_id  INTEGER,
    ticket_id   INTEGER,
    description TEXT,
    content     TEXT,
    creator     VARCHAR(255),
    created     TIMESTAMP
);

CREATE TABLE IF NOT EXISTS request_tracker.ticket_summary
(
    id                           SERIAL primary key,
    ticket_id                    INT,
    model_used                   TEXT,
    requesting_entity            VARCHAR(255),
    queue                        VARCHAR(100),
    status                       VARCHAR(100),
    title                        VARCHAR(255),
    summary                      TEXT,
    summary_long                 TEXT,
    contextual_details           TEXT,
    contextual_technical_details TEXT,
    keywords                     TEXT,
    ticket_as_question           TEXT,
    category                     TEXT,
    key_points_discussed         TEXT,
    data_patterns_or_trends      TEXT,
    customer_sentiment           TEXT,
    customer_sentiment_score     INT,
    -- We just store this data to be shipped off to elastic search.
    -- So it's just TEXT field to maintain accuracy.
    -- REAL[] or DOUBLE PRECISION[] could potentially round the numbers
    embedding                    TEXT
);

-- Add to schema.sql
CREATE TABLE IF NOT EXISTS request_tracker.scan_history
(
    id                SERIAL PRIMARY KEY,
    scan_type         VARCHAR(50) NOT NULL, -- 'full', 'incremental', etc.
    scan_start_time   TIMESTAMP   NOT NULL,
    scan_end_time     TIMESTAMP,
    tickets_processed INTEGER
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ticket_content_history_id ON request_tracker.ticket_content (history_id);
CREATE INDEX IF NOT EXISTS idx_ticket_content_ticket_id ON request_tracker.ticket_content (ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_meta_ticket_id ON request_tracker.ticket_meta (ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_summary_ticket_id ON request_tracker.ticket_summary (ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_to_history_map_history_id ON request_tracker.ticket_to_history_map (history_id);
CREATE INDEX IF NOT EXISTS idx_ticket_to_history_map_ticket_id ON request_tracker.ticket_to_history_map (ticket_id);
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_id ON request_tracker.tickets (ticket_id);
