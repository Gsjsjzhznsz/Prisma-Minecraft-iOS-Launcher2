#!/usr/bin/env python3
# Task339 自检电池 —— 四线：
#   A 进世界后切不了分辨率（自绘分辨率面板根修 UI 面：actionSheet 退役）
#   B fluent-ui 插件外置（builtin 移除 → plugin-repo 远程仓库 + index.json）
#   C Fluent 2 / Apple 官方重设计（AMEFluentTheme 令牌层 + 主页换装）
#   D 结构护栏（文件清单 / 断言漂移 / TU 编译面闭环）
# 惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
import hashlib, json, os, re, sys, zipfile

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

fails, passed = [], 0
def check(name, ok, detail=''):
    global passed
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if ok:
        passed += 1
    else:
        fails.append(name)

def read(rel):
    with open(os.path.join(REPO, rel), encoding='utf-8') as f:
        return f.read()

def strip_code(src):
    """自持真代码剥离（337 判例：括号平衡剥器只保留括号 = 假阳性；用注释/字符串全剥）。"""
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    return src

# ── 读面 ─────────────────────────────────────────────────────
nav = read('Natives/SurfaceViewController+Navigation.m')
svc = read('Natives/SurfaceViewController.m')
home = read('Natives/ZL2HomeViewController.m')
ft_h = read('Natives/AMEFluentTheme.h')
ft_m = read('Natives/AMEFluentTheme.m')
cmk = read('Natives/CMakeLists.txt')
smoke = read('scripts/ui_fluent_smoke.sh')
s318 = read('scripts/ame318_selfcheck.py')
s338 = read('scripts/ame338_selfcheck.py')
index_json = json.loads(read('plugin-repo/index.json'))

if '--selftest' in sys.argv:
    print('== ame339 selftest（反向验证：内存注入病灶，必翻红）==')
    inj_nav = nav.replace('- (void)ame339_resOptionTouched:', '- (void)ame339_resOptionTouched_disabled:')
    inj_nav2 = nav.replace('[self ame328_applyResolutionInSession:(float)value / 100.0]', '')
    bad = 0
    # S-A2: 面板方法被禁用 -> A2 探针必翻红
    ok_a2 = ('- (void)ame339_resOptionTouched:' in inj_nav)
    if ok_a2:
        print('S-A2 未翻红（面板方法探针失效）'); bad += 1
    else:
        print('ok  S-A2 反向：面板方法禁用 -> FAIL（符合预期）')
    # S-A3: 会话内生效链被摘 -> A3 探针必翻红
    inj2_code = strip_code(inj_nav2)
    ok_a3 = ('ame328_applyResolutionInSession' in inj2_code)
    if ok_a3:
        print('S-A3 未翻红（生效链探针失效）'); bad += 1
    else:
        print('ok  S-A3 反向：生效链摘除 -> FAIL（符合预期）')
    # S-C2: 主页回潜 ZL2Theme
    inj_home = home.replace('[AMEFluentTheme brand]', '[ZL2Theme primary]', 1)
    ok_c2 = not re.search(r'\[ZL2Theme \w+\]', inj_home) is None
    if not ok_c2:
        print('S-C2 未翻红（主页令牌探针失效）'); bad += 1
    else:
        print('ok  S-C2 反向：主页回潜 ZL2Theme -> FAIL（符合预期）')
    # S-B3: index.json sha256 与 zip 实算不符
    import tempfile
    tmp = json.loads(json.dumps(index_json))
    for p in tmp['plugins']:
        if p.get('id') == 'fluent-ui':
            p['sha256'] = '0' * 64
    zp = os.path.join(REPO, 'plugin-repo/plugins/fluent-ui.zip')
    real = hashlib.sha256(open(zp, 'rb').read()).hexdigest()
    ent = next(p for p in tmp['plugins'] if p.get('id') == 'fluent-ui')
    ok_b3 = (ent['sha256'] != real)
    if not ok_b3:
        print('S-B3 未翻红（zip 完整性探针失效）'); bad += 1
    else:
        print('ok  S-B3 反向：sha256 篡改 -> FAIL（符合预期）')
    print(f'selftest: {"FAIL " + str(bad) + " probes failed to trigger" if bad else "4/4 反向探针全翻红"}')
    sys.exit(1 if bad else 0)

