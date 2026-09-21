-- MySQL 8. Run before upgrading when Hibernate schema updates are disabled.
-- Back up the database first. Do not delete consumed code fingerprints or change
-- DEVICE_LICENSE_SECRET / namespace after issuance. The application performs the
-- one-time legacy grant + pairing import transaction on its first startup.
CREATE TABLE IF NOT EXISTS device_license_grants (
  device_id VARCHAR(255) PRIMARY KEY,
  owner_user_id BIGINT NOT NULL,
  name VARCHAR(128) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  activated_at DATETIME(6) NOT NULL,
  revoked_at DATETIME(6),
  legacy BIT NOT NULL,
  INDEX idx_license_grant_owner (owner_user_id, revoked_at, activated_at)
);
CREATE TABLE IF NOT EXISTS device_license_codes (
  id VARCHAR(36) PRIMARY KEY,
  owner_user_id BIGINT NOT NULL,
  code_hash VARCHAR(64) NOT NULL UNIQUE,
  qr_hash VARCHAR(64) NOT NULL UNIQUE,
  status VARCHAR(16) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  device_id VARCHAR(255),
  device_name VARCHAR(128),
  platform VARCHAR(32),
  redeemed_at DATETIME(6),
  INDEX idx_license_code_owner (owner_user_id, status),
  INDEX idx_license_code_device (device_id, status)
);
CREATE TABLE IF NOT EXISTS device_license_accounts (
  user_id BIGINT PRIMARY KEY,
  legacy_extra_slots INT NOT NULL,
  migrated_at DATETIME(6) NOT NULL
);
CREATE TABLE IF NOT EXISTS device_license_migration (id INT PRIMARY KEY, completed BIT NOT NULL);
CREATE TABLE IF NOT EXISTS license_rate_buckets (
  id VARCHAR(255) PRIMARY KEY,
  window_started_at BIGINT NOT NULL,
  hits INT NOT NULL,
  INDEX idx_license_rate_window (window_started_at)
);
CREATE TABLE IF NOT EXISTS device_license_audit (
  id VARCHAR(36) PRIMARY KEY,
  owner_user_id BIGINT NOT NULL,
  action VARCHAR(32) NOT NULL,
  device_id VARCHAR(255),
  request_id VARCHAR(36),
  created_at DATETIME(6) NOT NULL,
  INDEX idx_license_audit_owner_time (owner_user_id, created_at)
);
