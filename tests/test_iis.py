import base64
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse
from urllib.request import urlopen

HERE = Path(__file__).resolve().parent.parent
ROOT = Path(r'C:\inetpub\opensearch-lookup-ci')
STATE = {'case': 'normal', 'requests': []}


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        ip = parse_qs(urlparse(self.path).query)['ipAddress'][0]
        result = {'data': {
            'ipAddress': ip, 'abuseConfidenceScore': 75, 'countryCode': 'KR',
            'usageType': 'Data Center', 'isp': 'TEST ISP', 'domain': 'example.test',
            'totalReports': 99, 'numDistinctUsers': 12,
            'lastReportedAt': '2026-11-26T00:00:00Z', 'isTor': False,
        }}
        self.reply(200, result)

    def do_POST(self):
        assert self.path.startswith('/wazuh-alerts-*/_count?')
        expected = 'Basic ' + base64.b64encode(b'admin:SecretPassword').decode()
        assert self.headers['Authorization'] == expected
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        filters = body['query']['bool']['filter']
        assert filters[0] == {'term': {'data.srcip': '203.0.113.9'}}
        assert 'size' not in body and 'aggs' not in body
        STATE['requests'].append(body)
        case = STATE['case']
        if case == 'unauthorized':
            self.reply(401, {'error': 'unauthorized'})
        elif case == 'shard_failure':
            self.reply(200, {'count': 999, '_shards': {'failed': 1}})
        elif case == 'missing_count':
            self.reply(200, {'_shards': {'failed': 0}})
        else:
            count = 0 if case == 'zero' else (123 if 'data.type' in filters[1]['term'] else 456)
            self.reply(200, {'count': count, '_shards': {'failed': 0}})

    def reply(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    report = []
    with tempfile.TemporaryDirectory() as folder:
        cert, key = Path(folder) / 'cert.pem', Path(folder) / 'key.pem'
        openssl = shutil.which('openssl') or r'C:\Program Files\Git\usr\bin\openssl.exe'
        subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', '/CN=localhost'], check=True, capture_output=True)
        http = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        https = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        context.load_verify_locations(cert)
        context.verify_mode = ssl.CERT_OPTIONAL
        https.socket = context.wrap_socket(https.socket, server_side=True)
        for server in (http, https):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        asp = (HERE / 'ip_lookup_opensearch.asp').read_text(encoding='utf-8')
        asp = asp.replace('"222.233.121"', '"127.0.0.1"', 1)
        asp = asp.replace('https://api.abuseipdb.com', f'http://127.0.0.1:{http.server_port}')
        asp = asp.replace('pythonExe = "python.exe"', f'pythonExe = "{sys.executable}"')
        (ROOT / 'ip_lookup_opensearch.asp').write_bytes(asp.encode('cp949'))
        helper = (HERE / 'opensearch_count.py').read_text(encoding='utf-8')
        helper = helper.replace('https://222.233.121.38:9200', f'https://127.0.0.1:{https.server_port}')
        (ROOT / 'opensearch_count.py').write_text(helper, encoding='utf-8')
        try:
            for case in ['normal', 'zero', 'unauthorized', 'shard_failure', 'missing_count']:
                STATE['case'] = case
                STATE['requests'] = []
                url = 'http://127.0.0.1:18080/ip_lookup_opensearch.asp?ip=203.0.113.9'
                try:
                    with urlopen(url, timeout=70) as response:
                        html = response.read().decode('cp949')
                except HTTPError as error:
                    print(error.read().decode('cp949', errors='replace'))
                    raise
                assert 'TEST ISP' in html and 'example.test' in html, html
                assert '75 / 100' in html and '>99<' in html and '>12<' in html, html
                assert len(STATE['requests']) == 2, html
                if case == 'normal':
                    assert '방화벽 탐지 횟수: 123건' in html, html
                    assert '웹방화벽 탐지 횟수: 456건' in html, html
                elif case == 'zero':
                    assert '방화벽 탐지 횟수: 0건' in html, html
                    assert '웹방화벽 탐지 횟수: 0건' in html, html
                else:
                    expected = {'unauthorized': 'ERROR HTTP 401', 'shard_failure': 'ERROR SHARD_FAILURE',
                                'missing_count': 'ERROR INVALID_COUNT'}[case]
                    assert html.count(expected) == 2, html
                    assert '탐지 횟수: 0건' not in html, html
                report.append({'case': case, 'status': 'passed', 'requests': len(STATE['requests'])})
                print('PASSED:', case, flush=True)
        finally:
            http.shutdown()
            https.shutdown()
            (HERE / 'tests/test-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Passed 5 real IIS Classic ASP cases; optional client TLS certificates; count-only responses.')


if __name__ == '__main__':
    main()
