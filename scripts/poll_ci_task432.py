#!/usr/bin/env python3
"""Task432 CI 轮询 —— token 从 git remote URL 内存提取（绝不打印）。
用法: python3 scripts/poll_ci_task432.py <sha> [max_seconds]
每 30s 查一次 runs?head_sha=<sha>，全部 completed 即退出打印结论。
"""
import json
import re
import subprocess
import sys
import time
import urllib.request

SHA = sys.argv[1]
MAXS = int(sys.argv[2]) if len(sys.argv) > 2 else 500
REPO = "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2"

url = subprocess.check_output(
    ["git", "-C", "/home/z/my-project/repo-prisma2", "remote", "get-url", "origin"],
    text=True).strip()
tok = re.search(r":([^@]+)@", url).group(1)
owner_repo = re.search(r"github\.com/([^@]+?)(?:\.git)?$", url).group(1)
auth = "Basic " + __import__("base64").b64encode(("x-access-token:" + tok).encode()).decode()

api = "https://api.github.com/repos/" + owner_repo + "/actions/runs?head_sha=" + SHA


def get(path):
    req = urllib.request.Request("https://api.github.com/repos/" + path,
                                 headers={"Authorization": auth,
                                          "Accept": "application/vnd.github+json",
                                          "User-Agent": "prisma-ci-poll"})
    return json.load(urllib.request.urlopen(req, timeout=30))


t0 = time.time()
seen = {}
while time.time() - t0 < MAXS:
    data = get(owner_repo + "/actions/runs?head_sha=" + SHA + "&per_page=20")
    runs = data.get("workflow_runs", [])
    lines = []
    all_done = bool(runs)
    for r in runs:
        key = (r["name"], r["event"])
        lines.append("%s | %s | %s | %s -> %s | %s" % (
            r["id"], r["name"][:28], r["event"], r["status"], r["conclusion"],
            r["html_url"]))
        if r["status"] != "completed":
            all_done = False
    print("=== poll t+%ds runs=%d ===" % (int(time.time() - t0), len(runs)))
    for ln in lines:
        print(" ", ln)
    sys.stdout.flush()
    if all_done:
        print("ALL COMPLETED")
        sys.exit(0)
    time.sleep(30)
print("TIMEOUT still running")
sys.exit(2)
