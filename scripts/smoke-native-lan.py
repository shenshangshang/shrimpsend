#!/usr/bin/env python3
"""Exercise a running native client's LAN receiver using disposable fixtures."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import time
import subprocess
from urllib.parse import quote, urlsplit
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url', required=True)
parser.add_argument('--download-dir', type=Path, default=Path.home() / 'Downloads')
parser.add_argument('--adb-serial', help='Verify the received file on an attached Android device')
parser.add_argument('--size-mib', type=int, default=4, help='Test file size (2–1024 MiB)')
args = parser.parse_args()
if not 2 <= args.size_mib <= 1024:
    parser.error('--size-mib must be between 2 and 1024')
endpoint = urlsplit(args.url)
if endpoint.scheme != 'http':
    parser.error('Use the native LAN HTTP URL.')

def request(method, path, data=None, headers=None):
    connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=30)
    try:
        connection.request(method, path, data, headers or {})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()

status, info = request('GET', '/device-info')
assert status == 200
device = json.loads(info)['deviceId']
run_id = uuid.uuid4().hex[:12]
text = json.dumps({'text': '离线局域网文字验证 ' + run_id,
                   'fromDeviceId': 'smoke-lan-' + run_id,
                   'fromDeviceName': '本地收发测试', 'toDeviceId': device}).encode()
assert request('POST', '/message', text, {'Content-Type': 'application/json'})[0] == 200

payload = bytes(range(256)) * (args.size_mib * 1024 * 1024 // 256)
name = 'shrimpsend-offline-' + run_id + '.bin'
headers = {'X-File-Name': quote(name), 'X-File-Size': str(len(payload)),
           'X-File-Id': run_id, 'X-Ultrasend-Local-Id': run_id,
           'X-Ultrasend-From-Device-Id': 'smoke-lan-' + run_id,
           'X-Ultrasend-To-Device-Id': device,
           'Content-Type': 'application/octet-stream'}

# Deliberately break a real socket after sending a prefix, then resume it.
connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=30)
connection.putrequest('POST', '/transfer')
for key, value in {**headers, 'Content-Length': str(len(payload))}.items():
    connection.putheader(key, value)
connection.endheaders()
connection.send(payload[:1024 * 1024])
connection.close()
offset = 0
for _ in range(30):
    status, body = request('GET', '/transfer-status?fileId=' + run_id)
    offset = int(body) if status == 200 else 0
    if offset: break
    time.sleep(0.1)
assert 0 < offset < len(payload), ('partial not preserved', offset)
start = time.monotonic()
status, body = request('POST', '/transfer', payload[offset:],
                       {**headers, 'X-Resume-Offset': str(offset)})
assert status == 200, (status, body)
transfer_seconds = time.monotonic() - start
received = args.download_dir / name
if args.adb_serial:
    received_bytes = subprocess.check_output(['adb', '-s', args.adb_serial, 'exec-out', 'cat', str(received)])
else:
    received_bytes = received.read_bytes()
assert hashlib.sha256(received_bytes).digest() == hashlib.sha256(payload).digest()
print(json.dumps({'text': 'accepted', 'resume_offset': offset, 'size': len(payload),
                  'sha256': hashlib.sha256(payload).hexdigest(), 'path': str(received),
                  'transfer_seconds': round(transfer_seconds, 3),
                  'resume_seconds': round(time.monotonic() - start, 3)}, ensure_ascii=False))
