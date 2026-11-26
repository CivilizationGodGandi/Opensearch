# 단일 ASP OpenSearch IP 조회

운영에 필요한 파일은 `ip_lookup_opensearch.asp` 하나입니다.
Python, curl, 별도 PS1 파일을 설치하거나 배포하지 않습니다.
ASP 내부에서 Windows 기본 PowerShell 5.1과 .NET HTTPS 기능을 호출합니다.

## 적용

1. IIS 사이트의 **인증 → 익명 인증 → 편집 → 응용 프로그램 풀 ID**를 선택합니다.
2. 해당 앱 풀의 **고급 설정 → 사용자 프로필 로드 = True**를 지정하고 풀을 재시작합니다.
3. ASP의 `apiKey`, `aiKey`에 기존 AbuseIPDB·OpenRouter 키를 유지합니다.
4. OpenSearch 주소와 계정은 `osBaseUrl`, `osUser`, `osPassword`에서 지정합니다.
5. 파일을 ANSI/CP949로 저장해 기존 ASP와 교체합니다.
6. 기존 주소에 `?ip=조회할IP`로 접속합니다.

기존 AbuseIPDB 조회, 위험도·국가·ISP·신고 내역, 화면, AI 코드 유지.
MySQL 건수 조회 부분만 OpenSearch `_count` 호출로 교체합니다.
방화벽: `data.srcip` + `data.type=traffic`.
웹방화벽: `data.srcip` + `decoder.name=Monitorapp-data`.
건수만 `fwCount`, `wafCount`에 넣으며 원본 로그는 조회하지 않습니다.
원본에서 주석 처리되어 있던 룰명·탐지 근거 조회를 활성화하지 않았습니다.
서버 인증서 검사 생략은 기존 ASP와 동일합니다.
API 키는 공개 저장소에 포함하지 않습니다.

## 테스트

GitHub Actions에서 실제 Windows IIS/Classic ASP 페이지를 호출합니다.
정상 건수, 0건, HTTP 401, 일부 샤드 실패, count 누락을 확인합니다.
테스트용 HTTPS 서버는 클라이언트 인증서를 선택적으로 요청합니다.
`tests/test_iis.py`는 CI의 모의 API 서버이며 운영 ASP에서는 사용하지 않습니다.
운영 OpenSearch에 직접 접속하는 테스트는 포함하지 않습니다.

단일 ASP Windows IIS 테스트 5개 통과: https://github.com/CivilizationGodGandi/Opensearch/actions/runs/45756489593

AbuseIPDB의 HTTP 401 또는 IP 응답 누락 시에도 입력 IP로 OpenSearch 건수 조회와 화면 표시를 계속합니다.
백지 화면 실패 경로를 포함한 IIS 테스트 7개 통과: https://github.com/CivilizationGodGandi/Opensearch/actions/runs/45757370330
