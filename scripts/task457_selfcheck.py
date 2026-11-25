#!/usr/bin/env python3
# Task457 自检门 —— ★Task465 判例翻转：启动链恢复仓库第一个预发行版（v1.0 形态）
#   历史断言（Task457~464）：op1/op4 Safe 护栏 + vm_protect 执法 + 写回校验 +
#   op4 通道金丝雀 + 调用点优雅退出 + Task464 canary 条件收紧——全部要求
#   「调试器主动应答 brk #0xf00d op4」。
#   翻转病历（用户装机 latestlog，Task464 构建 a21e8ca 实证）：
#     Ame451 preflight PASSED（x16=1 分配通道健康）→ DyldLVBypass init →
#     Task457: op4 canary verdict=0 → 优雅拦截 → JVM 拒绝发射。
#   同机 A/B 定谳：一代（v7.0 = Task 333 时代，与本仓 v1.0 同形态）同设备
#   同调试器正常起游戏。UniversalJIT26.js 三代零改动（两仓 commit 哈希同源
#   479f75ca），commands 表仅 x16=0/1/2，op4 处理器仅由 Extension（op2 推送
#   eval）注册；未知命令优雅跳过（主循环 P20=pc+4 先行）——canary 的
#   「主动应答」语义在标准脚本会话中永假 = 必杀所有标准会话。Task464 预判
#   （用户设备 FORCE_MIRRORED=0）被 Task464 构建装机日志证伪（canary 实跑）。
#   本轮（Task465）：四层启动拦截面（Task437/451/457/464）整体退役，启动链
#   恢复 v1.0 形态——裸 op4 best-effort + vm_remap 直达（一代同设备可用实证）。
#   断言语义翻转：Task457/464 面 → 归零执法；v1.0 形态 → 在场执法。
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


dyld = rd('Natives/dyld_bypass_validation.m')
utils_m = rd('Natives/utils.m')
utils_h = rd('Natives/utils.h')
jl = rd('Natives/JavaLauncher.m')
buildtag = rd('Natives/BuildTag.h')

print('== R 组：Task457/464 四层拦截面归零执法（Task465 翻转） ==')

check('R1 Safe 护栏三件套归零（utils.h 声明 + utils.m 信号网 + dyld 调用）',
      'JIT26PrepareRegionSafe' not in utils_h and 'JIT26PrepareRegionForPatchingSafe' not in utils_h
      and 'ame457_brkWithNet' not in utils_m and 'ame457_trapEnv' not in utils_m
      and 'JIT26PrepareRegionForPatchingSafe' not in dyld and 'JIT26PrepareRegionSafe' not in dyld)

check('R2 op4 金丝雀归零（dyld 无 canary/Task457/Task464 字样，注释含幂）',
      'canary' not in dyld and 'Task457' not in dyld and 'Task464' not in dyld
      and 'ame457' not in dyld)

check('R3 vm_protect 执法 + 写回校验退役（v1.0 直写形态回归）',
      'ame457_prot' not in dyld and 'patch write-back verify' not in dyld
      and 'builtin_memcpy((char *)mirrored, patch, sizeof(patch));' in dyld)

check('R4 init 签名回退 void（v1.0 形态，两仓 API 面一致）',
      'void init_bypassDyldLibValidation() {' in dyld
      and 'BOOL init_bypassDyldLibValidation' not in dyld
      and 'void init_bypassDyldLibValidation();' in utils_h)

check('R5 调用点裸形态回归（launchJVM + headless 两站无中止面）',
      jl.count('init_bypassDyldLibValidation();') == 2
      and 'if (!init_bypassDyldLibValidation())' not in jl
      and 'i18n_str_ame457_dyldhook' not in jl
      and 'Task457: dyld library-validation bypass incomplete' not in jl)

check('R6 镜像路径裸 op4 / mmap 裸 op1 在场（v1.0 协议 canon）',
      'JIT26PrepareRegionForPatching(patchAddr, sizeof(patch));' in dyld
      and 'JIT26PrepareRegion(map, len);' in dyld)

check('R7 退役面旁证：Task437/451 面同步归零（同轮四层整体退役）',
      'ame437_selfVerifyJit26Channel' not in jl and 'ame451_preflightJit26Channel' not in jl
      and '★Task437' not in jl and '★Task451' not in jl
      and 'jit26_preflight_disable' not in rd('Natives/PLPreferences.m'))

check('R8 镜像轨命脉零回归（Task433/434 TXM 闸双站 + ame434 探针双站）',
      jl.count('if (ame342_retireMirror && JIT26IsLikelyDebuggerKeepAttached()) {') == 2
      and jl.count('ame434_probeJit26Runtime(javaHome);') == 2)

print('== S 组：代际锚 + 电池注册 ==')

check('S1 BuildTag Task477 · 2026-11-25（恢复轮代际重锚，464 归零）',
      'Task464 · 2026-11-22' not in buildtag
      and 'ame415_buildTag = @"Task477 · 2026-11-25"' in buildtag)

check('S2 电池注册 task465（Task439 幽灵门判例：声明即实跑）',
      'task465_selfcheck' in rd('scripts/task432_gate_battery.sh'))

print()
print(f'== task457_selfcheck: {len(passed)} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('ALL GREEN')
sys.exit(0)
