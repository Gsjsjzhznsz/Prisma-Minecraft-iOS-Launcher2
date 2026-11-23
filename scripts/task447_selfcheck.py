#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""task447_selfcheck —— Task472 退役化改写：Task447 隔离行真实态装载/写入
（isolationRow + ame447_applyIsolationToggle 全族）已随版本隔离退役删除；
本门反向执法其缺席 + Task463 折叠面保形 + 括号平衡。"""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
fails = []
sp = (ROOT / 'Natives' / 'ZL2SettingPages.m').read_text(encoding='utf-8')
for sym in ['isolationRow', 'ame447_applyIsolationToggle', 'ame447_isolationStateText',
            'ame447_isolationSwitchOn', 'ame369.setpg.version_isolation',
            'general.isolation_default"']:
    code = '\n'.join(re.sub(r'//.*', '', ln) for ln in sp.split('\n'))
    if sym in code:
        fails.append(f'隔离行残面 {sym}')
d = 0
for ln in sp.split('\n'):
    s = re.sub(r'//.*', '', ln)
    s = re.sub(r'@"[^"]*"', '""', s)
    s = re.sub(r'"[^"]*"', '""', s)
    d += s.count('{') - s.count('}')
if d != 0:
    fails.append(f'括号失衡 delta={d}')
fold = sum((ROOT / n).read_text(encoding='utf-8').count('defaultCollapsed:')
           for n in ('Natives/ZL2SettingPages.m', 'Natives/ZL2SettingCards.m', 'Natives/ZL2SettingCards.h'))
if fold < 41:
    fails.append(f'折叠面锚 {fold} < 41')
print('task447_selfcheck(退役化): ' + ('ALL GREEN — 隔离行零残面 + 折叠面保形' if not fails else 'FAIL'))
for f in fails:
    print('  -', f)
sys.exit(1 if fails else 0)
