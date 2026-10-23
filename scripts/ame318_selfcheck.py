#!/usr/bin/env python3
# Task318 内置插件仓库综合静态自查
# ① builtin-plugins 资源完备性（4 插件 × manifest+main.js，schema 字段/权限 id 合法）
# ② ame318.* 四表键集一致且 17 键、无意外占位符
# ③ 新 .m 的 import 头文件闭环（文件存在于仓内）
# ④ CMakeLists 已登记 ZL2PluginRepoViewController.m + 伞头已挂
# ⑤ 权限 id 注册表对照（manifest 声明 ⊆ AmePluginPermissions 注册表）
import os, re, sys, json

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

# ── ① builtin-plugins 资源完备性 ────────────────────────
root = os.path.join(NAT, 'resources', 'builtin-plugins')
expect_ids = {'theme-sunset', 'renderer-quickswitch', 'launch-counter', 'modrinth-hot'}
try:
    dirs = set(d for d in os.listdir(root) if not d.startswith('.'))
except FileNotFoundError:
    dirs = set()
check('builtin-plugins dirs == 4 expected', dirs == expect_ids, f'got {sorted(dirs)}')

perm_src = open(os.path.join(NAT, 'AmePluginPermissions.m'), encoding='utf-8').read()
perm_registry = set(re.findall(r'initWithId:@"([a-z0-9._]+)"', perm_src))
check('perm registry parsed non-empty', len(perm_registry) >= 11, f'got {sorted(perm_registry)}')

for pid in sorted(expect_ids):
    mpath = os.path.join(root, pid, 'manifest.json')
    jpath = os.path.join(root, pid, 'main.js')
    check(f'{pid}/manifest.json exists', os.path.isfile(mpath))
    check(f'{pid}/main.js exists', os.path.isfile(jpath))
    if not (os.path.isfile(mpath) and os.path.isfile(jpath)):
        continue
    try:
        m = json.load(open(mpath, encoding='utf-8'))
    except Exception as e:
        check(f'{pid} manifest.json parses', False, str(e)); continue
    check(f'{pid} id == dir', m.get('id') == pid, f'manifest id={m.get("id")}')
    check(f'{pid} id regex', re.fullmatch(r'[a-z0-9][a-z0-9._-]{2,63}', m.get('id', '')) is not None)
    for field in ('name', 'version', 'entry'):
        check(f'{pid} {field} non-empty', bool(m.get(field)))
    check(f'{pid} entry == main.js', m.get('entry') == 'main.js')
    check(f'{pid} minApi == 1', m.get('minApi') == 1)
    perms = m.get('permissions') or []
    check(f'{pid} permissions subset of registry', set(perms) <= perm_registry,
          f'unknown={sorted(set(perms) - perm_registry)}')
    js = open(jpath, encoding='utf-8').read()
    check(f'{pid} main.js guards ame facade', 'typeof ame' in js)
    check(f'{pid} main.js non-trivial', len(js) > 500)

# ── ② ame318 四表键集 ───────────────────────────────────
langs = {}
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    langs[lang] = open(os.path.join(NAT, 'resources', f'{lang}.lproj', 'Localizable.strings'),
                       encoding='utf-8').read()
keysets = {}
for lang, txt in langs.items():
    keysets[lang] = set(re.findall(r'"(ame318\.[a-zA-Z0-9_.-]+)"\s*=', txt))
base = keysets['en']
check('ame318 keyset size == 17', len(base) == 17, f'got {len(base)}')
need_ui = {
    'ame318.repo.title', 'ame318.repo.nav', 'ame318.repo.entry_subtitle',
    'ame318.repo.section_title', 'ame318.repo.empty', 'ame318.repo.install',
    'ame318.repo.installing', 'ame318.repo.reinstall_body', 'ame318.repo.zip_failed',
}
need_builtin = set()
for pid in expect_ids:
    need_builtin.add(f'ame318.builtin.{pid}.name')
    need_builtin.add(f'ame318.builtin.{pid}.desc')
check('ame318 ui keys present', need_ui <= base, f'missing={sorted(need_ui - base)}')
check('ame318 builtin keys present', need_builtin <= base, f'missing={sorted(need_builtin - base)}')
for lang in ['zh-Hans', 'zh-CN', 'zh-Hant']:
    check(f'ame318 keyset {lang} == en', keysets[lang] == base,
          f'diff={base ^ keysets[lang]}')
# 本轮 ame318 键全部无占位符（若加占位符键须在此登记参数个数）
for key in sorted(base):
    m = re.search(r'"%s"\s*=\s*"((?:[^"\\]|\\.)*)"' % re.escape(key), langs['en'])
    val = m.group(1) if m else ''
    got = len(re.findall(r'%[@dlsu]', val))
    check(f'placeholder {key}==0', got == 0, f'got {got}: {val[:60]}')

# ── ③ import 闭环 ───────────────────────────────────────
new_ms = ['ZL2PluginRepoViewController.m']
natives_files = set()
for r, _, fs in os.walk(NAT):
    if 'Preview' in r: continue
    for f in fs: natives_files.add(f)
for f in new_ms:
    src = open(os.path.join(NAT, f), encoding='utf-8').read()
    for imp in re.findall(r'#import\s+"([^"]+)"', src):
        ok = imp in natives_files
        check(f'{f} import {imp}', ok)

# ── ④ CMake + 伞头登记 ──────────────────────────────────
cm = open(os.path.join(NAT, 'CMakeLists.txt'), encoding='utf-8').read()
for f in new_ms:
    check(f'CMake has {f}', f in cm)
kit = open(os.path.join(NAT, 'AmePluginKit.h'), encoding='utf-8').read()
check('AmePluginKit.h umbrella has repo VC', 'ZL2PluginRepoViewController.h' in kit)

print()
print(f'FAILURES: {len(fails)}')
sys.exit(1 if fails else 0)
