-- 短 TTL 信令 mailbox（生产可用 ddl-auto=update 自动建表；自托管手工升级用此脚本）
CREATE TABLE IF NOT EXISTS signaling_mailbox (
    id             BIGINT       NOT NULL AUTO_INCREMENT,
    user_id        BIGINT       NOT NULL,
    from_device_id VARCHAR(255) DEFAULT NULL,
    to_device_id   VARCHAR(255) DEFAULT NULL,
    type           VARCHAR(64)  NOT NULL,
    data           MEDIUMTEXT   NOT NULL,
    created_at     DATETIME(3)  NOT NULL,
    expires_at     DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_mailbox_user_expires (user_id, expires_at),
    KEY idx_mailbox_user_id (user_id, id),
    CONSTRAINT fk_mailbox_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
