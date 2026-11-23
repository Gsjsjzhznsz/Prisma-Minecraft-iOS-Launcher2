#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task219 —— Task472 退役化改写：版本隔离体系整体退役（用户钦定全删）。
原 Task219 隔离自动识别（ame219 状态机）已随退役删除；本门反向执法其缺席，
并锚定 Task472 统一共享根解析的在场。零残留 + 新锚在场 = PASS。"""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
fails = []
def grep_natives(pat):
    out = []
    for p in list(ROOT.glob('Natives/**/*.m')) + list(ROOT.glob('Natives/**/*.h')):
        if 'Preview/ZL2PagesStub' in str(p):
            continue
        for i, ln in enumerate(p.read_text(encoding='utf-8', errors='ignore').split('\n'), 1):
            s = re.sub(r'//.*', '', ln)
            if re.search(pat, s):
                out.append(f'{p.relative_to(ROOT)}:{i}')
    return out
for sym in ['ame219_isolationStateForProfile', 'ame225_sniffedIsolationGameDirForProfile',
            'ame271_selfHealStrandedIsolation', 'ame324_ensureIsolationSkeleton',
            'ame325_ensureInstanceAxisSkeletons', 'ame450_seedIsolatedVersionData',
            'ame428_effectiveIsolationForVid', 'ame428_effectiveCore']:
    hits = grep_natives(re.escape(sym))
    if hits:
        fails.append(f'隔离符号残留 {sym}: {hits[:4]}')
jl = (ROOT / 'Natives' / 'JavaLauncher.m').read_text(encoding='utf-8')
if '[JavaLauncher] Task473: gameDir = %@ (isolation=%d vid=%@)' not in jl:
    fails.append('启动链 Task472 共享根锚缺席')
ms = (ROOT / 'Natives' / 'ModService.m').read_text(encoding='utf-8')
if 'resolveAbsoluteGameDirForProfile' not in ms or 'POJAV_GAME_DIR' not in ms:
    fails.append('ModService 统一共享根解析缺席')
print('verify_task219(退役化): ' + ('ALL GREEN — 隔离体系零残留 + Task472 锚在场' if not fails else 'FAIL'))
for f in fails:
    print('  -', f)
sys.exit(1 if fails else 0)
