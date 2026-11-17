#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task189 —— ★Task440 重生版：旧页退役面验收门。

历史：原 Task189 verifier 检查 DownloadViewController / LauncherRightPanel / 
LauncherPreferences / LauncherNavigationController 四文件（均已于批次二物理
删除）——第 10 期复核报告表 8 #6 判其「检查已删文件（单跑必红）」腐烂。
本轮重生为退役面验收门：断言旧页家族（批次二旧三页 + 死代码六件）物理缺席、
活代码零引用、CMake 零条目、Preview 桩零孤儿。

口径：引用计数前剥 // 行注释（删除记录墓碑注释为家法豁免面）。
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

RETIRE_FAMILY = [
    "ModVersionViewController", "AssetVersionViewController", "ShaderVersionViewController",
    "AccountLoginViewController", "ProfileSettingsViewController",
    "FabricInstallViewController", "WelcomeViewController",
]

FAILS = []


def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f"  {detail}" if not ok and detail else ""))
    if not ok:
        FAILS.append(name)


def code_without_line_comments(text):
    return re.sub(r"//[^\n]*", "", text)


print("== verify_task189 重生版：旧页退役面验收 ==")

# R1 七页 14 文件物理缺席
missing_files = []
for cls in RETIRE_FAMILY:
    for ext in (".h", ".m"):
        p = f"Natives/{cls}{ext}"
        if os.path.exists(p):
            missing_files.append(p)
for cls in ("ProfileSettingsViewController", "FabricInstallViewController"):
    for ext in (".h", ".m"):
        p = f"Natives/installer/{cls}{ext}"
        if os.path.exists(p):
            missing_files.append(p)
check("R1 退役七页 14 文件物理缺席（含 installer 两族）", not missing_files, f"存在: {missing_files[:4]}")

# R2 活代码零引用（Natives 全域剥行注释后扫类名；external 豁免）
live_refs = []
for root, dirs, files in os.walk("Natives"):
    if "external" in root:
        continue
    for fn in files:
        if not fn.endswith((".m", ".h")):
            continue
        p = os.path.join(root, fn)
        try:
            t = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        code = code_without_line_comments(t)
        code = "\n".join(ln for ln in code.split("\n") if not ln.strip().startswith("#pragma"))
        for cls in RETIRE_FAMILY:
            if cls in code:
                live_refs.append(f"{p}:{cls}")
                break
check("R2 活代码零退役类引用（行注释墓碑豁免）", not live_refs, f"refs: {live_refs[:4]}")

# R3 CMake 零条目（注释豁免）
cmk_resid = []
for ln in open("Natives/CMakeLists.txt", encoding="utf-8", errors="replace"):
    code = ln.split("#")[0]
    for cls in RETIRE_FAMILY:
        if f"{cls}.m" in code:
            cmk_resid.append(ln.strip())
check("R3 CMakeLists 零退役 TU 条目（注释豁免）", not cmk_resid, f"resid: {cmk_resid[:3]}")

# R4 Preview 桩零孤儿桩（桩随真身同生死）
stub_path = "Natives/Preview/ZL2PagesStub.m"
stub_orphans = []
if os.path.exists(stub_path):
    stub_code = code_without_line_comments(open(stub_path, encoding="utf-8", errors="replace").read())
    stub_orphans = [c for c in RETIRE_FAMILY if c in stub_code]
check("R4 Preview 桩零孤儿桩", not stub_orphans, f"orphan: {stub_orphans[:3]}")

# R5 失实注释清账：「push ProfileSettingsViewController」现时态声明归零
#    （历史勘误注记允许引用旧写法——仅拦截「= push ProfileSettingsViewController」
#     式现时态契约行）
stale = []
for root, dirs, files in os.walk("Natives"):
    if "external" in root:
        continue
    for fn in files:
        if not fn.endswith((".m", ".h")):
            continue
        p = os.path.join(root, fn)
        t = open(p, encoding="utf-8", errors="replace").read()
        for i, ln in enumerate(t.split("\n"), 1):
            if "push ProfileSettingsViewController" in ln and "★Task440" not in ln and "已随" not in ln and "旧写法" not in ln:
                stale.append(f"{p}:{i}")
check("R5 现时态「push ProfileSettingsViewController」注释归零（勘误注记豁免）",
      not stale, f"stale: {stale[:3]}")

if FAILS:
    print(f"verify_task189 RED: {len(FAILS)} fail(s): {', '.join(FAILS)}")
    sys.exit(1)
print("verify_task189 ALL GREEN —— 旧页退役面干净")
sys.exit(0)
