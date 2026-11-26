import base64
import ipaddress
import json
import re
import ssl
import sys
from urllib.error import HTTPError
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

BASE_URL = "https://222.233.121.38:9200/wazuh-alerts-*"
USERNAME = "admin"
PASSWORD = "SecretPassword"


def make_opener():
    context = ssl.create_default_context()
    # 기존 ASP의 서버 인증서 검사 생략 설정과 동일하게 적용합니다.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return build_opener(ProxyHandler({}), HTTPSHandler(context=context))


def get_count(opener, source_ip, device_filter):
    body = {"query": {"bool": {"filter": [
        {"term": {"data.srcip": source_ip}}, device_filter
    ]}}}
    token = base64.b64encode(
        (USERNAME + ":" + PASSWORD).encode("utf-8")
    ).decode("ascii")
    request = Request(
        BASE_URL + "/_count?filter_path=count,_shards.failed,error",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": "Basic " + token,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with opener.open(request, timeout=15) as response:
            result = json.load(response)
        if result.get("_shards", {}).get("failed") != 0:
            return "ERROR SHARD_FAILURE"
        count = result.get("count")
        if type(count) is not int or count < 0:
            return "ERROR INVALID_COUNT"
        return str(count)
    except HTTPError as error:
        return "ERROR HTTP " + str(error.code)
    except Exception as error:
        detail = re.sub(r"[^A-Za-z0-9 _.:/-]", "?", str(error))[:180]
        return "ERROR " + type(error).__name__ + ": " + detail


def main():
    try:
        source_ip = str(ipaddress.ip_address(sys.stdin.readline().strip()))
        opener = make_opener()
        result = {
            "fwCount": get_count(opener, source_ip, {"term": {"data.type": "traffic"}}),
            "wafCount": get_count(opener, source_ip, {"term": {"decoder.name": "Monitorapp-data"}}),
        }
    except Exception as error:
        message = "ERROR " + type(error).__name__
        result = {"fwCount": message, "wafCount": message}
    print(json.dumps(result, ensure_ascii=True), flush=True)


if __name__ == "__main__":
    main()
