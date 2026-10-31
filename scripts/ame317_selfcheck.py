#!/usr/bin/env python3
# Task317 插件系统综合静态自查
# ① 权限 id ↔ ame317.perm.* i18n 键对齐（四表）
# ② 多参键占位符个数 vs 代码 formatString 参数个数
# ③ 新 .m 的 import 头文件闭环（文件存在于仓内）
# ④ CMakeLists 已登记全部插件 .m
# ⑤ strings 四表 ame317 键集一致
import os, re, sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

# ── ① 权限 id ↔ i18n 键 ─────────────────────────────────
perm_src = open(os.path.join(NAT, 'AmePluginPermissions.m'), encoding='utf-8').read()
perm_ids = set(re.findall(r'initWithId:@"([a-z0-9._]+)"', perm_src))
langs = {}
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    txt = open(os.path.join(NAT, 'resources', f'{lang}.lproj', 'Localizable.strings'), encoding='utf-8').read()
    langs[lang] = txt
    for pid in perm_ids:
        for suffix in ('name', 'desc'):
            k = f'"ame317.perm.{pid}.{suffix}"'
            check(f'perm key {k} in {lang}', k in txt)

# ── ② 占位符核对 ────────────────────────────────────────
# 代码侧真实调用（手动核对结论固化）：
# 1 参: not_declared(%@) uninstall_confirm_body(%@) api_line(%ld) by_author(%@) invalid_value(%@)
# 2 参: denied(%@,%@)
# 0 参: 其余
expect = {
    'ame317.detail.not_declared': 1,
    'ame317.detail.uninstall_confirm_body': 1,
    'ame317.list.api_line': 1,
    'ame317.list.by_author': 1,
    'ame317.bridge.invalid_value': 1,
    'ame317.bridge.denied': 2,
}
for lang, txt in langs.items():
    for key, n in expect.items():
        m = re.search(r'"%s"\s*=\s*"((?:[^"\\]|\\.)*)"' % re.escape(key), txt)
        if not m:
            check(f'placeholder {key} in {lang}', False, 'key missing'); continue
        val = m.group(1)
        got = len(re.findall(r'%[@dlsu]', val))
        check(f'placeholder {key}={n} in {lang}', got == n, f'got {got}: {val[:60]}')

# ── ③ import 闭环 ───────────────────────────────────────
new_ms = ['AmePluginBridge.m', 'AmePluginManager.m', 'AmePluginPermissions.m',
          'AmePluginRuntime.m', 'ZL2PluginListViewController.m', 'ZL2PluginDetailViewController.m']
natives_files = set()
for root, _, fs in os.walk(NAT):
    if 'Preview' in root: continue
    for f in fs: natives_files.add(f)
for f in new_ms:
    src = open(os.path.join(NAT, f), encoding='utf-8').read()
    for imp in re.findall(r'#import\s+"([^"]+)"', src):
        # ★Task367 重锚：子目录导入（如 AI/AiSettings.h，Task365 ai.ask 接线引入）
        # 按相对路径存在性判定；根目录导入沿用 basename 集合。
        ok = imp in natives_files or os.path.exists(os.path.join(NAT, imp))
        check(f'{f} import {imp}', ok)

# ── ④ CMake 登记 ────────────────────────────────────────
cm = open(os.path.join(NAT, 'CMakeLists.txt'), encoding='utf-8').read()
for f in new_ms:
    check(f'CMake has {f}', f in cm)

# ── ⑤ 四表 ame317 键集一致 ──────────────────────────────
keysets = {}
for lang, txt in langs.items():
    keysets[lang] = set(re.findall(r'"(ame317\.[a-zA-Z0-9_.]+)"\s*=', txt))
base = keysets['en']
check('ame317 keyset size', len(base) == 99, f'got {len(base)}')  # ★Task367 重锚: 62(Task333) → 99（Task364 ui.views +2 / 365 自修复三件套 +8 / 366 权限 20→33 组全量 name/desc 重排）
for lang in ['zh-Hans', 'zh-CN', 'zh-Hant']:
    check(f'keyset {lang} == en', keysets[lang] == base,
          f'diff={base ^ keysets[lang]}')

print()
print(f'FAILURES: {len(fails)}')
sys.exit(1 if fails else 0)
