#!/usr/bin/env python3
# Task332 自查门禁
# ① 插件线：门面作用域修复（var ame= IIFE 赋值）+ load census 双面升级
#    + boot 桥面自证 + 勘测插件资源面
# ② MD3 开关：apply block 动画事务 layoutIfNeeded
# ③ 版本隔离：ame324 实例轴接管守卫（ame324×ame328 抖动消除）
#    + insertSafety 良性路径静默
# ④ 小窗输入：触点取证面放宽（freeform 标志/contentOrigin/bounds 落日志）
import os, re, sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

def read(p):
    return open(os.path.join(p), encoding='utf-8').read()

# ── ① 插件线 ──────────────────────────────────────────────
R = read(os.path.join(NAT, 'AmePluginRuntime.m'))
check('P1 facade assigns IIFE to global ame', 'var ame=(function(raw){' in R)
check('P1 facade comment documents scope bug', '门面作用域根修' in R)
check('P2 load census dual-face (facade)', 'Task332 load census' in R and 'facade(addLauncherRow)' in R)
check('P2 load census dual-face (raw)', 'raw(rowHandler/log)' in R)
check('P2 census probes raw.log', 'objectForKeyedSubscript:@"log"' in R)
check('P3 boot bridge export self-check', 'Task332 bridge export self-check' in R)
check('P3 self-check probes JSExport conformance', 'class_conformsToProtocol([AmePluginBridge class], @protocol(JSExport))' in R)

survey_m = read(os.path.join(NAT, 'resources', 'builtin-plugins', 'plugin-survey', 'manifest.json'))
survey_j = read(os.path.join(NAT, 'resources', 'builtin-plugins', 'plugin-survey', 'main.js'))
import json
try:
    sm = json.loads(survey_m)
    ok_manifest = (sm.get('id') == 'plugin-survey' and sm.get('entry') == 'main.js'
                   and set(sm.get('permissions') or []) <= {'ui.rows', 'ui.dialog', 'storage'}
                   and sm.get('minApi') == 1)
except Exception:
    ok_manifest = False
check('P4 plugin-survey manifest schema', ok_manifest)
check('P4 plugin-survey main.js guards ame', 'typeof ame' in survey_j)
check('P4 plugin-survey main.js non-trivial', len(survey_j) > 500, f'len={len(survey_j)}')
check('P4 plugin-survey main.js logs marker', 'Task332-survey' in survey_j)

# ── ② MD3 开关动画 ───────────────────────────────────────
K = read(os.path.join(NAT, 'ZL2M3Kit.m'))
check('M1 apply block layouts inside animation transaction',
      re.search(r'ame_applyAppearanceAnimated[\s\S]{0,2600}\[self layoutIfNeeded\];', K) is not None)
check('M1 travel geometry untouched (Task331 anchor)', 'CGFloat lead = checked ? 24.0 : 4.0;' in K)

# ── ③ 版本隔离 ───────────────────────────────────────────
M = read(os.path.join(NAT, 'ModService.m'))
check('V1 ame324 instance-axis takeover guard',
      re.search(r'ame324_ensureIsolationSkeletonForVersionId[\s\S]{0,1800}isAbsolutePath[\s\S]{0,120}return;', M) is not None)
check('V1 guard mirrors ame328 semantics (comment)', 'ame324×ame328 每启动抖动消除' in M)
U = read(os.path.join(NAT, 'MinecraftResourceUtils.m'))
check('V2 insertSafety benign path silenced', 'how to insert' not in U)
check('V2 insertSafety semantics documented', '良性路径静默' in U)

# ── ④ 小窗输入取证放宽 ───────────────────────────────────
S = read(os.path.join(NAT, 'SurfaceViewController.m'))
check('I1 forensic widened to all window states (Task333 re-anchor: 333 live/legacy)', 'Task277/332/333: touch forensic' in S)
check('I1 forensic logs freeform flag', 'freeform=%d' in S)
check('I1 forensic logs contentOrigin', 'content=%.0fx%.0f@(%.0f,%.0f)' in S)
check('I1 forensic logs window/screen bounds', 'windowBounds=%@ screenBounds=%@' in S)
check('I1 no more freeform-only gate', 'g_ame267_freeformScaled && event == ACTION_DOWN' not in S)

# ── 既有锚点不回退 ───────────────────────────────────────
check('A1 JSExport protocol kept (Task331 anchor)', 'AmePluginBridgeJSExport <JSExport>' in read(os.path.join(NAT, 'AmePluginBridge.h')))
check('A2 storageSetValue facade call kept (Task331 anchor)', 'raw.storageSetValue(String(k),v)' in R)
check('B fingerprint gate kept (Task331 anchor)', 'ame331_lastFactorFrame' in S)
check('D active-instance re-point kept (Task331 anchor)', 'Task331' in read(os.path.join(NAT, 'JavaLauncher.m')) if os.path.exists(os.path.join(NAT, 'JavaLauncher.m')) else False)

print()
if fails:
    print(f'FAIL {len(fails)} check(s): {fails}')
    sys.exit(1)
print('ALL GREEN')
