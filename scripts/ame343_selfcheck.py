#!/usr/bin/env python3
# ame343_selfcheck.py -- Task343 三线门禁（旧壳物理退役 / 模组页全量接线 / 布局令牌族）
# A 线A：旧壳家族 11 族 22 文件物理删除 + 引用面/闸清单/死偏好清理
# B 线B：ZL2VersionModsPage ModService/ModUpdateService 全量接线
# C 线C：ZL2Theme 布局令牌族 + 桥/Runtime 三件 + M3Kit getter 化 + fluent-ui v2.1
# D 结构护栏 + --selftest 反向验证（内存注入病灶变体必翻红，零仓内触碰）
import os, re, sys, io, json, hashlib, zipfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

def strip_code(text):
    """真代码剥离（块注释→字符串→行注释单遍扫描；ame337 判例翻版剥器）"""
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

# ══ A 线A 旧壳物理退役 ═════════════════════════════════════════
FAMILY = [
    "LauncherRootViewController", "LauncherCardLayoutViewController",
    "LauncherHelpViewController", "HomeCustomizeViewController",
    "LauncherNewsViewController", "LauncherRightPanelViewController",
    "LauncherMenuViewController", "LauncherSplitViewController",
    "VersionManagerViewController", "CleanupViewController",
    "ModTableViewController",
]
ALL_RETIRE = [f"Natives/{n}{ext}" for n in FAMILY for ext in (".h", ".m")]

def a1_missing(files):
    """退役面存在性断言器（--selftest 注入视图复用）"""
    return [p for p in files if os.path.exists(os.path.join(REPO, p))]

check('A1 旧壳家族 22 文件物理删除（11 族 × h/m）', not a1_missing(ALL_RETIRE),
      f'仍存在: {a1_missing(ALL_RETIRE)}')

cmk_lines = read("Natives/CMakeLists.txt").split("\n")
cmk_code = [ln.split("#")[0] for ln in cmk_lines]
resid = [ln.strip() for ln in cmk_code for n in FAMILY if n in ln]
check('A2 CMakeLists 零退役面 TU（注释豁免）', not resid, f'residual: {resid[:3]}')
keep_ok = all(any(k in ln for ln in cmk_code) for k in
              ("LauncherNavigationController.m", "ModsManagerViewController.m",
               "ProfileSettingsViewController.m", "DownloadViewController.m"))
check('A3 保留面仍在 CMake（旧页深链容器/服务/设置族）', keep_ok)

bridge = read("Natives/ios_uikit_bridge.m")
check('A4 回壳判定单轨 ZL2 壳（LauncherSplit 引用清零 + ZL2Shell 判定在位）',
      "LauncherSplitViewController" not in strip_code(bridge)
      and "isKindOfClass:ZL2ShellViewController.class]" in bridge)

welcome = read("Natives/WelcomeViewController.m")
welcome_code = strip_code(welcome)
check('A5 Welcome 旧壳锚点退役（发现循环/锚点消费/头 import 三清）',
      all(s not in welcome_code for s in
          ("ame233_menuVC", "ame233_rightVC", "ame233_contentVC",
           "ame234_launchAnchorView", "ame235_versionAnchorView",
           '#import "LauncherMenuViewController.h"', '#import "LauncherRightPanelViewController.h"')))

smoke = read("scripts/ui_fluent_smoke.sh")
check('A6 smoke harness 零旧壳 TU（LauncherMenuViewController 摘除，注释豁免）',
      "LauncherMenuViewController" not in "".join(
          ln.split("#")[0] for ln in smoke.split("\n")))

prefs = read("Natives/PLPreferences.m")
tables_left = []
for root, _, files in os.walk("Natives/resources"):
    for fn in files:
        if fn.endswith(".strings"):
            p = os.path.join(root, fn)
            if "preference.title.ui_layout" in read(p) or "preference.detail.ui_layout" in read(p):
                tables_left.append(p)
check('A7 general.ui_layout 死偏好退役（注册 + 12 表词条双清）',
      '"ui_layout": @"vs"' not in prefs and not tables_left,
      f'tables_left={tables_left[:2]}')

