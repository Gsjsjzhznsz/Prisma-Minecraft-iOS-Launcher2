#!/usr/bin/env python3
"""取 run 的 job 列表与失败 job 日志尾部（302 去 Auth），落盘 /tmp/ci_smoke_<run>.log"""
import base64
import json
import re
import subprocess
import sys
import urllib.request

RUN = sys.argv[1]
url = subprocess.check_output(
    ["git", "-C", "/home/z/my-project/repo-prisma2", "remote", "get-url", "origin"],
    text=True).strip()
tok = re.search(r":([^@]+)@", url).group(1)
owner_repo = re.search(r"github\.com/([^@]+?)(?:\.git)?$", url).group(1)
auth = "Basic " + base64.b64encode(("x-access-token:" + tok).encode()).decode()

UA = "prisma-ci-poll"


def get(path):
    req = urllib.request.Request("https://api.github.com/repos/" + path,
                                 headers={"Authorization": auth,
                                          "Accept": "application/vnd.github+json",
                                          "User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=60))


class NoAuthRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return urllib.request.Request(newurl, headers={
            "Accept": "application/vnd.github+json", "User-Agent": UA})


def get_raw_noauth(path):
    opener = urllib.request.build_opener(NoAuthRedirect)
    req = urllib.request.Request("https://api.github.com/repos/" + path,
                                 headers={"Authorization": auth,
                                          "Accept": "application/vnd.github+json",
                                          "User-Agent": UA})
    return opener.open(req, timeout=120).read()


jobs = get(owner_repo + "/actions/runs/%s/jobs?per_page=20" % RUN)["jobs"]
for j in jobs:
    print("job", j["id"], j["name"][:40], j["status"], "->", j["conclusion"])

for j in jobs:
    if j["conclusion"] == "failure":
        raw = get_raw_noauth(owner_repo + "/actions/jobs/%s/logs" % j["id"])
        txt = raw.decode("utf-8", errors="replace")
        out = "/tmp/ci_smoke_%s.log" % RUN
        open(out, "w", encoding="utf-8").write(txt)
        print("saved", out, len(txt), "chars")
        keep = []
        for ln in txt.splitlines():
            low = ln.lower()
            if ("error:" in ln or "undefined symbol" in low or "ld:" in low
                    or "failed" in low or ("clang" in low and "error" in low)):
                keep.append(ln)
        print("--- error lines (%d) ---" % len(keep))
        for ln in keep[-45:]:
            print(ln[:220])
