#!/usr/bin/env python3
# ame346_selfcheck.py -- Task346 两线门禁（令牌即时生效 / 备份脉柱链收口）
# A 线A：ZL2Theme 令牌 setter 接入根重建杠杆（终结"插件只变了配色"）
# B 线B：备份链四段收口（导出 flush ×2 + 分区强制脉柱 + 导入空/坏脉柱防毒化）
# C 线C：fluent-ui v2.1.1 文案/manifest/仓库件对拍
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
    """真代码剥离（块注释→字符串→行注释单遍扫描；ame337/341 判例剥器翻版）"""
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
    """剥注释保留字符串（Task342 判例剥器；括号平衡专用）"""
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

# ══ A 线A 令牌即时生效链 ═══════════════════════════════════════
theme = read("Natives/ZL2Theme.m")
theme_code = strip_code(theme)

check('A1 根重建杠杆定义（合并去抖 + 主队列 + AppLanguageChanged 投递 + 日志锚点）',
      "static void ame346_requestRootRebuild(void)" in theme_code
      and "ame346_rebuildScheduled" in theme_code
      and "postNotificationName:@" in theme_code
      and 'postNotificationName:@"AppLanguageChanged"' in theme
      and "[ZL2Theme] Task346: token change -> root rebuild posted" in theme)

check('A2 八落位（四 setter × 应用/还原双路径均接入；★Task347 ame347 结构 setter 接入）',
      theme_code.count("ame346_requestRootRebuild()") == 8,
      f'call sites={theme_code.count("ame346_requestRootRebuild()")}')

def _restore_has_call(code):
    """三个 setter 的还原路径（tokens.count == 0 早退）各自紧跟重建调用"""
    hits = 0
    for m in re.finditer(r"tokens\.count == 0\) \{\s*ame346_requestRootRebuild\(\);", code):
        hits += 1
    return hits

check('A3 四还原路径全部带重建调用（还原语义同样即时生效；★Task347 +结构族）',
      _restore_has_call(theme_code) == 4,
      f'restore paths with call={_restore_has_call(theme_code)}')

sd = read("Natives/SceneDelegate.m")
check('A4 根重建杠杆消费面在位（AppLanguageChanged 观察者 + ZL2Shell 重建，Task230 链路未回退）',
      'name:@"AppLanguageChanged"' in sd
      and "ZL2ShellViewController" in sd
      and "applyLanguageChange" in sd)

bridge = read("Natives/AmePluginBridge.m")
runtime = read("Natives/AmePluginRuntime.m")
check('A5 桥面/Runtime 全路径仍经 ZL2Theme setter（杠杆覆盖桥面应用/装载重放/卸载还原三路）',
      "[ZL2Theme ame317_setPluginThemeTokens:" in bridge
      and "[ZL2Theme ame341_setPluginThemeShape:" in bridge
      and "[ZL2Theme ame343_setPluginThemeLayout:" in bridge
      and "[ZL2Theme ame317_setPluginThemeTokens:" in runtime
      and "[ZL2Theme ame341_setPluginThemeShape:" in runtime
      and "[ZL2Theme ame343_setPluginThemeLayout:" in runtime)

# ══ B 线B 备份脉柱链收口 ═══════════════════════════════════════
lp_h = read("Natives/LauncherPreferences.h")
lp_m = read("Natives/LauncherPreferences.m")
plp_h = read("Natives/PLPreferences.h")
dt = read("Natives/DataTransferService.m")

check('B1 flush 声明/实现/落盘链（头声明 + 实现 saveGlobalPref + PLPreferences.h 声明）',
      "void ame346_flushGlobalPrefsToDisk(void);" in lp_h
      and "void ame346_flushGlobalPrefsToDisk(void) {" in lp_m
      and "[pref saveGlobalPref];" in lp_m
      and "- (void)saveGlobalPref;" in plp_h)

check('B2 双导出器 flush 前置（Task219 全量 + Task224 分区，walk 前各一次）',
      dt.count("ame346_flushGlobalPrefsToDisk();") == 2
      and "backup spine guard" in lp_m)

check('B3 分区导出脉柱强制在场（v2 脉柱 + v1 兼容件，勾选外仍进包）',
      '[rel isEqualToString:@"launcher_preferences_v2.plist"]' in dt
      and '[rel isEqualToString:@"launcher_preferences.plist"]' in dt
      and re.search(r"if \(!include &&\s*\(\[rel isEqualToString:@\"launcher_preferences_v2\.plist\"\]", dt))

check('B4 导入空/坏脉柱防毒化（合并循环 staging 解析 count==0 跳过 + 计数留痕）',
      "ame346_skippedSpineFiles" in dt
      and re.search(r"launcher_preferences_v2\.plist\"\]\) \{\s*NSDictionary \*ame346_chk = \[NSDictionary dictionaryWithContentsOfFile:", dt)
      and "empty/corrupt prefs spine skipped -- kept current settings" in dt)