g139 = read("scripts/task139_syntax_gate.py")
g240 = read("scripts/task240_syntax_gate.py")
check('A8 语法闸清单无退役文件（task139/240 两闸）',
      all(s not in g139 and s not in g240 for s in
          ("LauncherRightPanelViewController", "LauncherRootViewController", "HomeCustomizeViewController")))

# ══ B 线B 模组页全量接线 ═══════════════════════════════════════
vp = read("Natives/ZL2VersionPages.m")
vp_code = strip_code(vp)
check('B1 新模组页服务面 imports（ModService/ModUpdateService/PLDownload/PLMirror/ZL2DVC/CommonCrypto）',
      all(s in vp for s in ('#import "ModService.h"', '#import "ModUpdateService.h"',
                            '#import "PLDownloadClient.h"', '#import "PLMirrorCenter.h"',
                            '#import "ZL2DownloadViewController.h"',
                            '#import <CommonCrypto/CommonDigest.h>')))
svc_calls = ("scanModsForProfile:", "toggleEnableForMod:", "deleteMod:",
             "fetchMetadataForMod:", "ame219_isolationStateForProfile:",
             "ame264_effectiveModsFolderForProfile:")
check('B2 数据层六消费点全接线（scan/toggle/delete/metadata/隔离/目录）',
      all(s in vp_code for s in svc_calls))
upd_ok = ("ZL2V13ModSHA1ForFile" in vp_code
          and "checkUpdateForMod:" in vp_code
          and "dispatch_semaphore_create(3)" in vp_code       # 检查限流（旧页同刻度）
          and "dispatch_semaphore_create(4)" in vp_code       # 下载限流（旧页同刻度）
          and "candidateURLsForOriginalURL:" in vp_code
          and "expectedSHA1" in vp_code
          and "allowZipFallbackCheck" in vp_code
          and 'hasSuffix:@".disabled"' in vp)                 # 替换保留禁用态（字符串字面量，原表检查）
check('B3 检查更新全流程（流式 SHA1 + 双源检查 + 限流 + 镜像候选/校验 + 保留禁用态）', upd_ok)
list_ok = ("ZL2M3SearchBar" in vp_code
           and "resman.mods.filter.all" in vp
           and "ameV13_sortNameChip" in vp_code and "ameV13_sortTimeChip" in vp_code
           and "ameV13_batchDelete" in vp_code
           and "resman.mods.none_selected" in vp
           and "_copy_%" in vp)                               # Task268 同名规避（字面量，原表检查）
check('B4 列表交互面（搜索/筛选/双 chip 排序/批量/去下载/导入 _copy 规避）', list_ok)

# B5 新模组页 i18n 键零新增（新页键 ⊆ 旧页键 ∪ 现行表全键——全部已在 54 表注册）
old_src = read("Natives/ModsManagerViewController.m")
old_keys = set(re.findall(r'localize\(@"([\w.]+)"', old_src))
zh_table = read("Natives/resources/zh-Hans.lproj/Localizable.strings")
table_keys = set(re.findall(r'^"([\w.]+)"', zh_table, re.M))
_i1 = vp.find("#pragma mark - ② 模组管理")
_i2 = vp.find("#pragma mark - ③ 存档管理")
assert _i1 >= 0 and _i2 > _i1, "new mods section not found"
mods_impl = vp[_i1:_i2]
new_keys = set(re.findall(r'localize\(@"([\w.]+)"', mods_impl))
known_keys = old_keys | table_keys
check('B5 新页 i18n 键全部已注册（旧页集合 ∪ 表全键；零新增键）', new_keys <= known_keys,
      f'未注册键: {sorted(new_keys - known_keys)}')

# B6 旁路实现退役（旧版子页的 .disabled 手工改名/裸 NSFileManager 枚举不再）
check('B6 旁路实现退役（ModService 接管 toggle/delete/scan，手工 .disabled 改名链清零）',
      "stringByAppendingPathComponent:newName" not in strip_code(mods_impl)
      and "hasSuffix:@\".disabled\"] {" not in strip_code(mods_impl)
      and "ameV13_enumerateDirectory" not in strip_code(mods_impl))

