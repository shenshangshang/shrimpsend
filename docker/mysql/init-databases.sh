#!/bin/bash
# First-boot grants for the Compose MySQL volume.
# MYSQL_DATABASE (ultrasend) is created by the official image.
set -euo pipefail
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
CREATE DATABASE IF NOT EXISTS ultrasend CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ultrasend_overseas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON ultrasend.* TO '${MYSQL_USER}'@'%';
GRANT ALL PRIVILEGES ON ultrasend_overseas.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
