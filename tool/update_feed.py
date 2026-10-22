#!/usr/bin/env python3
"""
本機測試自動更新用的假「最新版」（只在開發時用，正式版讀 GitHub）。

把資料夾裡的安裝檔（例如 make macos 產生的 Securibit-<版本>-macos.zip）列成和 GitHub
releases/latest 相同格式的 latest.json，算出 SHA256SUMS.txt，再用 http.server 在 127.0.0.1 提供：

    python3 tool/update_feed.py <資料夾> <版本> [--port 8765] [--bad-checksum] [--no-checksums]

App 要用 --dart-define=UPDATE_FEED_URL=http://127.0.0.1:8765/latest.json 建置才會讀這份。
--bad-checksum：SHA256SUMS.txt 故意寫錯，確認 App 會丟掉檔案、不安裝
--no-checksums：不提供 SHA256SUMS.txt，確認 App 改成提示用瀏覽器下載
"""
import argparse, functools, hashlib, http.server, json, os, sys

parser = argparse.ArgumentParser(description="本機測試自動更新用的假 Release")
parser.add_argument("dir", help="放安裝檔的資料夾（latest.json、SHA256SUMS.txt 也寫在這裡）")
parser.add_argument("version", help="假的最新版本，例如 1.2.0")
parser.add_argument("--port", type=int, default=8765)
parser.add_argument("--bad-checksum", action="store_true")
parser.add_argument("--no-checksums", action="store_true")
args = parser.parse_args()

root = os.path.abspath(args.dir)
base = f"http://127.0.0.1:{args.port}"
skip = {"latest.json", "SHA256SUMS.txt"}
files = sorted(f for f in os.listdir(root) if f not in skip and not f.startswith(".") and os.path.isfile(os.path.join(root, f)))
if not files:
    sys.exit(f"{root} 裡沒有安裝檔")

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()

sums_path = os.path.join(root, "SHA256SUMS.txt")
if args.no_checksums:
    if os.path.exists(sums_path): os.remove(sums_path)
else:
    with open(sums_path, "w") as fh:
        for f in files:
            fh.write(f"{'0' * 64 if args.bad_checksum else sha256(os.path.join(root, f))}  {f}\n")

assets = files + ([] if args.no_checksums else ["SHA256SUMS.txt"])
latest = {
    "tag_name": f"v{args.version}",
    "name": f"v{args.version}",
    "html_url": f"{base}/",
    "draft": False,
    "prerelease": False,
    "body": f"## 本機測試\n- 假的 {args.version}，用來測自動更新\n",
    "assets": [{"name": f, "browser_download_url": f"{base}/{f}"} for f in assets],
}
with open(os.path.join(root, "latest.json"), "w") as fh:
    json.dump(latest, fh, ensure_ascii=False, indent=2)

print(f"UPDATE_FEED_URL={base}/latest.json")
for f in assets: print(f"  {base}/{f}")
sys.stdout.flush()
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
