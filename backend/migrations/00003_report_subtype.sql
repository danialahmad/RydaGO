-- +goose Up
-- Optional detail for a report, like "hidden" for police or "standstill" for traffic.
-- NULL means the reporter gave no detail. Allowed values live in main.go (reportSubtypes).
ALTER TABLE reports ADD COLUMN subtype TEXT;

-- +goose Down
ALTER TABLE reports DROP COLUMN subtype;
