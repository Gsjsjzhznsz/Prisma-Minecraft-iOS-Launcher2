#!/usr/bin/env python3
# Task465 自检门 —— 游戏启动链恢复仓库第一个预发行版（v1.0 = f3d31003，
# 2026-10-31「Prisma 2 Beta 发布」，全仓首个/唯一 prerelease）。
#   用户指令：「直接把游戏启动部分的代码恢复到仓库第一个预发行版的吧。」
#   病历链（装机 latestlog，Task464 构建 a21e8ca 实证）：Ame451 preflight
#   PASSED（x16=1 分配通道健康）→ Task457 op4 canary verdict=0 → 优雅拦截
#   → JVM 拒绝发射。同机一代（v7.0 = Task 333 时代，与本仓 v1.0 同形态）
#   正常起游戏。定谳：UniversalJIT26.js 三代零改动（两仓 commit 哈希同源），
#   commands 表仅 x16=0/1/2，op4 主动应答仅存在于 Extension（op2 推送
#   eval）注册成功之时；Task437/451/457/464 四层拦截面在标准脚本会话下
#   必杀启动（canary「主动应答」语义永假）。本轮四层整体退役 + 启动链
#   回 v1.0 形态（裸 op4 best-effort + vm_remap 直达 = 一代可用实证形态），
#   Task433/434 TXM 镜像轨闸、Task304/301/342/267/302（≤368 = v1.0 原生）、
#   Task463 折叠面零触碰。
#   判例 N+20（N+18/N+19 延伸）：「恢复到历史形态」轮的门禁 = 双向执法——
#   退役面归零 + 历史形态在场 + 保留面回归锚三组并行，缺一组即盲区。
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


dyld = rd('Natives/dyld_bypass_validation.m')
utils_m = rd('Natives/utils.m')
utils_h = rd('Natives/utils.h')
jl = rd('Natives/JavaLauncher.m')
pp = rd('Natives/PLPreferences.m')
cards = rd('Natives/ZL2SettingCards.m')
buildtag = rd('Natives/BuildTag.h')

print('== R1 组：v1.0 形态在场执法（恢复目标面） ==')

check('R1a dyld 整文件 v1.0 形态（void init + 镜像裸 op4 + mmap 裸 op1）',
      'void init_bypassDyldLibValidation() {' in dyld
      and 'JIT26PrepareRegionForPatching(patchAddr, sizeof(patch));' in dyld
      and 'JIT26PrepareRegion(map, len);' in dyld
      and 'BOOL init_bypassDyldLibValidation' not in dyld)

check('R1b utils.h init 签名 void（两仓 API 面一致）',
      'void init_bypassDyldLibValidation();' in utils_h
      and 'BOOL init_bypassDyldLibValidation' not in utils_h)

check('R1c JavaLauncher 两调用点裸形态（launchJVM + headless 直达）',
      jl.count('init_bypassDyldLibValidation();') == 2
      and 'if (!init_bypassDyldLibValidation())' not in jl)

check('R1d utils.m 裸超调用四件套在场（x16=1/2/3/4 协议面；op0 DETACH 原生侧不存在=一代同构）',
      all(f'mov x16, #{n} ' in utils_m for n in (1, 2, 3, 4))
      and 'void JIT26PrepareRegionForPatching(void *addr, size_t size) {' in utils_m)

print('== R2 组：四层拦截面归零执法（Task437/451/457/464 退役） ==')

check('R2a Task457/464 面归零（Safe 护栏 + canary + 判例注释）',
      'ame457' not in dyld and 'canary' not in dyld and 'Task457' not in dyld
      and 'Task464' not in dyld and 'ame457_brkWithNet' not in utils_m
      and 'JIT26PrepareRegionForPatchingSafe' not in utils_h + utils_m + dyld)

check('R2b Task437/451 面归零（探针家族 + 预检家族 + include 行）',
      'ame437_selfVerifyJit26Channel' not in jl and 'ame451_preflightJit26Channel' not in jl
      and '★Task437' not in jl and '★Task451' not in jl
      and '#include <signal.h>' not in jl and '#include <setjmp.h>' not in jl
      and 'OSCacheControl' not in jl)

check('R2c 逃生阀 + 54 语种弹窗键归零',
      'jit26_preflight_disable' not in pp
      and 'i18n_str_ame457_dyldhook' not in jl and 'i18n_str_ame451_preflight' not in jl)

tables = sorted(glob.glob(os.path.join(ROOT, 'Natives/resources/*.lproj/Localizable.strings')))
residual = [p for p in tables
            if 'i18n_str_ame457_dyldhook' in rd(os.path.relpath(p, ROOT))
            or 'i18n_str_ame451_preflight' in rd(os.path.relpath(p, ROOT))]
check('R2d 两弹窗键 54 表全量归零', len(tables) >= 54 and not residual,
      f'tables={len(tables)} residual={len(residual)}')

print('== R3 组：保留面回归锚（恢复轮不得误伤） ==')

check('R3a v1.0 原生启动面在场（Task304/301/342/267/302）',
      'ame304_requestAndAwaitJITIfNeeded(@"Launch")' in jl
      and 'ame301_createRegionWithWatchdog()' in jl
      and 'Task342 probe region' in jl
      and 'ame267.jit.legacy_stik' in jl
      and 'ame302_clearStaleDebuggerPorts' in jl)

check('R3b TXM 镜像轨命脉在场（Task433 闸双站 + ame434 探针双站）',
      jl.count('if (ame342_retireMirror && JIT26IsLikelyDebuggerKeepAttached()) {') == 2
      and jl.count('ame434_probeJit26Runtime(javaHome);') == 2)

check('R3c Extension 推送 + 分离旗标在场（op2/op3 面，v1.0 原生）',
      jl.count('JIT26SendJITScript(') == 2
      and 'JIT26SendJITScript(extensionScript);' in jl
      and 'JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached)' in jl)

check('R3d Task463 折叠面零回归（38 组折叠 + 持久化键）',
      'ame449_enableCollapsingWithTitle' in cards
      and 'general.fold_overrides' in cards)

check('R3e main_hook 崩溃分类轴零回归（Task437 分类器消费历史 marker）',
      'ame437_gotmap' in rd('Natives/main_hook.m')
      and 'ame437_probe_canned.txt' in rd('Natives/main_hook.m'))

check('R3f 脚本证据件零回退（UniversalJIT26.js 协议表 0/1/2）',
      'const CMD_DETACH = 0;' in rd('Natives/resources/UniversalJIT26.js')
      and 'const CMD_PREPARE_REGION = 1;' in rd('Natives/resources/UniversalJIT26.js')
      and 'const CMD_NEW_BREAKPOINTS = 2;' in rd('Natives/resources/UniversalJIT26.js'))

print('== S 组：代际锚 + 电池注册 ==')

check('S1 BuildTag Task473 · 2026-11-24（恢复轮代际重锚，464 归零）',
      'Task464 · 2026-11-22' not in buildtag
      and 'ame415_buildTag = @"Task473 · 2026-11-24"' in buildtag)

check('S2 电池注册 task465（声明即实跑）',
      'task465_selfcheck' in rd('scripts/task432_gate_battery.sh'))

print()
print(f'== task465_selfcheck: {len(passed)} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('ALL GREEN')
sys.exit(0)
