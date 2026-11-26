# OpenSearch ASP IP 조회

기존 Classic ASP의 AbuseIPDB 조회, 위험도·국가·ISP·신고 내역, 화면, AI 호출 코드를 유지합니다.
MySQL 건수 조회를 OpenSearch `_count` 조회로 교체합니다.
ASP에서 Python을 실행하며 Python 표준 라이브러리만 사용합니다.

| 항목 | 값 |
|---|---|
| OpenSearch 주소 | `https://222.233.121.38:9200` |
| 인덱스 | `wazuh-alerts-*` |
| 출발지 IP 필드 | `data.srcip` |
| 방화벽 구분 | `data.type=traffic` |
| 웹방화벽 구분 | `decoder.name=Monitorapp-data` |
| 반환 변수 | `fwCount`, `wafCount` |

## 적용

1. Python이 설치된 IIS 서버에서 저장소 파일을 내려받습니다.
2. 기존 ASP 파일 경로를 넣어 실행합니다.

```cmd
python prepare.py "C:\inetpub\wwwroot\ip_lookup_opensearch.asp"
```

3. 생성된 `deploy` 폴더의 ASP와 `opensearch_count.py`를 기존 ASP 폴더에 함께 복사합니다.
4. 기존 페이지에 `?ip=조회할IP`로 접속합니다.

`prepare.py`는 기존 ASP에서 AbuseIPDB·OpenRouter 키를 읽어 유지하고, 현재 Python 실행 경로를 자동 지정합니다.
ASP 파일은 EUC-KR 사이트에 맞춰 CP949로 생성합니다. 기존 ASP는 준비 과정에서 변경하지 않습니다.
OpenSearch 계정은 `opensearch_count.py`의 `USERNAME`, `PASSWORD`에서 지정합니다.
기본값은 기존 Wazuh 배포본과 같은 `admin/SecretPassword`입니다.
API 키는 이 저장소에 포함하지 않습니다. `deploy`는 Git 추적에서 제외합니다.

## 동작

두 요청 모두 IP와 장비 조건으로 `_count`만 호출합니다. 원본 로그는 조회하지 않습니다.
조회 오류는 0건으로 표시하지 않고 해당 항목에 오류를 표시합니다.
원본에서 주석 처리되어 있던 룰명·탐지 근거 조회는 활성화하지 않았습니다.
따라서 이번 변경으로 기존 AI 호출 조건이 새로 충족되지는 않습니다.
OpenSearch 서버 설정이나 시스템 curl을 변경하지 않습니다.
HTTPS의 서버 인증서 검사 생략은 기존 ASP 설정과 동일합니다.

## 검증

GitHub Actions에서 Windows Server 2022에 IIS와 Classic ASP를 설치해 실제 ASP 페이지를 호출합니다.
OpenSearch·AbuseIPDB 대신 로컬 테스트 서버를 사용합니다.
HTTPS 서버는 클라이언트 인증서를 선택적으로 요청하며, Python은 인증서 없이 접속합니다.

- 정상 건수: 방화벽 123건, 웹방화벽 456건
- 탐지 내역 없음: 각각 0건
- HTTP 401: 오류 표시
- 일부 샤드 실패: 오류 표시
- count 누락: 오류 표시
- 모든 사례에서 기존 AbuseIPDB 화면 필드 유지

실제 운영 OpenSearch와 IIS에 대한 접속 검증은 포함하지 않습니다.
