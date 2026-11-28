#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task483 换代重锚 sweep —— 门禁日期字面量族 Task482 · 2026-11-28 →
Task483 · 2026-11-28（Task480 轮同款脚本家族的幂等重放）。

范围：scripts/ 下 .py/.sh 全量（除 task470_artifact_verify.py——V3/V4 已在本轮
单独手术：V3 在场翻转 + V4 退役清单补 482，避免 sweep 二次翻转 V4
新插入的退役字面量 = Task479 判例③「谓词副本须与主检查同批换代」的排序镜像）。
幂等：二跑零改动。
用法: python3 scripts/task483_generation_sweep.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OLD = "Task482 · 2026-11-28"
NEW = "Task483 · 2026-11-28"
PREFIX_OLD = '@"Task482 · '
PREFIX_NEW = '@"Task483 · '
SKIP = {"task483_generation_sweep.py", "task470_artifact_verify.py"}


def main():
    changed, skipped_already = [], []
    for p in sorted(ROOT.glob("*.py")) + sorted(ROOT.glob("*.sh")):
        if p.name in SKIP:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        new_text = text.replace(OLD, NEW).replace(PREFIX_OLD, PREFIX_NEW)
        if new_text != text:
            p.write_text(new_text, encoding="utf-8")
            changed.append(p.name)
        elif NEW in text or PREFIX_NEW in text:
            skipped_already.append(p.name)
    print(f"sweep changed={len(changed)} {changed}")
    print(f"sweep already-ok={len(skipped_already)}")
    # 终检：除 SKIP + 退役清单外不得残留旧字面量（两种形态）
    residue = []
    for p in sorted(ROOT.glob("*.py")) + sorted(ROOT.glob("*.sh")):
        if p.name in SKIP:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        if OLD in text or PREFIX_OLD in text:
            residue.append(p.name)
    if residue:
        print(f"[FAIL] 旧代际字面量残留: {residue}")
        return 1
    print("task483_generation_sweep ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
