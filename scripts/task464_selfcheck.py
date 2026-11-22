#!/usr/bin/env python3
# Task464 自检门 —— ★Task465 判例翻转：canary 条件收紧面整体退役
#   历史断言（Task464）：canary 运行条件收紧为与 mirrored 内部 op4 实际调用
#   条件一致（FORCE_MIRRORED && HAS_TXM 双 flags），判据「用户设备
#   FORCE_MIRRORED=0 → canary 跳过 → 与一代逐指令对齐」。
#   翻转病历（Task465 定谳，用户装机 Task464 构建 latestlog 实证）：
#     canary 实跑且 verdict=0 = 用户设备双 flags 为真——Task464 前提
#     「FORCE_MIRRORED=0」被证伪；且 UniversalJIT26.js commands 表仅
#     x16=0/1/2（三代零改动，两仓 commit 哈希同源），op4 在标准脚本会话
#     永不被主动应答 → canary「主动应答」语义对标准会话永假 = 收紧后
#     仍必杀真实 TXM 设备会话。同机一代（v1.0 同形态）正常起游戏。
#   本轮（Task465）：启动链四层拦截面（Task437/451/457/464）整体退役，
#   dyld_bypass_validation.m 整文件回填 v1.0（f3d31003）形态。
#   R3 脚本协议取证锚原样保留（证据件不回退——op4 不在脚本协议中是
#   本轮定谳的物理前提，与本轮恢复方向一致）。
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

fails, passed = [], []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if ok:
        passed.append(name)
    else:
        fails.append(name)


def rd(p):
    with open(os.path.join(ROOT, p), encoding='utf-8', errors='replace') as f:
        return f.read()


dyld = rd("Natives/dyld_bypass_validation.m")
utils_m = rd("Natives/utils.m")
jl = rd("Natives/JavaLauncher.m")

print("== R canary 收紧面退役执法（Task465 翻转） ==")
check("R1 canary 条件双行归零（Task464 条件收紧面随整文件回填退役）",
      "if (redirectFunction == redirectFunctionMirrored\n"
      "        && DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {" not in dyld
      and "op4 canary verdict" not in dyld)
check("R2 判例注释三锚归零（v1.0 blob 无 Task464 判例文本）",
      "x16=4（PrepareRegionForPatching）在脚本协议中" not in dyld
      and "一代行为逐指令对齐" not in dyld
      and "Task464 判例修正" not in dyld
      and "Task464" not in dyld)
check("R3 脚本协议取证锚（commands 表仅 0/1/2，证据件不回退）",
      "const CMD_NEW_BREAKPOINTS = 2;" in rd("Natives/resources/UniversalJIT26.js")
      and "const CMD_PREPARE_REGION = 1;" in rd("Natives/resources/UniversalJIT26.js")
      and "const CMD_DETACH = 0;" in rd("Natives/resources/UniversalJIT26.js"))

print("== R Task457 防线退役执法（四层整体退役） ==")
check("R4 mirrored 内 Safe op4 调用归零（v1.0 裸调形态回归）",
      "JIT26PrepareRegionForPatchingSafe" not in dyld
      and "JIT26PrepareRegionForPatching(patchAddr, sizeof(patch));" in dyld)
check("R5 canary 探针三件套归零",
      "ame457_scratch" not in dyld and "op4 canary verdict" not in dyld)
check("R6 信号网归零（ame457_brkWithNet 退出 utils.m）",
      "ame457_brkWithNet" not in utils_m and "ame457_trapEnv" not in utils_m)
check("R7 JavaLauncher 两调用点裸形态回归（优雅退出面退役）",
      jl.count("init_bypassDyldLibValidation();") == 2
      and "if (!init_bypassDyldLibValidation()) {" not in jl
      and "i18n_str_ame457_dyldhook" not in jl)
check("R8 ame451 preflight 通道归零（x16=1 预检面随四层退役）",
      "ame451_preflightJit26Channel" not in jl
      and "Ame451] preflight attempt" not in jl)

print("== S 代际与注册 ==")
tag = rd("Natives/BuildTag.h")
check("S1 BuildTag Task466 · 2026-11-22", "Task464 · 2026-11-22" not in tag
      and "Task466 · 2026-11-22" in tag)
check("S2 电池注册 task465", "task465_selfcheck" in rd("scripts/task432_gate_battery.sh"))

print()
print(f'== task464_selfcheck: {len(passed)} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('ALL GREEN')
sys.exit(0)
