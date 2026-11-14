#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task427 CI 轮询：development + ui-smoke 双工作流至终态。"""
import json, subprocess, sys, time, urllib.request

COMMIT = "c9ee071"
TOKEN = open("/home/z/my-project/.gh_token").read().strip()
REPO = "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2"
HDR = {"Authorization": "token " + TOKEN, "Accept": "application/vnd.github+json",
       "User-Agent": "task427-poll"}

def api(url):
    req = urllib.request.Request(url, headers=HDR)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

def runs():
    data = api(f"https://api.github.com/repos/{REPO}/actions/runs?head_sha={COMMIT}&per_page=20")
    return data.get("workflow_runs", [])

seen, deadline = {}, time.time() + 60 * 55
while time.time() < deadline:
    rr = runs()
    for r in rr:
        seen[r["id"]] = r
    summary = []
    done = True
    for rid, r in sorted(seen.items()):
        summary.append((rid, r["name"], r["status"], r["conclusion"]))
        if r["status"] != "completed":
            done = False
    print(time.strftime("%H:%M:%S"), summary, flush=True)
    if done and seen:
        bad = [s for s in summary if s[3] not in ("success",)]
        if bad:
            print("RESULT: FAILURE", bad)
            sys.exit(1)
        print("RESULT: ALL GREEN")
        for rid, name, st, cc in sorted(summary):
            print(f"  run {rid} [{name}] {cc}")
        sys.exit(0)
    time.sleep(45)
print("RESULT: TIMEOUT")
sys.exit(2)
