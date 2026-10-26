#!/usr/bin/env python3
# Task334 线③：偏好键注册面全仓审计。
# 规矩（Task142/143/230 病历）：PLPreferences 只能读写"已注册"的键 —— 注册面 =
#   ① 字面量 @"key": 形（setDefaultsForPref 内字典）
#   ② 括号赋值 [...][@"key"] = 形（global 段尾追加）
#   ③ 存量设备 plist 已有的键（无法静态判定，忽略）
# 未注册键的 setter 写入被静默丢弃（setObject 返回 NO），getter 恒回落代码内
# 默认 + 每次访问打一行 "could not find" 日志。本审计扫描 Natives/*.m 的
# getPref*/setPref* 调用点，按"是否出现 setter""是否注册"两维出清单。
import re
import glob
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREF = os.path.join(ROOT, 'Natives', 'PLPreferences.m')

reg_src = open(PREF, errors='ignore').read()
# ① 字面量注册：@"key":（后跟冒号；排除 @"section.key" 全点分调用形态——注册面只会是纯段内键）
registered = set(re.findall(r'@"([A-Za-z_][A-Za-z_0-9]*)"\s*:', reg_src))
# ② 括号赋值注册：[@"key"]（= 赋值 / 直接读）
registered |= set(re.findall(r'\[@"([A-Za-z_][A-Za-z_0-9]*)"\]', reg_src))
# setDefaultsForPref 的段名（避免把段名当漏注册键——段名不是叶子键）
sections = set(re.findall(r'@"([A-Za-z_][A-Za-z_0-9]*)"\s*:\s*\@\{', reg_src))

getters, setters = {}, {}
for f in sorted(glob.glob(os.path.join(ROOT, 'Natives', '**', '*.m'), recursive=True)):
    src = open(f, errors='ignore').read()
    for m in re.finditer(r'\b(get|set)Pref\w+\(\s*@"([A-Za-z_][A-Za-z_0-9.]*)"', src):
        kind, key = m.group(1), m.group(2)
        if '.' not in key:
            continue
        leaf = key.split('.')[-1]
        bucket = setters if kind == 'set' else getters
        bucket.setdefault(key, set()).add(os.path.relpath(f, ROOT))

print('=== SET 路径且疑似未注册（写入被静默丢弃 = 功能性 bug）===')
broken = False
for key in sorted(setters):
    leaf = key.split('.')[-1]
    if leaf in registered or leaf in sections:
        continue
    broken = True
    print(f'  {key}  <- {", ".join(sorted(setters[key]))}')
if not broken:
    print('  (none)')

print('=== 仅 GET 路径且疑似未注册（回落默认 + 日志噪音）===')
noisy = False
for key in sorted(getters):
    if key in setters:
        continue
    leaf = key.split('.')[-1]
    if leaf in registered or leaf in sections:
        continue
    noisy = True
    print(f'  {key}  <- {", ".join(sorted(getters[key]))}')
if not noisy:
    print('  (none)')

print('=== SET+GET 双路径注册健康键（抽样确认计数）===')
ok = [k for k in setters if k.split('.')[-1] in registered or k.split('.')[-1] in sections]
print(f'  {len(ok)} keys healthy')
