#!/usr/bin/env python3
"""Seed an isolated local-only QA purchaser; never talks to external payment/email services."""
import json, os, pathlib, secrets, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
out = root / '.local' / 'license-qa.json'
out.parent.mkdir(exist_ok=True)
if out.exists():
    fixture = json.loads(out.read_text())
else:
    fixture = {'email': 'device-license-qa@local.invalid', 'password': secrets.token_urlsafe(24)}
    out.write_text(json.dumps(fixture, indent=2) + '\n')
    out.chmod(0o600)
# Context and container deliberately fixed. No host, database or account override.
docker = ['docker', '--context', 'colima-shrimpsend', 'exec', '-i', 'shrimpsend-local-mysql-1']
backup = root / '.local' / 'backups' / 'before-device-license.sql'
backup.parent.mkdir(exist_ok=True)
if not backup.exists():
    with backup.open('wb') as f:
        subprocess.run(docker + ['sh', '-c', 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction "$MYSQL_DATABASE"'], stdout=f, check=True)
    backup.chmod(0o600)
pw_hash = subprocess.check_output(['htpasswd', '-niBC', '10', 'qa'], input=(fixture['password']+'\n').encode()).decode().strip().split(':', 1)[1]
# Generated identifiers/password hash have a constrained alphabet; no user SQL interpolation.
assert fixture['email'] == 'device-license-qa@local.invalid'
assert all(c.isalnum() or c in '$./' for c in pw_hash)
sql = f"""
INSERT INTO users (email, username, password_hash) VALUES ('device-license-qa@local.invalid', 'Local license QA', '{pw_hash}')
ON DUPLICATE KEY UPDATE password_hash=VALUES(password_hash);
SET @qa_owner=(SELECT id FROM users WHERE email='device-license-qa@local.invalid');
INSERT INTO membership_entitlements (user_id,tier_code,device_limit,addon_packs,is_lifetime,effective_at,updated_at,payment_channel)
VALUES (@qa_owner,'PRO',3,0,1,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),'ALIPAY_LIFETIME')
ON DUPLICATE KEY UPDATE tier_code='PRO',device_limit=3,is_lifetime=1,updated_at=UTC_TIMESTAMP(6);
"""
subprocess.run(docker + ['sh', '-c', 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot "$MYSQL_DATABASE"'], input=sql.encode(), check=True)
print(f'Local QA purchaser ready. Credentials: {out}')
print(f'Backup: {backup}')
