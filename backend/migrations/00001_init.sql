-- +goose Up
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE reports (
    id         BIGSERIAL PRIMARY KEY,
    type       TEXT NOT NULL CHECK (type IN
                 ('police', 'accident', 'jam', 'hazard', 'camera', 'closed')),
    geom       GEOGRAPHY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX reports_geom_idx ON reports USING GIST (geom);
CREATE INDEX reports_created_idx ON reports (created_at DESC);

-- +goose Down
DROP TABLE reports;
