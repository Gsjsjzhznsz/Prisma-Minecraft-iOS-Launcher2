#!/usr/bin/env python3
# Task333 综合静态自查
# A 行基类 init 文本落位（空白卡根修）
# B 引导安装 + 官方仓信任面（bootstrap/heal 面扩展/ame.super 永不代授）
# C ame.super 完全接管（注册表/桥闸/详情页变灰）
# D 上仓迁移资产（bundle=survey / plugin-repo index+zip sha 一致 / theme-sunset 1.2.0+ui.dialog）
# E SDL 现读几何（live out/热栏/内容原点/抓取态/宣告三连/取证 live-legacy）
# F i18n 键面（ame.super + ame333.repo.* 四表一致）
import json, hashlib, os, re

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

def read(p):
    return open(os.path.join(REPO, p), encoding='utf-8').read()

# ── A 行基类 init 文本落位 ──────────────────────────────
cards = read('Natives/ZL2SettingCards.m')
check('A1 base init writes titleLabel.text', 'self.titleLabel.text = _title;' in cards)
check('A2 base init writes subtitleLabel.text', 'self.subtitleLabel.text = _subtitle;' in cards)
check('A3 Task333 anchor comment', 'Task333' in cards)

# ── B 引导安装 + 官方仓信任面 ────────────────────────────
rt = read('Natives/AmePluginRuntime.m')
check('B1 bootstrap fn exists', 'ame333_bootstrapBundleBuiltins' in rt)
_b = rt.find('+ (void)bootIfNeeded {')
check('B2 bootstrap called before heal (in bootIfNeeded)',
      _b >= 0
      and rt.find('ame333_bootstrapBundleBuiltins];', _b) >= 0
      and rt.find('ame333_bootstrapBundleBuiltins];', _b) < rt.find('ame326_healFirstPartyGrants];', _b))
check('B3 official cache path', '.repo-official.json' in rt)
check('B4 noteRepoOfficialIndex impl', '+ (void)noteRepoOfficialIndex:' in rt)
check('B5 heal face = bundle ∪ official', 'official.allKeys' in rt)
check('B6 heal never grants ame.super',
      '[p isEqualToString:@"ame.super"]' in rt
      and rt.count('ame.super') >= 5)
check('B7 heal preserves extra user grants',
      'for (NSString *k in cur)' in rt
      and 'if ([cur[k] boolValue] && g[k] == nil) g[k] = @1;' in rt)
h = read('Natives/AmePluginRuntime.h')
check('B8 noteRepoOfficialIndex declared in .h', 'noteRepoOfficialIndex:' in h)

# ── C ame.super 完全接管 ────────────────────────────────
perm = read('Natives/AmePluginPermissions.m')
check('C1 ame.super in registry', 'initWithId:@"ame.super"' in perm)
bridge = read('Natives/AmePluginBridge.m')
check('C2 bridge bypass first line', 'pluginHasGrant:self.pluginId permission:@"ame.super"' in bridge
      and bridge.find('ame.super takeover grant') < bridge.find('declaredPermissions containsObject:perm'))
detail = read('Natives/ZL2PluginDetailViewController.m')
check('C3 detail super toggle always interactive', 'ame333_isSuper' in detail and 'ame333_superGranted' in detail)
check('C4 detail grey-out alpha', '0.35' in detail and '0.45' in detail)

# ── D 上仓迁移资产 ─────────────────────────────────────
builtin_root = os.path.join(NAT, 'resources', 'builtin-plugins')
try:
    dirs = sorted(d for d in os.listdir(builtin_root) if not d.startswith('.'))
except FileNotFoundError:
    dirs = []
check('D1 bundle builtin == survey+fluent-ui (Task338)', dirs == ['fluent-ui', 'plugin-survey'], f'got {dirs}')
repo_src = os.path.join(REPO, 'plugin-repo', 'src')
src_dirs = sorted(d for d in os.listdir(repo_src) if not d.startswith('.'))
check('D2 repo src == 4 migrated',
      src_dirs == ['launch-counter', 'modrinth-hot', 'renderer-quickswitch', 'theme-sunset'],
      f'got {src_dirs}')