# ══ A 线A 分辨率自绘面板 ═══════════════════════════════════════
nav_code = strip_code(nav)
action_res = re.search(r'- \(void\)actionAdjustResolution \{.*?\n\}', nav, re.S)
a1 = action_res.group(0) if action_res else ''
check('A1 actionAdjustResolution 退役 actionSheet（不再走 ame240 present）',
      bool(a1) and 'ame240_presentMenuWithTitle' not in a1 and 'UIAlertController' not in a1,
      '旧 actionSheet 路径仍残留于 actionAdjustResolution')
check('A2 自绘面板四件套',
      'kAme339ResPanelKey' in nav
      and '- (void)ame339_dismissResolutionPanel' in nav
      and '- (void)ame339_resOptionTouched:' in nav
      and 'resolution panel presented' in nav,
      '自绘面板方法族缺失')
check('A3 应用链 1:1 保留（profile 写入 + 会话内生效 + 兼容镜像 + Toast）',
      'ame328_applyResolutionInSession' in nav_code
      and 'PLProfiles.current.profiles[ame186_profileName] = ame186_profile;' in nav_code
      and 'setPrefFloat(@"video.resolution", (float)value)' in nav
      and 'NMToast showMessage:' in nav_code,
      '应用链断件')
check('A4 取证日志三连', 'resolution panel presented' in nav
      and 'resolution option selected' in nav
      and 'resolution apply result' in nav,
      '取证日志缺失')
check('A7 NSInteger 点语法退役（r0 热修判例：value 由 NSNumber 改 NSInteger 后 .floatValue 必炸）',
      'value.floatValue' not in nav and '(float)value / 100.0' in nav
      and 'setPrefFloat(@"video.resolution", (float)value)' in nav,
      'NSInteger 上仍有 floatValue 点语法')
langs_13 = ('zh-Hans', 'zh-CN', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'pt-BR', 'ru', 'km')
i18n_missing = [l for l in langs_13
                if 'game.menu.resolution.current' not in read(f'Natives/resources/{l}.lproj/Localizable.strings')]
check('A5 i18n 新键 13 表齐（game.menu.resolution.current）', not i18n_missing, f'missing: {i18n_missing}')
m338 = re.search(r'Task338（非SDL 调节分辨率"不迅速 \+ 黑块"根修）.*?\n\}', svc, re.S)
check('A6 338 两段式链未被破坏（announce-first 五件套仍在）',
      bool(m338) and 'isUseStackQueueCall && isInputReady' in m338.group(0)
      and 'g_ame338_pendingResCommit = YES;' in m338.group(0)
      and '2.0 * NSEC_PER_SEC' in m338.group(0),
      '338 两段式被本轮改动破坏')

# ══ B 线B fluent-ui 外置 ═══════════════════════════════════════
builtin_dir = os.path.join(REPO, 'Natives/resources/builtin-plugins')
builtin_ids = set(d for d in os.listdir(builtin_dir) if not d.startswith('.'))
check('B1 builtin 收敛（无 fluent-ui）', builtin_ids == {'plugin-survey'}, f'got {sorted(builtin_ids)}')
src_ok = (os.path.isfile(os.path.join(REPO, 'plugin-repo/src/fluent-ui/manifest.json'))
          and os.path.isfile(os.path.join(REPO, 'plugin-repo/src/fluent-ui/main.js')))
check('B2 plugin-repo/src/fluent-ui 两文件齐', src_ok)
zp = os.path.join(REPO, 'plugin-repo/plugins/fluent-ui.zip')
zip_ok, real_sha, real_size = False, '', 0
names = []
if os.path.isfile(zp):
    real_size = os.path.getsize(zp)
    real_sha = hashlib.sha256(open(zp, 'rb').read()).hexdigest()
    with zipfile.ZipFile(zp) as z:
        names = sorted(z.namelist())
    zip_ok = names == ['main.js', 'manifest.json']
