#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task464 自检门：JIT op4 金丝雀误杀修正轮（用户诉「问题依旧。为什么一代正常。拉个对比一下。」）。

判例链（同机 A/B 对比取证）：
  A. 用户设备 Task463 构建（702c9d8）：Ame451 preflight PASSED（x16=1 分配通道
     健康）→ Task457 canary verdict=0（x16=4 探测）→ graceful abort。
  B. 同机一代构建正常启动 = 一代 mirrored 的 op4 分支未执行（若执行，一代裸调
     op4 无 SIGTRAP handler 必闪退，与实证矛盾）→ 用户设备 FORCE_MIRRORED=0。
  C. UniversalJIT26.js commands 表仅 x16=0/1/2——x16=4 协议不存在，canary
     探测「实际不会走的路径」= 协议必然假阴性（Task463 verdict=0 根因）。
  修正：canary 运行条件收紧 = 与 mirrored 内部 op4 实际调用条件完全一致
  （FORCE_MIRRORED && HAS_TXM）；真需 op4 的设备保留 Task457 .ips 防线。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []
CHECKS = [0]


def check(name, cond, detail=""):
    CHECKS[0] += 1
    if cond:
        print(f"  [PASS] {name}")
    else:
        FAILS.append(name)
        print(f"  RED  {name}" + (f" | {detail}" if detail else ""))


def rd(p):
    return (ROOT / p).read_text(encoding="utf-8", errors="replace")


def scan_count(pattern):
    n = 0
    pat = re.compile(pattern)
    for f in list((ROOT / "Natives").rglob("*.m")) + list((ROOT / "Natives").rglob("*.h")):
        n += len(pat.findall(f.read_text(encoding="utf-8", errors="replace")))
    return n


dyld = rd("Natives/dyld_bypass_validation.m")
utils_m = rd("Natives/utils.m")
jl = rd("Natives/JavaLauncher.m")

print("== R canary 条件收紧执法 ==")
check("R1 canary 运行条件 = mirrored 内部 op4 实际调用条件（双行与语义）",
      "if (redirectFunction == redirectFunctionMirrored\n"
      "        && DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {" in dyld)
check("R2 判例注释三锚在场（脚本协议不存在/一代对齐/条件收紧）",
      "x16=4（PrepareRegionForPatching）在脚本协议中" in dyld
      and "一代行为逐指令对齐" in dyld
      and "Task464 判例修正" in dyld)
check("R3 脚本协议取证锚（commands 表仅 0/1/2，证据件不回退）",
      "const CMD_NEW_BREAKPOINTS = 2;" in rd("Natives/resources/UniversalJIT26.js")
      and "const CMD_PREPARE_REGION = 1;" in rd("Natives/resources/UniversalJIT26.js")
      and "const CMD_DETACH = 0;" in rd("Natives/resources/UniversalJIT26.js"))

print("== R Task457 防线原样在场（不回退） ==")
check("R4 mirrored 内 Safe op4 调用保留（FORCE_MIRRORED 设备防线）",
      "if (!JIT26PrepareRegionForPatchingSafe(patchAddr, sizeof(patch))) {" in dyld)
check("R5 canary 探针三件套保留（Safe 调用+释放+verdict 日志）",
      "JIT26PrepareRegionForPatchingSafe(ame457_scratch, 16)" in dyld
      and "munmap(ame457_scratch, getpagesize());" in dyld
      and "op4 canary verdict=%d (scratch-page round-trip)" in dyld)
check("R6 信号网保留（ame457_brkWithNet SIGTRAP 网在 utils.m）",
      "static BOOL ame457_brkWithNet(void (^fn)(void)) {" in utils_m
      and "siglongjmp(ame457_trapEnv, 1)" in utils_m)
check("R7 JavaLauncher 两调用点优雅退出保留",
      jl.count("if (!init_bypassDyldLibValidation()) {") == 2
      and jl.count("i18n_str_ame457_dyldhook") == 2)
check("R8 ame451 preflight 通道保留（x16=1 分配探测不回退）",
      scan_count(r"Ame451\] preflight attempt") >= 2)

print("== S 代际与注册 ==")
tag = rd("Natives/BuildTag.h")
check("S1 BuildTag Task464 · 2026-11-22", "Task463 · 2026-11-22" not in tag
      and "Task464 · 2026-11-22" in tag)
check("S2 电池注册 task464", "task464_selfcheck" in rd("scripts/task432_gate_battery.sh"))
check("S3 ame457 诊断窗 i18n 键仍全语种入册（en/zh-Hans 抽样）",
      "i18n_str_ame457_dyldhook" in rd("Natives/resources/en.lproj/Localizable.strings")
      and "i18n_str_ame457_dyldhook" in rd("Natives/resources/zh-Hans.lproj/Localizable.strings"))

print(f"\n========================================")
if FAILS:
    print(f"task464_selfcheck RED —— {len(FAILS)} failed / {CHECKS[0]} total")
    sys.exit(1)
print(f"task464_selfcheck: {CHECKS[0]} passed, 0 failed")
