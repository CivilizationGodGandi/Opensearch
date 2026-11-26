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
from urllib.parse import parse_qs, unquote, urlparse
from urllib.request import urlopen

HERE = Path(__file__).resolve().parent.parent
ROOT = Path(r'C:\inetpub\opensearch-lookup-ci')
STATE = {'case': 'normal', 'requests': []}


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/_cat/indices/'):
            self.catalog_request()
            return
        if '/_search?' in self.path:
            self.count_request()
            return
        if STATE['case'] == 'abuse_unauthorized':
            self.reply(401, {'errors': [{'detail': 'Invalid API key'}]})
            return
        if STATE['case'] == 'abuse_empty':
            self.reply(200, {'data': {}})
            return
        ip = parse_qs(urlparse(self.path).query)['ipAddress'][0]
        result = {'data': {
            'ipAddress': ip, 'abuseConfidenceScore': 75, 'countryCode': 'KR',
            'usageType': 'Data Center', 'isp': 'TEST ISP', 'domain': 'example.test',
            'totalReports': 99, 'numDistinctUsers': 12,
            'lastReportedAt': '2026-11-26T00:00:00Z', 'isTor': False,
        }}
        self.reply(200, result)

    def catalog_request(self):
        assert self.path.startswith('/_cat/indices/wazuh-archives-*?')
        params = parse_qs(urlparse(self.path).query)
        assert params == {'format': ['json'], 'h': ['index'], 's': ['index:desc'], 'expand_wildcards': ['open']}
        expected = 'Basic ' + base64.b64encode(b'admin:SecretPassword').decode()
        assert self.headers['Authorization'] == expected
        case = STATE['case']
        if case == 'unauthorized':
            self.reply(401, {'error': 'unauthorized'})
            return
        if case == 'slow_catalog':
            time.sleep(21)
        self.reply(200, [] if case == 'empty_indices' else [
            {'index': 'wazuh-archives-4.x-2026.11.26'},
            {'index': 'wazuh-archives-4.x-2026.11.25'},
        ])

    def count_request(self):
        index = unquote(urlparse(self.path).path).split('/')[1]
        assert index in ['wazuh-archives-4.x-2026.11.26', 'wazuh-archives-4.x-2026.11.25']
        assert unquote(self.path).startswith('/' + index + '/_search?'), self.path
        params = parse_qs(urlparse(self.path).query)
        assert params['size'] == ['0']
        assert params['track_total_hits'] == ['true']
        assert params['timeout'][0].endswith('ms')
        assert 0 <= int(params['timeout'][0][:-2]) <= 8000
        assert params['allow_partial_search_results'] == ['true']
        assert params['filter_path'] == ['timed_out,hits.total,_shards.failed,error']
        expected = 'Basic ' + base64.b64encode(b'admin:SecretPassword').decode()
        assert self.headers['Authorization'] == expected
        query = params['q'][0]
        assert query in ['data.srcip:"203.0.113.9" AND location:"210.116.108.137"', 'data.srcip:"203.0.113.9" AND location:"210.116.108.249"']
        STATE['requests'].append((index, query))
        case = STATE['case']
        latest = index.endswith('2026.11.26')
        fw = '210.116.108.137' in query
        if case in ['slow_count', 'shared_deadline'] and not latest and fw:
            time.sleep(21)
        if case == 'shared_deadline' and latest and fw:
            time.sleep(3)
        if case == 'missing_count' and latest and fw:
            self.reply(200, {'timed_out': False, '_shards': {'failed': 0}})
            return
        count = (100 if fw else 10) if latest else (23 if fw else 446)
        timed_out = case == 'partial_zero' or (case == 'partial_count' and latest and fw)
        if case in ['zero', 'partial_zero']:
            count = 0
        elif case == 'partial_count' and latest and fw:
            count = 29918
        relation = 'gte' if case == 'lower_bound' else 'eq'
        failed = 1 if case == 'shard_failure' and latest and fw else 0
        self.reply(200, {'timed_out': timed_out, 'hits': {'total': {'value': count, 'relation': relation}}, '_shards': {'failed': failed}})

    def reply(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

    def log_message(self, *args):
        pass


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    report = []
    with tempfile.TemporaryDirectory() as folder:
        curl = Path(os.environ['SystemRoot']) / 'System32/curl.exe'
        failure = subprocess.run([str(curl), '--disable', '--config', str(Path(folder) / 'missing-config.txt')], capture_output=True)
        assert failure.returncode == 26, (failure.returncode, failure.stderr)
        print('REPRODUCED: unreadable local curl config returns CURL 26', flush=True)
        report.append({'case': 'curl_26_reproduced', 'status': 'passed'})
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
        assert 'Server.ScriptTimeout = 300' in asp
        assert '--max-time 120' not in asp
        asp = asp.replace('"222.233.121"', '"127.0.0.1"', 1)
        asp = asp.replace('https://api.abuseipdb.com', f'http://127.0.0.1:{http.server_port}')
        (ROOT / 'ip_lookup_opensearch.asp').write_bytes(asp.encode('cp949'))
        asp = asp.replace('https://222.233.121.38:9200', f'https://127.0.0.1:{https.server_port}')
        (ROOT / 'ip_lookup_opensearch.asp').write_bytes(asp.encode('cp949'))
        probe = '<%@ Language=VBScript %><% On Error Resume Next : Dim fso, f : Set fso=Server.CreateObject("Scripting.FileSystemObject") : Set f=fso.OpenTextFile(Server.MapPath("missing-file.txt"),1) : Dim firstError : firstError=Err.Number : Dim data : data=f.ReadAll : Response.Write firstError & ":" & Err.Number %>'
        (ROOT / 'probe.asp').write_text(probe, encoding='ascii')
        with urlopen('http://127.0.0.1:18080/probe.asp') as response:
            masked = response.read().decode('ascii')
        assert masked == '53:424', masked
        print('REPRODUCED: file-open error 53 overwritten by Object required 424', flush=True)
        report.append({'case': 'object_required_mask_reproduced', 'status': 'passed'})
        try:
            for case in ['normal', 'slow_count', 'shared_deadline', 'slow_catalog', 'zero', 'empty_indices', 'partial_count', 'partial_zero', 'lower_bound', 'unauthorized', 'shard_failure', 'missing_count', 'abuse_unauthorized', 'abuse_empty']:
                STATE['case'] = case
                STATE['requests'] = []
                url = 'http://127.0.0.1:18080/ip_lookup_opensearch.asp?ip=203.0.113.9'
                started = time.monotonic()
                try:
                    with urlopen(url, timeout=70) as response:
                        html = response.read().decode('cp949')
                except HTTPError as error:
                    print(error.read().decode('cp949', errors='replace'))
                    raise
                if case.startswith('abuse_'):
                    expected_abuse = 'AbuseIPDB 조회 실패 HTTP 401' if case == 'abuse_unauthorized' else 'AbuseIPDB 조회 실패: IP 응답 없음'
                    assert expected_abuse in html and '203.0.113.9' in html, html
                    assert '▶ ISP' in html and '▶ 국가 코드' in html, html
                else:
                    assert 'TEST ISP' in html and 'example.test' in html, html
                    assert '75 / 100' in html and '>99<' in html and '>12<' in html, html
                elapsed = time.monotonic() - started
                expected_requests = 0 if case in ['slow_catalog', 'empty_indices', 'unauthorized'] else (3 if case in ['slow_count', 'shared_deadline'] else 4)
                assert len(STATE['requests']) == expected_requests, html
                expected = {
                    'slow_count': ('100+', '10+'),
                    'shared_deadline': ('100+', '10+'),
                    'slow_catalog': ('0+', '0+'),
                    'zero': ('0', '0'),
                    'empty_indices': ('0', '0'),
                    'partial_count': ('29941+', '456'),
                    'partial_zero': ('0+', '0+'),
                    'lower_bound': ('123+', '456+'),
                    'shard_failure': ('123+', '456'),
                    'missing_count': ('23+', '456'),
                }.get(case, ('123', '456'))
                if case == 'unauthorized':
                    assert html.count('조회 실패 CURL 22') == 2, html
                else:
                    assert '방화벽 탐지 횟수: ' + expected[0] + '건' in html, html
                    assert '웹방화벽 탐지 횟수: ' + expected[1] + '건' in html, html
                    assert '시간 초과' not in html, html
                if case in ['slow_count', 'shared_deadline', 'slow_catalog']:
                    assert 8 <= elapsed < 13, elapsed
                report.append({'case': case, 'status': 'passed', 'requests': len(STATE['requests']), 'elapsed_seconds': round(elapsed, 3)})
                print('PASSED:', case, flush=True)
            broken = asp.replace('openSearchJSON = readTextFile(fso, bodyPath)', 'openSearchJSON = readTextFile(fso, bodyPath & ".missing")')
            (ROOT / 'broken.asp').write_bytes(broken.encode('cp949'))
            STATE['case'] = 'normal'
            with urlopen('http://127.0.0.1:18080/broken.asp?ip=203.0.113.9', timeout=70) as response:
                html = response.read().decode('cp949')
            assert html.count('조회 실패 [35]') == 2, html
            assert '개체가 필요합니다' not in html and 'Object required' not in html, html
            report.append({'case': 'original_file_error_preserved', 'status': 'passed'})
            print('PASSED: file-open failure reports original stage/code; no Object required masking', flush=True)
        finally:
            http.shutdown()
            https.shutdown()
            (HERE / 'tests/test-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Passed CURL 26 reproduction and 14 real IIS Classic ASP cases (including preserved per-index accumulated counts at the shared ten-second deadline); optional client TLS certificates; count-only responses.')


if __name__ == '__main__':
    main()
