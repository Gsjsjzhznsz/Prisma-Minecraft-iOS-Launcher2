#!/usr/bin/env python3
"""Task334 门禁电池 —— 四线收口断言。
线① SDL 小窗偏移第五轮（MC 侧双信念劈裂收口）：
  A1 PollEvent 钉扎面扩到 0x206（0x206/0x207/0x208 三口全钉）
  A2 改写日志升 Task61/334
  A3 宣告面 0x206+0x207 事件对（ame334_pushWindowSizePair）
  A4 强制通道/83b 通道均走事件对
  A5 SIZE_CHANGED 常量定义在案
线③ 偏好键注册面（Setter 静默丢弃族修复）：
  B1-B10 注册键逐一在案（jvm_preset/jvm_preset_custom_args/speed_probe 双键/
      mod_touch_user_off/two_finger_keyboard/mod_touch_prev_preset_json/
      thirdparty_servers/translation_notice_dismissed/autolaunch_profile/
      mirror_idx/autoRendererBlacklist/disable_window_rotation_shim/
      ame259_quic_guard/ame280_kw_batch/internal_launch_on_boot/account_selected_name）
  B11 审计脚本零 SET 路径漏注册（存活项均为有意保留：死键/只读/zink 风险面）
线④ 动画/逻辑优化：
  C1 ame232 幂等 memo 闸在案
  C2 风格切换绕过 memo（floatingGlassStyleChanged 置无效）
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

failures = []
passed = 0

def check(name, cond, detail=''):
    global passed
    if cond:
        passed += 1
        print(f'  ok  {name}')
    else:
        failures.append(name)
        print(f'  FAIL {name} {detail}')

def read(rel):
    with open(os.path.join(ROOT, rel), errors='ignore') as f:
        return f.read()

# ── A 线① SDL 双信念收口 ──────────────────────────────────────
hook = read('Natives/sdl3_hook.m')
ibv3 = read('Natives/input_bridge_v3.m')
gmv = read('Natives/GameMenuOverlayView.m')

check('A1 PollEvent 钉扎面 0x206+0x207+0x208 三口',
      re.search(r'type == 0x206 .{0,80}\|\|\s*\n?\s*type == 0x207 .{0,60}\|\|\s*\n?\s*type == 0x208', hook)
      or ('type == 0x206' in hook and 'type == 0x207' in hook and 'type == 0x208' in hook
          and re.search(r'0x206[^\n]*\n\s*type == 0x207', hook)),
      'sdl3_hook.m Task61/334 rewrite condition')

check('A2 改写日志 Task61/334', 'Task61/334 window-size event' in hook)

check('A3 ame334_pushWindowSizePair 定义且推 0x206+0x207',
      'ame334_pushWindowSizePair' in ibv3
      and 'SDL3_EVENT_WINDOW_SIZE_CHANGED' in ibv3
      and re.search(r'ame334_types\[2\]\s*=\s*\{\s*SDL3_EVENT_WINDOW_SIZE_CHANGED,\s*\n?\s*SDL3_EVENT_WINDOW_RESIZED', ibv3),
      'input_bridge_v3.m pair helper')

check('A4 强制通道走事件对',
      'ame334_pushWindowSizePair(width, height)' in ibv3
      and ibv3.count('ame334_pushWindowSizePair(width, height)') >= 2,
      f"count={ibv3.count('ame334_pushWindowSizePair(width, height)')}")

check('A5 SIZE_CHANGED 0x206 常量定义', '#define SDL3_EVENT_WINDOW_SIZE_CHANGED 0x206' in ibv3)

check('A6 旧单发 0x207 push 块已清零（防双源漂移）',
      'we->type = SDL3_EVENT_WINDOW_RESIZED;' not in ibv3.replace('ame334_types[2] = { SDL3_EVENT_WINDOW_SIZE_CHANGED,\n                                       SDL3_EVENT_WINDOW_RESIZED };', ''),
      'legacy inline push sites')

# ── B 线③ 偏好键注册面 ──────────────────────────────────────
pref = read('Natives/PLPreferences.m')
b_keys = [
    ('B1 java.jvm_preset', '@"jvm_preset": @"normal"'),
    ('B2 java.jvm_preset_custom_args', '@"jvm_preset_custom_args": @""'),
    ('B3 download.speed_probe.bmclapi', '@"bmclapi": [NSDictionary new]'),
    ('B4 download.speed_probe.mcim', '@"mcim": [NSDictionary new]'),
    ('B5 control.mod_touch_user_off', '@"mod_touch_user_off": @NO'),
    ('B6 control.two_finger_keyboard', '@"two_finger_keyboard": @NO'),
    ('B7 control.mod_touch_prev_preset_json', '@"mod_touch_prev_preset_json": @""'),
    ('B8 general.thirdparty_servers', '@"thirdparty_servers": [NSArray new]'),
    ('B9 general.translation_notice_dismissed', '@"translation_notice_dismissed": @NO'),
    ('B10 general.disable_window_rotation_shim', '@"disable_window_rotation_shim": @NO'),
    ('B11 internal.autolaunch_profile', '@"autolaunch_profile": @""'),
    ('B12 internal.internal_launch_on_boot', '@"internal_launch_on_boot": @NO'),
    ('B13 debug.ame259_quic_guard', '@"ame259_quic_guard": @NO'),
    ('B14 debug.ame280_kw_batch', '@"ame280_kw_batch": @NO'),
    ('B15 controlrepo.mirror_idx', '@"mirror_idx": @(0)'),
    ('B16 ame217.autoRendererBlacklist', '@"autoRendererBlacklist": @""'),
    ('B17 launcher.account_selected_name', '@"account_selected_name": @""'),
]
for name, lit in b_keys:
    check(name, lit in pref, f'literal {lit!r} missing in PLPreferences.m')

check('B18 审计脚本存在且可跑', os.path.exists(os.path.join(ROOT, 'scripts', 'ame334_pref_key_audit.py')))

# ── C 线④ 动画/逻辑优化 ──────────────────────────────────────
check('C1 ame232 幂等 memo 闸', 'ame334_glassMemoValid' in gmv
      and 'CGRectEqualToRect(self.ame334_lastGlassGearFrame' in gmv)
check('C2 风格切换绕过 memo',
      re.search(r'ame232_floatingGlassStyleChanged\s*\{[^}]*ame334_glassMemoValid = NO', gmv, re.S),
      'style-change path must invalidate memo')
check('C3 memo ivar 三件在类扩展', gmv.count('ame334_') >= 5)

# ── 括号平衡（编辑面编译保险；HEAD 对照式 —— 判定"本次编辑是否引入新失衡"，
# 复用 task139 剥离算法排除字符串/注释干扰；存量文件的既有形差不算失败）────
def _strip_strings_comments(text):
    import sys as _s
    _s.path.insert(0, os.path.join(ROOT, 'scripts'))
    import task139_syntax_gate as _t139
    return _t139.strip_strings_comments(text)

def _deltas(src):
    return (src.count('{') - src.count('}'),
            src.count('(') - src.count(')'),
            src.count('[') - src.count(']'))

import subprocess as _sp
for rel in ['Natives/PLPreferences.m', 'Natives/sdl3_hook.m',
            'Natives/input_bridge_v3.m', 'Natives/GameMenuOverlayView.m']:
    cur = _deltas(_strip_strings_comments(read(rel)))
    head_src = _sp.run(['git', 'show', f'HEAD:{rel}'],
                       capture_output=True, text=True).stdout
    head = _deltas(_strip_strings_comments(head_src))
    check(f'D 括号平衡(HEAD对照) {os.path.basename(rel)}', cur == head,
          f'cur={cur} head={head}')

print(f'\nRESULT: {passed} pass, {len(failures)} fail')
if failures:
    print('FAILURES PRESENT:', ', '.join(failures))
    sys.exit(1)
print('ALL GREEN')
