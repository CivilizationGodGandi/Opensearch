import re
import sys
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent
    source = (root / "ip_lookup_opensearch.asp").read_text(encoding="utf-8")
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python prepare.py "C:\\inetpub\\wwwroot\\existing.asp"')

    original_path = Path(sys.argv[1])
    raw = original_path.read_bytes()
    try:
        original = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        original = raw.decode("cp949")

    for name, placeholder in [("apiKey", "ABUSEIPDB_API_KEY"),
                              ("aiKey", "Bearer OPENROUTER_API_KEY")]:
        match = re.search(r'(?im)^\s*' + name + r'\s*=\s*"((?:[^"]|"")*)"', original)
        if not match:
            raise SystemExit("Missing original setting: " + name)
        source = source.replace(placeholder, match.group(1))

    # IIS 환경의 PATH에 의존하지 않도록 현재 Python의 전체 경로를 기록합니다.
    source = source.replace('pythonExe = "python.exe"',
                            'pythonExe = "' + sys.executable.replace('"', '""') + '"')
    output = root / "deploy"
    output.mkdir(exist_ok=True)
    (output / original_path.name).write_bytes(source.replace("\r\n", "\n").replace("\n", "\r\n").encode("cp949"))
    (output / "opensearch_count.py").write_bytes((root / "opensearch_count.py").read_bytes())
    print("Prepared:", output / original_path.name)
    print("Prepared:", output / "opensearch_count.py")


if __name__ == "__main__":
    main()
