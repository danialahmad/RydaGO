-- +goose Up
-- Live trip sharing: a driver shares a link; the app keeps the position and ETA fresh.
CREATE TABLE shares (
    token      TEXT             PRIMARY KEY,           -- unguessable, goes in the public link
    user_id    BIGINT           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dest_name  TEXT             NOT NULL,
    dest_lat   DOUBLE PRECISION NOT NULL,
    dest_lng   DOUBLE PRECISION NOT NULL,
    lat        DOUBLE PRECISION NOT NULL,
    lng        DOUBLE PRECISION NOT NULL,
    eta_at     TIMESTAMPTZ      NOT NULL,
    created_at TIMESTAMPTZ      NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ      NOT NULL DEFAULT now(),
    ended_at   TIMESTAMPTZ
);

CREATE INDEX shares_user_idx ON shares (user_id);

-- +goose Down
DROP TABLE shares;