check('B3 zip 结构与存在性（根直接两文件）', zip_ok, f'names={names}')
ent = next((p for p in index_json.get('plugins', []) if p.get('id') == 'fluent-ui'), None)
check('B4 index.json 条目全字段 + 完整性一致',
      bool(ent) and ent.get('file') == 'plugins/fluent-ui.zip'
      and ent.get('official') is True and ent.get('version') == '1.0.0'
      and ent.get('sha256') == real_sha and ent.get('size') == real_size,
      f'sha/size mismatch or entry missing')
check('B5 旧电池演进同步（ame318 收敛断言 + ame338 repo 路径）',
      "{'plugin-survey'}" in s318 and "plugin-repo/src/fluent-ui/manifest.json" in s338,
      '旧电池断言未随外置演进')

# ══ C 线C Fluent 2 / Apple 重设计 ══════════════════════════════
check('C1 AMEFluentTheme 令牌核心（brand 双态 + Neutral + ramp + 圆角栅格）',
      '0x0F/255.0 green:0x6C/255.0 blue:0xBD' in ft_m
      and '0x4C/255.0 green:0xC2/255.0 blue:0xFF' in ft_m
      and 'colorWithDynamicProvider' in ft_m
      and '+ (CGFloat)radiusCard    { return 8.0; }' in ft_m
      and '+ (CGFloat)radiusControl { return 4.0; }' in ft_m
      and '+ (CGFloat)spacingM   { return 16.0; }' in ft_m
      and 'fontTitleLarge' in ft_h and 'fontCaption' in ft_h
      and 'applyCardShadow' in ft_h,
      '令牌核心缺件')
check('C2 主页换装（import AMEFluentTheme + 零 ZL2Theme 调用）',
      '#import "AMEFluentTheme.h"' in home and not re.search(r'\[ZL2Theme \w+\]', home),
      '主页仍引用 ZL2Theme')
home_code = strip_code(home)
check('C3 Fluent 化四件（卡 hairline+shadow8 / 选中 brand 2pt / 按压 brandShade / 三态 onBrand）',
      'applyCardShadow:_cardBody' in home_code
      and 'isSelected ? 2 : 1' in home_code
      and 'ame339_launchTouchDown' in home_code and 'brandShade' in home_code
      and 'AMEFluentTheme onBrand]' in home_code,
      'Fluent 化缺件')
check('C4 CMakeLists 登记新 TU', 'AMEFluentTheme.m' in cmk, 'CMakeLists 未登记')
check('C5 smoke 双口径演进（syntax 加 AMEFluentTheme.h + preview sources）',
      '"AMEFluentTheme\\.h"' in smoke and 'AmeTheme AMEFluentTheme' in smoke,
      'smoke 脚本未演进')

# ══ D 线D 结构护栏 ═════════════════════════════════════════════
check('D1 文件清单（新令牌层 + 外置插件源 + zip）',
      os.path.isfile(os.path.join(REPO, 'Natives/AMEFluentTheme.h'))
      and os.path.isfile(os.path.join(REPO, 'Natives/AMEFluentTheme.m'))
      and os.path.isfile(os.path.join(REPO, 'plugin-repo/src/fluent-ui/main.js'))
      and os.path.isfile(os.path.join(REPO, 'plugin-repo/plugins/fluent-ui.zip')),
      '文件缺件')
check('D2 断言漂移护栏（ame338 A1 两段式断言面未漂移）',
      r'Task338（非SDL 调节分辨率"不迅速 \+ 黑块"根修）' in s338,
      'ame338 断言面漂移')
check('D3 编译面闭环（主页 import 的 TU 均已在 CMakeLists）',
      'AMEFluentTheme.m' in cmk and 'ZL2HomeViewController.m' in cmk,
      'TU 编译面缺口')

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
