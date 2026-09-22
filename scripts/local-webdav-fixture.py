#!/usr/bin/env python3
"""Local-only disposable WebDAV fixture for UI and direct-client smoke tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit, quote
from html import escape
import os, shutil, time

ROOT = Path(__file__).resolve().parents[1] / '.local' / 'webdav-fixture'
ROOT.mkdir(parents=True, exist_ok=True)
(ROOT / '快速开始.txt').write_text('虾传 WebDAV 本地联调文件\n文件由存储服务直接读取。\n', encoding='utf-8')
(ROOT / '资料').mkdir(exist_ok=True)
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass
    def target(self):
        path = unquote(urlsplit(self.path).path)
        if not path.startswith('/dav/'): raise ValueError()
        target = (ROOT / path[5:]).resolve()
        if not target.is_relative_to(ROOT): raise ValueError()
        return target
    def response(self, code, body=b'', content_type='text/plain; charset=utf-8'):
        self.send_response(code)
        self.send_header('Access-Control-Allow-Origin', self.headers.get('Origin', '*'))
        self.send_header('Access-Control-Allow-Methods','GET, HEAD, PUT, DELETE, PROPFIND, MKCOL, MOVE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Authorization, Content-Type, Depth, Destination, Overwrite, If-None-Match, Range')
        self.send_header('Access-Control-Allow-Private-Network','true')
        self.send_header('Content-Type', content_type); self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD': self.wfile.write(body)
    def do_OPTIONS(self): self.response(204)
    def do_PROPFIND(self):
        try:
            target = self.target()
            if not target.exists(): return self.response(404)
            paths = [target] + (list(target.iterdir()) if target.is_dir() and self.headers.get('Depth') != '0' else [])
            rows=[]
            for path in paths:
                uri='/dav/'+quote(str(path.relative_to(ROOT)))
                if path==ROOT: uri='/dav/'
                elif path.is_dir(): uri+='/'
                rows.append(f'<d:response><d:href>{escape(uri)}</d:href><d:propstat><d:prop><d:displayname>{escape(path.name)}</d:displayname><d:resourcetype>{"<d:collection/>" if path.is_dir() else ""}</d:resourcetype><d:getcontentlength>{0 if path.is_dir() else path.stat().st_size}</d:getcontentlength><d:getlastmodified>Mon, 21 Sep 2026 03:00:00 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>')
            self.response(207, ('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'+''.join(rows)+'</d:multistatus>').encode(), 'application/xml')
        except (ValueError,OSError): self.response(400)
    def do_GET(self):
        try:
            path=self.target()
            import mimetypes
            self.response(200,path.read_bytes(),mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
        except (ValueError,OSError): self.response(404)
    do_HEAD=do_GET
    def do_PUT(self):
        try:
            path=self.target()
            if self.headers.get('If-None-Match')=='*' and path.exists(): return self.response(412)
            data=self.rfile.read(int(self.headers.get('Content-Length','0')))
            path.write_bytes(data);self.response(201)
        except (ValueError,OSError): self.response(400)
    def do_MKCOL(self):
        try: self.target().mkdir();self.response(201)
        except (ValueError,OSError): self.response(405)
    def do_MOVE(self):
        try:
            path=self.target(); previous=self.path; self.path=urlsplit(self.headers['Destination']).path; destination=self.target();self.path=previous
            if destination.exists(): return self.response(412)
            path.rename(destination);self.response(201)
        except (ValueError,OSError): self.response(400)
    def do_DELETE(self):
        try:
            path=self.target()
            if path==ROOT: return self.response(403)
            shutil.rmtree(path) if path.is_dir() else path.unlink(); self.response(204)
        except (ValueError,OSError): self.response(404)

if __name__=='__main__':
    print('Disposable WebDAV fixture: http://127.0.0.1:4318/dav/', flush=True)
    ThreadingHTTPServer(('127.0.0.1',4318),Handler).serve_forever()
