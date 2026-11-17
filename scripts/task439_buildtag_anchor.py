#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task439 代际锚门（第 10 期复核报告 6.3 节「BuildTag 落后 2 轮 + worklog 自述矛盾」
的制度化防再犯：每轮电池实跑校验 Natives/BuildTag.h 的 ame415_buildTag 重锚状态）。

规则：
  B1  BuildTag 值形如 "Task<NNN> · YYYY-MM-DD"，可解析；
  B2  锚号 = 近 40 条提交主题里出现的最大 Task 号，或最大值 + 1
      （+1 容差覆盖「门禁先跑、本轮提交后落」的时序：门禁时 HEAD 仍在上一轮）；
  B3  锚号不得小于日志最大号（落后即红——Task437/438 两轮未重锚的复发即拦）；
  B4  锚号不得超前日志最大号 2 及以上（防止改了别处忘提交正文）。
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAG_FILE = ROOT / "Natives" / "BuildTag.h"


def git_log_max_task():
    out = subprocess.run(
        ["git", "log", "--oneline", "-40"], cwd=ROOT,
        capture_output=True, text=True, timeout=30).stdout
    nums = [int(n) for n in re.findall(r"Task(\d+)", out)]
    return max(nums) if nums else None


def main():
    fails = []
    text = TAG_FILE.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'ame415_buildTag = @"Task(\d+) · (\d{4}-\d{2}-\d{2})"', text)
    if not m:
        print("[FAIL] B1 BuildTag 值不可解析（期望 \"Task<NNN> · YYYY-MM-DD\"）")
        return 1
    tag_num, tag_date = int(m.group(1)), m.group(2)
    print(f"  BuildTag = Task{tag_num} · {tag_date}")
    if not re.match(r"\d{4}-\d{2}-\d{2}$", tag_date):
        fails.append("B1 date-format")

    log_max = git_log_max_task()
    if log_max is None:
        print("[FAIL] B2 git log 无 Task 号可解析")
        return 1
    print(f"  git log max Task = Task{log_max}")
    if tag_num < log_max:
        fails.append(f"B3 anchor-behind (tag={tag_num} < log={log_max})")
    if tag_num > log_max + 1:
        fails.append(f"B4 anchor-ahead (tag={tag_num} > log={log_max}+1)")

    if fails:
        for f in fails:
            print(f"[FAIL] {f}")
        print("task439_buildtag_anchor RED —— 每轮合流清单必含「BuildTag 重锚当前轮次」")
        return 1
    print("task439_buildtag_anchor ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
