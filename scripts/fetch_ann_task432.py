#!/usr/bin/env python3
"""取 run 全部 check-run 注解（错误行），r1/r2 诊断用。"""
import base64
import json
import re
import subprocess
import os as _os
REPO_LOCAL = _os.environ.get("AME_REPO") or _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))   # ★Task455：脚本自身位置解析（历史绝对路径随沙箱回收失效）
import sys
import urllib.request

RUN = sys.argv[1]
url = subprocess.check_output(
    ["git", "-C", REPO_LOCAL, "remote", "get-url", "origin"],
    text=True).strip()
tok = re.search(r":([^@]+)@", url).group(1)
owner_repo = re.search(r"github\.com/([^@]+?)(?:\.git)?$", url).group(1)
auth = "Basic " + base64.b64encode(("x-access-token:" + tok).encode()).decode()


def get(path):
    req = urllib.request.Request("https://api.github.com/repos/" + path,
                                 headers={"Authorization": auth,
                                          "Accept": "application/vnd.github+json",
                                          "User-Agent": "prisma-ci-poll"})
    return json.load(urllib.request.urlopen(req, timeout=60))


sha = subprocess.check_output(["git", "-C", REPO_LOCAL,
                               "rev-parse", "HEAD"], text=True).strip()
crs = get(owner_repo + "/commits/" + sha + "/check-runs?per_page=20")["check_runs"]
for cr in crs:
    print("== %s (%s) run=%s" % (cr["name"], cr["conclusion"], cr.get("details_url", "")[-40:]))
    if cr["conclusion"] == "failure" or cr["output"].get("annotations_count"):
        anns = get(owner_repo + "/check-runs/%s/annotations?per_page=30" % cr["id"])
        for a in anns:
            lvl = a.get("annotation_level")
            msg = a.get("message", "").replace("\n", " | ")[:300]
            if lvl == "failure" or "error" in msg.lower():
                print("  [%s] %s" % (lvl, msg))