idx_path = os.path.join(REPO, 'plugin-repo', 'index.json')
idx = json.load(open(idx_path, encoding='utf-8'))
check('D3 index schema 1', idx.get('schema') == 1)
check('D4 index 4 plugins', len(idx.get('plugins', [])) == 4)
byid = {p['id']: p for p in idx['plugins']}
check('D5 all official=true', all(p.get('official') is True for p in idx['plugins']))
for pid, p in sorted(byid.items()):
    zpath = os.path.join(REPO, 'plugin-repo', p['file'])
    ok = os.path.isfile(zpath)
    check(f'D6 {pid} zip exists', ok)
    if ok:
        data = open(zpath, 'rb').read()
        sha = hashlib.sha256(data).hexdigest()
        check(f'D7 {pid} sha256 match', sha == p['sha256'])
        check(f'D8 {pid} size match', len(data) == p['size'])
        with __import__('zipfile').ZipFile(zpath) as z:
            names = z.namelist()
        check(f'D9 {pid} manifest at zip root', 'manifest.json' in names)
ts = json.load(open(os.path.join(repo_src, 'theme-sunset', 'manifest.json'), encoding='utf-8'))
check('D10 theme-sunset 1.2.0', ts.get('version') == '1.2.0')
check('D11 theme-sunset declares ui.dialog', 'ui.dialog' in ts.get('permissions', []))
repo_m = read('Natives/ZL2PluginRepoViewController.m')
check('D12 repo VC remote fetch', 'ame333_fetchRemoteIndex' in repo_m)
check('D13 repo VC sha256 gate', 'ame333_sha256OfStringData' in repo_m and 'sha256 mismatch' in repo_m.lower() or 'sha_mismatch' in repo_m)
check('D14 repo VC official heal at install', 'official plugin grants healed at install' in repo_m)
check('D15 mirror pref persisted', 'ame333.plugin.repo.mirror' in repo_m)
check('D16 three mirror bases', repo_m.count('https://') >= 3 and 'jsdelivr' in repo_m and 'ghfast' in repo_m)
check('D17 noteRepoOfficialIndex called on fetch', '[AmePluginRuntime noteRepoOfficialIndex:' in repo_m)

# ── E SDL 现读几何 ─────────────────────────────────────
sv = read('Natives/SurfaceViewController.m')
check('E1 live out fn defined', '- (CGPoint)ame333_liveCursorOutScale' in sv)
check('E2 both consumers switched to live',
      'CGPoint ame277_out = [self ame333_liveCursorOutScale];' in sv
      and 'CGPoint ame333_out = [self ame333_liveCursorOutScale];' in sv)
check('E3 legacy kept for forensic', 'ame333_legacyOut' in sv)
check('E4 forensic live/legacy both logged',
      'live=%.3fx%.3f legacy=%.3fx%.3f' in sv)
check('E5 hotbar live (physical/bounds)',
      '(CGFloat)physicalWidth / ame333_cw' in sv)
check('E6 content origin live', 'self.surfaceView.frame.origin' in sv)
check('E7 announce trio t+0.8/t+2.5',
      '(int64_t)(0.8 * NSEC_PER_SEC)' in sv and '(int64_t)(2.5 * NSEC_PER_SEC)' in sv
      and sv.count('announce trio') >= 2)
check('E8 grab-state DOWN live', 'ame333_out.x' in sv)

# ── F i18n 键面 ───────────────────────────────────────
need = ['ame317.perm.ame.super.name', 'ame317.perm.ame.super.desc',
        'ame333.repo.section_remote', 'ame333.repo.section_builtin',
        'ame333.repo.fetching', 'ame333.repo.fetch_fail',
        'ame333.repo.fetch_empty', 'ame333.repo.install',
        'ame333.repo.update', 'ame333.repo.sha_mismatch']
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    txt = read(f'Natives/resources/{lang}.lproj/Localizable.strings')
    keys = set(re.findall(r'^"([^"]+)"\s*=', txt, re.M))
    check(f'F1 {lang} all 10 Task333 keys', set(need) <= keys,
          f'missing={sorted(set(need) - keys)}')
    check(f'F2 {lang} unique keys == 3316 (Task338: +fluent-ui name/desc)', len(keys) == 3316, f'got {len(keys)}')

print()
if fails:
    print(f'FAILURES: {len(fails)}')
    for f in fails: print('  -', f)
    raise SystemExit(1)
print('ALL GREEN')
