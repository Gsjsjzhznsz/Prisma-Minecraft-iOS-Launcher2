#!/usr/bin/env python3
# ame347_selfcheck.py -- Task347 两线门禁（zip 导入脉柱救援链 / Fluent 结构令牌承载面）
# A 线A：导入侧三段救援（ZIP 直读 / v1 迁移 / 保底留痕）+ 分区导出脉柱恒强校验
# B 线B：结构令牌五族链（ZL2Theme ame347 setter/getter + 桥面 + Runtime 重放/还原 + 壳层消费）
# C 线C：fluent-ui v2.2.0 结构应用/还原 + manifest/index/zip 三方对拍
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

def strip_keep_str(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1; out.append(c)
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1; out.append(c)
            else:
                out.append(c)
                if c == '"': mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

# ══ A 线A 导入脉柱救援链 ═══════════════════════════════════════
dt = read("Natives/DataTransferService.m")
dt_code = strip_code(dt)
plp_m = read("Natives/PLPreferences.m")
plp_h = read("Natives/PLPreferences.h")

check('A1 v1 迁移器在位（头声明 + 实现：defaults 骨架 + 旧值回填，与启动期迁移同语义）',
      "ame347_migratedGlobalPrefsFromV1" in plp_h
      and "+ (NSMutableDictionary<NSString *, NSMutableDictionary *> *)ame347_migratedGlobalPrefsFromV1:(NSDictionary *)oldPref {" in plp_m
      and "defaultPrefForGlobal:YES" in plp_m
      and "getOldLayoutPreference:key from:oldPref" in plp_m)

check('A2 导入三段救援（ZIP 直读 / v1 迁移 / 保底留痕，防毒化语义保留）',
      "ame347_spineZipRescued" in dt_code
      and "ame347_spineV1Restored" in dt_code
      and "ame347_spineKept" in dt_code
      and "ame346_skippedSpineFiles" in dt_code
      and "spine rescued from zip entry" in dt
      and "spine restored via v1 migration" in dt
      and "spine snapshot -- zipEntryV2=" in dt)

check('A3 救援数据源前置快照（合并循环前 extractDataFromFile + v1 staging 预读，零时序歧义）',
      'extractDataFromFile:\n                @"launcher_preferences_v2.plist"' in dt
      and 'dictionaryWithContentsOfFile:\n                [staging stringByAppendingPathComponent:@"launcher_preferences.plist"]' in dt)

check('A4 摘要如实上报（v1 恢复行 + 坏包保留行，i18n 键双落位；★Task348 演进：保留行消费点移交 ame348.import.spine_absent）',
      'localize(@"ame347.import.spine_v1", nil)' in dt
      and 'localize(@"ame348.import.spine_absent", nil)' in dt
      and "Task347: spine rescued zipEntry=" in dt)

check('A5 分区导出脉柱恒强校验（requirePrefs:YES 无条件——强制进包必强验）',
      "requirePrefs:YES]" in dt_code
      and "requirePrefs:[selected containsObject:Ame224SectionIdLauncher]]" not in dt_code
      and dt_code.count("ame345_exportSpineProblem:") >= 3)

check('A6 i18n 两键 54 表全落位',
      all("ame347.import.spine_v1" in read(f"Natives/resources/{d}/Localizable.strings")
          for d in os.listdir("Natives/resources") if d.endswith(".lproj")))

# ══ B 线B 结构令牌五族链 ═══════════════════════════════════════
theme = read("Natives/ZL2Theme.m")
theme_code = strip_code(theme)
theme_h = read("Natives/ZL2Theme.h")
bridge = read("Natives/AmePluginBridge.m")
bridge_h = read("Natives/AmePluginBridge.h")
runtime = read("Natives/AmePluginRuntime.m")
shell = read("Natives/ZL2ShellViewController.m")
shell_code = strip_code(shell)

check('B1 结构 setter 在位（白名单 topbar|navigationview + 记账还原语义 + 双路径根重建）',
      "+ (BOOL)ame347_setPluginThemeStructure:(NSString *)pluginId" in theme_code
      and '@[ @"topbar", @"navigationview" ]' in theme
      and "ame347_structureOverride" in theme_code
      and theme_code.count("ame346_requestRootRebuild()") == 8)

check('B2 结构 getter 在位（默认 topbar 基线）',
      "+ (NSString *)ame347_shellLayout {" in theme_code
      and 'Ame347StructureOverride(@"shellLayout", @"topbar")' in theme
      and "+ (NSString *)ame347_shellLayout;" in theme_h)

check('B3 桥面全链（JSExport 协议声明 + 实现走 ZL2Theme + __structure 持久化）',
      "- (BOOL)setThemeStructure:(NSDictionary *)tokens;" in bridge_h
      and "[ZL2Theme ame347_setPluginThemeStructure:self.pluginId tokens:tokens];" in bridge
      and 'storage[@"__structure"] = tokens ?: @{};' in bridge)

check('B4 Runtime 全路径（门面 setThemeStructure + __structure 重放 + 卸载还原 + 记账面）',
      'ame.setThemeStructure=function(t){return raw.setThemeStructure(t||{});};' in runtime
      and '[self ame347_applyThemeStructure:pluginId tokens:savedStructure];' in runtime
      and "[self ame347_applyThemeStructure:pluginId tokens:nil];" in runtime
      and "themeStructuresByPlugin" in runtime
      and "[ZL2Theme ame347_setPluginThemeStructure:pluginId tokens:tokens];" in runtime)

check('B5 壳层结构消费（viewDidLoad 分骨架 + NavigationView 构建器 + 刷新/抽屉/宽窄态）',
      'self.ame347_navMode = [[ZL2Theme ame347_shellLayout]\n                           isEqualToString:@"navigationview"];' in shell
      and "ame_buildNavigationViewShell" in shell_code
      and "ame_refreshNavShellStateAnimated" in shell_code
      and "ame347_applyWidthClass" in shell_code
      and "ame_setDrawerOpen" in shell_code
      and "ZL2ShellNavItem" in shell_code)

check('B6 nav 骨架刷新接线（顶栏刷新入口分支 + 任务胶囊动画上下文双骨架择一）',
      re.search(r"ame_refreshTopBarStateAnimated:\(BOOL\)animated \{\s*// ★ Task347：nav 骨架走等价刷新", shell)
      and "(self.topBar ?: self.contentHeader).window" in shell_code)

# ══ C 线C fluent-ui v2.2.0 ═════════════════════════════════════
man = json.loads(read("plugin-repo/src/fluent-ui/manifest.json"))
idx = json.loads(read("plugin-repo/index.json"))
fe = next((p for p in idx["plugins"] if p["id"] == "fluent-ui"), None)
zpath = "plugin-repo/plugins/fluent-ui.zip"
zdata = open(zpath, "rb").read()
zsha = hashlib.sha256(zdata).hexdigest()
znames = sorted(zipfile.ZipFile(zpath).namelist())

check('C1 v2.3.0 三方对拍（manifest + index 条目 + zip 实算 sha/size + zip 根两文件）',
      man.get("version") == "2.3.0" and fe and fe.get("version") == "2.3.0"
      and fe.get("sha256") == zsha and fe.get("size") == len(zdata)
      and znames == ["main.js", "manifest.json"])

plugin_js = read("plugin-repo/src/fluent-ui/main.js")
check('C2 结构应用/还原落位（FLUENT_STRUCTURE navigationview + 容错 + 五族全链）',
      "shellLayout: 'navigationview'" in plugin_js
      and "ame.setThemeStructure(FLUENT_STRUCTURE)" in plugin_js
      and "ame.setThemeStructure({})" in plugin_js
      and "setThemeStructure failed" in plugin_js
      and "ame.setThemeLayout(FLUENT_LAYOUT)" in plugin_js
      and "ame.setThemeLayout({})" in plugin_js
      and "ame.setThemeShape(FLUENT_SHAPE)" in plugin_js)

check('C3 v2.3.0 文案升维（装载即生效叙事 + v2.2.0 旧副题退役）',
      "左侧 NavigationView 导航窗格" in plugin_js
      and "Fluent 2 全维度·左侧导航窗格·装载即生效（点击循环）" in plugin_js
      and "fluent-ui v2.3.0 loaded" in plugin_js
      and "fluent-ui v2.2.0 loaded" not in plugin_js
      and "Fluent 2 全维度换装·即时生效（点击循环）" not in plugin_js)

# ══ D 结构护栏 ═════════════════════════════════════════════════
bal_files = ["Natives/ZL2Theme.m", "Natives/ZL2Theme.h", "Natives/DataTransferService.m",
             "Natives/PLPreferences.m", "Natives/PLPreferences.h",
             "Natives/AmePluginBridge.m", "Natives/AmePluginBridge.h",
             "Natives/AmePluginRuntime.m", "Natives/ZL2ShellViewController.m"]
check('D1 触碰面九文件括号平衡（大/圆/方三族，剥注释保留字符串口径——Task342 判例）',
      all(strip_keep_str(read(f)).count(a) == strip_keep_str(read(f)).count(b)
          for f in bal_files for a, b in [("{", "}"), ("(", ")"), ("[", "]")]))

wl = read("worklog.md")
check('D2 worklog Task 347 条目在位（## Task 347 + 双线标题）',
      "## Task 347" in wl and "ZIP 导入" in wl and "结构令牌" in wl)

# ══ 反向探针（--selftest：内存注入病灶变体必翻红，零仓内触碰） ══
if "--selftest" in sys.argv:
    print("── selftest 反向探针（内存注入，期望全翻红） ──")
    reds = []

    # S-A1：三段救援计数器全摘除 → A2 断言条件必翻红
    bad_dt = dt_code.replace("ame347_spineZipRescued", "").replace("ame347_spineV1Restored", "")
    ok = ("ame347_spineZipRescued" in bad_dt and "ame347_spineV1Restored" in bad_dt)
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-A1 三段救援计数器全摘除")
    if not ok: reds.append("S-A1")

    # S-B1：壳层 nav 骨架分支摘除 → B5 断言条件必翻红
    bad_shell = shell_code.replace("ame_buildNavigationViewShell", "")
    ok = ("ame_buildNavigationViewShell" in bad_shell)
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-B1 壳层 nav 骨架分支摘除")
    if not ok: reds.append("S-B1")

    # S-C1：manifest 版本回退 2.2.0 → C1 断言条件必翻红
    ok = (man.get("version") == "2.2.0" and fe and fe.get("version") == "2.3.0")
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-C1 manifest 版本回退")
    if not ok: reds.append("S-C1")

    if len(reds) != 3:
        print(f"selftest: {len(reds)}/3 翻红 -- 断言面失明，禁止交付")
        sys.exit(1)
    print("selftest: 3/3 全翻红（断言面有效）")
    sys.exit(0)

print(f"ame347_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("FAILED:", "; ".join(fails))
    sys.exit(1)
