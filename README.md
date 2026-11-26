# 단일 ASP OpenSearch IP 조회

운영 파일은 `ip_lookup_opensearch.asp` 하나입니다.
Windows 기본 `curl.exe`를 동기 실행하며 Python·PowerShell·추가 실행 파일을 설치하지 않습니다.
IIS 익명 인증 계정과 사용자 프로필 설정을 변경하지 않습니다.

## 적용

1. ASP의 `apiKey`, `aiKey`에 기존 키를 유지합니다. 공개 저장소에는 실제 API 키가 없습니다.
2. OpenSearch 주소·계정은 `osBaseUrl`, `osUser`, `osPassword`에서 지정합니다.
3. 파일을 CP949(ANSI)로 저장해 기존 ASP와 교체합니다.
4. 기존 주소에 `?ip=조회할IP`로 접속합니다.

기존 AbuseIPDB 조회·위험도·국가·ISP·신고 내역·화면·AI 코드를 유지합니다.
두 건수는 `_count`로만 조회합니다.
방화벽: `data.srcip` + `data.type=traffic`.
웹방화벽: `data.srcip` + `decoder.name=Monitorapp-data`.
AbuseIPDB 실패 때도 입력 IP로 건수 조회와 화면 표시를 계속합니다.
원본에서 비활성 상태였던 룰명·탐지 근거 조회는 활성화하지 않습니다.
요청용 임시 파일은 처리가 끝나면 삭제합니다. HTTPS 서버 인증서 검사 생략은 기존 코드와 동일합니다.

## 검증

Windows IIS의 익명 인증·사용자 프로필 설정을 변경하지 않고 7개 실행 테스트를 통과했습니다.
정상 건수, 0건, OpenSearch HTTP 401, 샤드 실패, count 누락,
AbuseIPDB HTTP 401, AbuseIPDB IP 응답 누락을 확인합니다.
HTTPS 모의 서버는 클라이언트 인증서를 선택적으로 요청합니다.
테스트용 Python은 CI의 모의 API 서버에만 사용하며 운영 ASP에서 호출하지 않습니다.
운영 OpenSearch 직접 접속 테스트는 포함하지 않습니다.

검증 결과: https://github.com/CivilizationGodGandi/Opensearch/actions/runs/45759310990
