-- +goose Up
-- "Still there?" answers from other drivers. One vote per user per report;
-- voting again replaces the earlier vote. See voteReport and nearbyReports in the API.
CREATE TABLE report_votes (
    report_id  BIGINT      NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    user_id    BIGINT      NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    vote       SMALLINT    NOT NULL CHECK (vote IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (report_id, user_id)
);

-- Joined by report_id for every report in range, on every map refresh.
CREATE INDEX report_votes_report_idx ON report_votes (report_id);

-- +goose Down
DROP TABLE report_votes;
