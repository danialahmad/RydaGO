-- +goose Up
CREATE TABLE users (
    id            BIGSERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE reports ADD COLUMN user_id BIGINT REFERENCES users(id);

-- +goose Down
ALTER TABLE reports DROP COLUMN user_id;
DROP TABLE users;