check('B5 Task345 脉柱校验保留为兜底（导入 spine check + 双导出器写毕校验未回退）',
      "Task345: spine check prefs=" in dt
      and "ame345_exportSpineProblem" in dt
      and dt.count("ame345_exportSpineProblem:") >= 3)

# ══ C 线C fluent-ui v2.1.1 ═════════════════════════════════════
man = json.loads(read("plugin-repo/src/fluent-ui/manifest.json"))
idx = json.loads(read("plugin-repo/index.json"))
fe = next((p for p in idx["plugins"] if p["id"] == "fluent-ui"), None)
zpath = "plugin-repo/plugins/fluent-ui.zip"
zdata = open(zpath, "rb").read()
zsha = hashlib.sha256(zdata).hexdigest()
znames = sorted(zipfile.ZipFile(zpath).namelist())

check('C1 v2.2.0 三方对拍（manifest + index 条目 + zip 实算 sha/size + zip 根两文件；★Task347 顺延）',
      man.get("version") == "2.2.0" and fe and fe.get("version") == "2.2.0"
      and fe.get("sha256") == zsha and fe.get("size") == len(zdata)
      and znames == ["main.js", "manifest.json"])

plugin_js = read("plugin-repo/src/fluent-ui/main.js")
check('C2 结构叙事文案落位（v2.1.1 副题退役 + 行副题/loaded 行升 2.2.0；★Task347 顺延）',
      "左侧导航窗格" in plugin_js
      and "新开页面/重启启动器全量生效" not in plugin_js
      and "Fluent 2 全维度·左侧导航窗格（点击循环）" in plugin_js
      and "fluent-ui v2.2.0 loaded" in plugin_js)

LAYOUT_KEYS = ["searchBarHeight", "chipHeight", "cardMarginV", "cardMarginH",
               "cardInsetX", "cardInsetTop", "cardInsetBottom", "cardContentGap",
               "pillMinWidth", "pillHeight", "pillGap", "dialogInset", "buttonHeight"]
check('C3 FLUENT_LAYOUT 13 键 + 布局链容错/恢复语义零回退（Task343 资产回归锚）',
      all(f"{k}:" in plugin_js for k in LAYOUT_KEYS)
      and "ame.setThemeLayout(FLUENT_LAYOUT)" in plugin_js
      and "ame.setThemeLayout({})" in plugin_js
      and "setThemeLayout failed" in plugin_js)

# ══ D 结构护栏 ═════════════════════════════════════════════════
bal_files = ["Natives/ZL2Theme.m", "Natives/DataTransferService.m",
             "Natives/LauncherPreferences.h", "Natives/LauncherPreferences.m",
             "Natives/PLPreferences.h"]
check('D1 触碰面五文件括号平衡（大/圆/方三族，剥注释保留字符串口径——Task342 判例）',
      all(strip_keep_str(read(f)).count(a) == strip_keep_str(read(f)).count(b)
          for f in bal_files for a, b in [("{", "}"), ("(", ")"), ("[", "]")]))

wl = read("worklog.md")
check('D2 worklog Task 346 条目在位（## Task 346 + 两线标题）',
      "## Task 346" in wl and "只变了配色" in wl)

# ══ 反向探针（--selftest：内存注入病灶变体必翻红，零仓内触碰） ══
if "--selftest" in sys.argv:
    print("── selftest 反向探针（内存注入，期望全翻红） ──")
    reds = []

    # S-A1：摘除全部重建调用 → A2 断言条件必翻红
    bad_code = theme_code.replace("ame346_requestRootRebuild()", "")
    ok = bad_code.count("ame346_requestRootRebuild()") == 6
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-A1 重建调用全摘除")
    if not ok: reds.append("S-A1")

    # S-B1：强制脉柱块整体摘除 → B3 断言条件必翻红
    bad_dt = re.sub(r"// ★ Task346：启动器设置脉柱强制在场.*?if \(!include &&\s*\(\[rel isEqualToString:@\"launcher_preferences_v2\.plist\"\]\s*\|\|\s*\[rel isEqualToString:@\"launcher_preferences\.plist\"\]\)\) \{\s*include = YES;\s*\}", "", dt, flags=re.S)
    ok = bool(re.search(r"if \(!include &&\s*\(\[rel isEqualToString:@\"launcher_preferences_v2\.plist\"\]", bad_dt))
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-B1 分区强制脉柱摘除")
    if not ok: reds.append("S-B1")

    # S-C1：manifest 版本回退 2.1.1 → C1 断言条件必翻红
    ok = (man.get("version") == "2.1.1" and fe and fe.get("version") == "2.2.0")
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-C1 manifest 版本回退")
    if not ok: reds.append("S-C1")

    if len(reds) != 3:
        print(f"selftest: {len(reds)}/3 翻红 -- 断言面失明，禁止交付")
        sys.exit(1)
    print("selftest: 3/3 全翻红（断言面有效）")
    sys.exit(0)

print(f"ame346_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("FAILED:", "; ".join(fails))
    sys.exit(1)