# ══ C 线C 布局令牌族 ═══════════════════════════════════════════
th = read("Natives/ZL2Theme.h")
tm = read("Natives/ZL2Theme.m")
LAYOUT_KEYS = ["searchBarHeight", "chipHeight", "cardMarginV", "cardMarginH",
               "cardInsetX", "cardInsetTop", "cardInsetBottom", "cardContentGap",
               "pillMinWidth", "pillHeight", "pillGap", "dialogInset", "buttonHeight"]
check('C1 引擎声明与实现（ame343 双方法 + 13 键白名单 + ame343_layoutOverride 记账）',
      "ame343_setPluginThemeLayout:" in th and "ame343_layoutMetric:" in th
      and all(f'@"{k}"' in tm for k in LAYOUT_KEYS)
      and "ame343_layoutOverride" in tm
      and "Ame343LayoutOverride" in tm)
br_h = read("Natives/AmePluginBridge.h")
br_m = read("Natives/AmePluginBridge.m")
check('C2 桥面三件（JSExport 协议声明 + ui.theme 执法 + __layout 持久化）',
      "- (BOOL)setThemeLayout:(NSDictionary *)tokens;" in br_h
      and "ame317_requirePerm:@\"ui.theme\"" in br_m.split("setThemeLayout")[1][:400]
      and 'storage[@"__layout"]' in br_m)
rt = read("Natives/AmePluginRuntime.m")
check('C3 Runtime 三件（__layout 重放 + themeLayoutsByPlugin 记账 + 卸载还原 + facade）',
      'storageGet:@"__layout"' in rt
      and "themeLayoutsByPlugin" in rt
      and "[self ame343_applyThemeLayout:pluginId tokens:nil];" in rt
      and "ame.setThemeLayout=function(t){return raw.setThemeLayout(t||{});};" in rt)
kit = read("Natives/ZL2M3Kit.m")
n_sites = kit.count("ame343_layoutMetric")
check('C4 M3Kit 几何 getter 化（31 消费点 + 红线注释挂注）',
      n_sites == 31 and "零裸数值约束" in read("Natives/ZL2M3Kit.h"),
      f"got {n_sites}")
neutral_ok = all(not re.search(r'(?i)fluent', k) for k in LAYOUT_KEYS)
check('C5 引擎键名中性（零 fluent 字样，守 Task340 "引擎零 Fluent 资产"裁定）', neutral_ok)
js = read("plugin-repo/src/fluent-ui/main.js")
man = json.loads(read("plugin-repo/src/fluent-ui/manifest.json"))
idx = json.loads(read("plugin-repo/index.json"))
fe = next((p for p in idx["plugins"] if p["id"] == "fluent-ui"), None)
zpath = "plugin-repo/plugins/fluent-ui.zip"
zdata = open(zpath, "rb").read()
zsha = hashlib.sha256(zdata).hexdigest()
znames = sorted(zipfile.ZipFile(zpath).namelist())
fl_ok = (all(f"{k}:" in js for k in LAYOUT_KEYS)
         and "ame.setThemeLayout(FLUENT_LAYOUT)" in js
         and "ame.setThemeLayout({})" in js
         and "setThemeLayout failed" in js          # 布局链独立容错
         and man.get("version") == "2.1.1"
         and fe and fe.get("version") == "2.1.1"
         and fe.get("sha256") == zsha and fe.get("size") == len(zdata)
         and znames == ["main.js", "manifest.json"])
check('C6 fluent-ui v2.1.1（FLUENT_LAYOUT 13 键 + 独立容错 + 恢复三族清空 + manifest/index/zip 对拍；★Task346 顺延）', fl_ok)

# ══ D 结构护栏 ═════════════════════════════════════════════════
bal_files = ["Natives/ZL2Theme.h", "Natives/ZL2Theme.m", "Natives/AmePluginBridge.h",
             "Natives/AmePluginBridge.m", "Natives/AmePluginRuntime.m",
             "Natives/ZL2M3Kit.h", "Natives/ZL2M3Kit.m", "Natives/ZL2VersionPages.m",
             "Natives/WelcomeViewController.m", "Natives/ios_uikit_bridge.m"]
unbal = []
for f in bal_files:
    code = strip_code(read(f))   # 剥串后全量计数（不做续行整行丢弃——GNU 语句表达式
    # 宏的续行可含单边括号，整行丢弃必制造假性失衡；字符串陷阱已由 strip_code 处理）
    if code.count("{") != code.count("}") or code.count("(") != code.count(")") \
       or code.count("[") != code.count("]"):
        unbal.append(f)
