#!/usr/bin/env python3
# Task451 自检门 —— ★Task465 判例翻转：JIT26ExecPreflight 预检面整体退役
#   历史断言（Task451）：授予前 64MB 级通道预检（三试重试环 + 零取指执行探测
#   + 四态判决 + 定罪 marker + 逃生阀 + 54 语种诊断窗）。
#   翻转病历（Task465 定谳，用户装机 latestlog 实证）：preflight 对
#   x16=1 分配通道的 PASSED 无法代表 op4 应答语义——UniversalJIT26.js
#   commands 表仅 x16=0/1/2（三代零改动，两仓 commit 哈希同源），op4 在标准
#   脚本会话永不被主动应答（未知命令优雅跳过，主循环 P20=pc+4 先行）；
#   Task457 canary verdict=0 拦截发生于 preflight PASSED 之后 = 预检面
#   对本轮病灶零检出价值。同机一代（v1.0 同形态）无预检面正常起游戏。
#   本轮（Task465）：预检家族 + 调用点 + 逃生阀注册 + 54 语种两弹窗键
#   随启动链四层拦截面（Task437/451/457/464）整体退役；v1.0 原生启动面
#   （Task342 探针/ame267 legacy 分支/Extension 推送）在场执法。
import os
import glob
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


jl = rd('Natives/JavaLauncher.m')
pp = rd('Natives/PLPreferences.m')
buildtag = rd('Natives/BuildTag.h')

print('== A 组：预检家族归零执法（Task465 翻转） ==')

check('A1 预检主链函数归零（ame451_preflightJit26Channel + 信号网 + 探针）',
      'ame451_preflightJit26Channel' not in jl and 'ame451_prepEnv' not in jl
      and 'ame451_execEnv' not in jl and 'ame451_prepareGuarded' not in jl)

check('A2 预检调用点归零（ conviction 拒绝发射面随四层退役）',
      'Task451 preflight conviction' not in jl
      and 'i18n_str_ame451_preflight' not in jl
      and 'debug.jit26_preflight_disable' not in jl)

check('A3 Task451 字样归零（JavaLauncher 注释含幂）',
      '★Task451' not in jl and 'Task451 preflight' not in jl)

print('== B 组：逃生阀注册 + 54 语种弹窗键退役 ==')

check('B1 逃生阀注册归零（PLPreferences，毗邻 mirror_codecache 阀零触碰）',
      'jit26_preflight_disable' not in pp
      and 'mirror_codecache_disable' in pp
      and '★Task451' not in pp)

tables = sorted(glob.glob(os.path.join(ROOT, 'Natives/resources/*.lproj/Localizable.strings')))
retired = [p for p in tables
           if 'i18n_str_ame451_preflight' in rd(os.path.relpath(p, ROOT))
           or 'i18n_str_ame457_dyldhook' in rd(os.path.relpath(p, ROOT))]
check('B2 两弹窗键全语种归零（54 表 → 0 表残留）',
      len(tables) >= 54 and not retired, f'tables={len(tables)} residual={len(retired)}')

control = [p for p in tables
           if 'i18n_str_jit26_not_ready' in rd(os.path.relpath(p, ROOT))]
check('B3 对照键在册（表结构未损，仅退役键移除）',
      len(control) == len(tables), f'control={len(control)}/{len(tables)}')

print('== C 组：v1.0 原生启动面在场执法（Task465 恢复轮回归锚） ==')

check('C1 Task342 探针 + ame267 legacy 分支 + Extension 推送在场（v1.0 原生）',
      'Task342 probe region' in jl
      and 'ame267.jit.legacy_stik' in jl
      and jl.count('JIT26SendJITScript(') == 2
      and 'JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached)' in jl)

check('C2 init 裸调用双站在场（v1.0 直达形态）',
      jl.count('init_bypassDyldLibValidation();') == 2
      and 'if (!init_bypassDyldLibValidation())' not in jl)

print('== S 组：代际锚 ==')

check('S1 BuildTag Task466 · 2026-11-22（恢复轮代际重锚）',
      'ame415_buildTag = @"Task466 · 2026-11-22"' in buildtag)

print()
print(f'== task451_selfcheck: {len(passed)} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('ALL GREEN')
sys.exit(0)
