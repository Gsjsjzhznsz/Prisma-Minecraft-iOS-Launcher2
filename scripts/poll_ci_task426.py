#!/usr/bin/env python3
# poll_ci_task426.py — 轮询 Task426 CI 双工作流至终态（development 43612424270 +
# ui-smoke 43612424303）；每 45s 采样，最长 40 分钟。
import json
import subprocess
import sys
import time

TOKEN = subprocess.check_output(
    ["git", "-C", "/home/z/my-project/work416", "remote", "get-url", "origin"],
    text=True).strip()
TOKEN = TOKEN.split("https://")[1].split("@")[0]
REPO = "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2"
RUNS = {"development": 43612424270, "ui-smoke": 43612424303}


def fetch(run_id):
    out = subprocess.check_output([
        "curl", "-sS", "-H", f"Authorization: token {TOKEN}",
        f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}"])
    return json.loads(out)


deadline = time.time() + 40 * 60
while time.time() < deadline:
    states = {}
    for name, rid in RUNS.items():
        r = fetch(rid)
        states[name] = (r.get("status"), r.get("conclusion"))
    line = " | ".join(f"{n}={s}/{c}" for n, (s, c) in states.items())
    print(time.strftime("%H:%M:%S"), line, flush=True)
    if all(s == "completed" for s, _ in states.values()):
        ok = all(c == "success" for _, c in states.values())
        print("TERMINAL:", "ALL GREEN" if ok else "FAILURE")
        sys.exit(0 if ok else 1)
    time.sleep(45)
print("TIMEOUT")
sys.exit(2)