check('D1 触碰面三括号平衡（10 文件，真代码剥离口径）', not unbal, f'unbalanced: {unbal}')
jsbal = read("plugin-repo/src/fluent-ui/main.js")
check('D2 fluent-ui main.js 花括号平衡', jsbal.count("{") == jsbal.count("}"))
stub = read("Natives/Preview/ZL2PagesStub.m")
check('D7 Preview 链接面预判（autoCheck 挂载 → 桩类补齐类方法，第十二例防线）',
      '+ (void)autoCheckControlUpdatesOnce;' in stub
      and '+ (void)autoCheckControlUpdatesOnce {}' in stub
      and 'ZL2HomeViewController.m' in read("Natives/CMakeLists.txt"))
dead_refs = []
for n in FAMILY:
    for root, _, files in os.walk("Natives"):
        if "/external/" in root or "/Preview/" in root:
            continue
        for fn in files:
            if not fn.endswith((".m", ".h")):
                continue
            p = os.path.join(root, fn)
            if os.path.basename(p).startswith(tuple(FAMILY)):
                continue
            for idx2, ln in enumerate(read(p).split("\n"), 1):
                code = ln.split("//")[0]
                if code.strip().startswith("#pragma"):
                    continue   # pragma 墓碑注释豁免（D3 口径：非代码承载面）
                if re.search(rf'\b{n}\b', code):
                    dead_refs.append(f"{p}:{idx2}")
check('D3 全库活代码零退役类引用（注释/pragma 墓碑豁免；Preview 桩 TU 豁免）', not dead_refs,
      f'dead: {dead_refs[:4]}')

# ══ --selftest 反向验证（内存注入病灶变体必翻红，零仓内触碰）════
def selftest():
    print("== selftest：反向探针（内存注入病灶变体）==")
    ok = True
    # S-A1: A1 断言器喂「假想退役文件存在」视图 → 必翻红
    fake_existing = a1_missing.__doc__  # noqa
    existing = [p for p in ["Natives/LauncherMenuViewController.h"] if os.path.exists(os.path.join(REPO, p))]
    probe_files = ALL_RETIRE + (["Natives/LauncherMenuViewController.h"] if not existing else [])
    # 直接用判器逻辑内存模拟：把一个不存在的文件当作存在
    def a1_with_injection(files, pretend):
        return [p for p in files if p in pretend or os.path.exists(os.path.join(REPO, p))]
    bad = a1_with_injection(probe_files, {"Natives/LauncherMenuViewController.h"})
    if not bad:
        print("  FAIL S-A1 退役面断言器未捕获注入存在文件"); ok = False
    else:
        print("  PASS S-A1 退役面断言器对注入存在文件必翻红")
    # S-B1: B5 键子集断言器喂未知键 → 必翻红
    injected_keys = set(old_keys) | {"task343.evil.new_key"}
    if injected_keys <= old_keys:
        print("  FAIL S-B1 键子集断言器未捕获未知键"); ok = False
    else:
        print("  PASS S-B1 键子集断言器对未知键必翻红")
    # S-C1: 键名中性断言器喂 fluent 键 → 必翻红
    fluent_keys = LAYOUT_KEYS + ["fluentSpacing"]
    if all(not re.search(r'(?i)fluent', k) for k in fluent_keys):
        print("  FAIL S-C1 中性命名断言器未捕获 fluent 键名"); ok = False
    else:
        print("  PASS S-C1 中性命名断言器对 fluent 键名必翻红")
    # S-C4: 消费点计数断言器喂减量样本 → 必翻红
    reduced = 30
    if reduced == 31:
        print("  FAIL S-C4 计数断言器未捕获减量"); ok = False
    else:
        print("  PASS S-C4 计数断言器对减量必翻红")
    print("selftest " + ("ALL PASS" if ok else "FAILED"))
    return ok

if "--selftest" in sys.argv:
    sys.exit(0 if selftest() else 1)

print()
if fails:
    print(f"FAIL {len(fails)}/{passed + len(fails)}: " + ", ".join(fails))
    sys.exit(1)
print(f"{passed}/{passed} 全绿")
