#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task482 换代重锚 sweep —— 门禁日期字面量族 Task480 · 2026-11-27 /
Task481 · 2026-11-28 → Task483 · 2026-11-28（task480 轮同款脚本家族的幂等
重放；Task481 轮 sweep 欠账随本批一并清偿）。

范围：scripts/ 下 .py/.sh 全量（除 task482_generation_sweep.py 本体与
task470_artifact_verify.py——V3/V4 已在本轮单独手术：V3 在场翻转换代 482 +
V4 退役清单补 481/480（五消轮转），避免 sweep 二次翻转 V4 新插入的退役
字面量 = Task479 判例③「谓词副本须与主检查同批换代」的排序镜像）。
幂等：二跑零改动。
用法: python3 scripts/task482_generation_sweep.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OLDS = [
    "Task481 · 2026-11-28",   # Task481 轮代际（装机线，sweep 欠账）
    "Task480 · 2026-11-27",   # Task480 轮代际
]
NEW = "Task483 · 2026-11-28"
# ★进代下限门家族的前缀形（无日期字面量）——ame468 S / task475 / task476
#   p3+S3/W1 / task477 D1 / task478 D1 等 check 用 'ame415_buildTag = @"Task4xx · '
#   判在场（判例③：谓词副本须与主检查同批换代——S3 内联 replace 的变异串
#   目标 'Task476 · ' 保持旧代，不在翻转面）。
PREFIX_OLDS = ['@"Task481 · ', '@"Task480 · ']
PREFIX_NEW = '@"Task483 · '
SKIP = {"task482_generation_sweep.py", "task470_artifact_verify.py"}


def main():
    changed, skipped_already = [], []
    for p in sorted(ROOT.glob("*.py")) + sorted(ROOT.glob("*.sh")):
        if p.name in SKIP:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        new_text = text
        for o in OLDS:
            new_text = new_text.replace(o, NEW)
        for po in PREFIX_OLDS:
            new_text = new_text.replace(po, PREFIX_NEW)
        if new_text != text:
            p.write_text(new_text, encoding="utf-8")
            changed.append(p.name)
        elif NEW in text or PREFIX_NEW in text:
            skipped_already.append(p.name)
    print(f"sweep changed={len(changed)} {changed}")
    print(f"sweep already-ok={len(skipped_already)}")
    # 终检：除 SKIP 外不得残留旧字面量（日期形 + 前缀形）
    residue = []
    for p in sorted(ROOT.glob("*.py")) + sorted(ROOT.glob("*.sh")):
        if p.name in SKIP:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        if any(o in text for o in OLDS) or any(po in text for po in PREFIX_OLDS):
            residue.append(p.name)
    if residue:
        print(f"[FAIL] 旧代际字面量残留: {residue}")
        return 1
    print("task482_generation_sweep ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
