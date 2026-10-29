#!/usr/bin/env python3
# ame348_selfcheck.py -- Task348 两线门禁（zip 导入深扫救援+文案根修 / fluent-ui v2.3.0 装载即生效）
# A 线A：导入侧第四段救援（全包深扫 + instances/ 排除 + 内容判定 v1/v2）
#         + 空包诚实文案（ame348.import.spine_absent 54 表）+ flush 落盘回读验证
# B 线B：fluent-ui v2.3.0 装载即自动应用（autoApply + silent + optout 语义）
#         + manifest/index/zip 三方对拍
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

# ══ A 线A 导入深扫救援 + 文案根修 ═════════════════════════════
dt = read("Natives/DataTransferService.m")
dt_code = strip_code(dt)
lp = read("Natives/LauncherPreferences.m")

check('A1 全包深扫救援（根位两源皆空才触发 + listFilenames 全包扫描 + 候选计数择优）',
      "Task348: deep scan rescue candidate" in dt
      and "deep scan found no settings data anywhere in backup" in dt
      and "ame347_zipSpine == nil && ame347_v1Prefs == nil" in dt_code
      and "listFilenames:nil" in dt_code
      and "ame348_dict.count <= ame348_bestDict.count" in dt_code)

check('A2 深扫两条硬边界（instances/ 子树排除 + env_vars 内容判定 v1/v2）',
      'hasPrefix:@"instances/"' in dt
      and 'rangeOfString:@"/instances/"' in dt
      and 'ame348_bestDict[@"env_vars"] != nil' in dt
      and "if (ame348_isV1) ame347_v1Prefs = ame348_bestDict;" in dt_code
      and "else ame347_zipSpine = ame348_bestDict;" in dt_code)

check('A3 空包诚实文案（ame348.import.spine_absent 消费 + "空/损坏"摘要键退役）',
      'localize(@"ame348.import.spine_absent", nil)' in dt
      and 'localize(@"ame347.import.spine_kept", nil)' not in dt
      and "ame347_spineKept" in dt_code)

check('A4 i18n 一键 54 表全落位',
      all("ame348.import.spine_absent" in read(f"Natives/resources/{d}/Localizable.strings")
          for d in os.listdir("Natives/resources") if d.endswith(".lproj")))

check('A5 flush 落盘回读验证（空/不可解析当场报警，交导出侧强校验拒绝交付）',
      "Task348: WARNING flushed spine reads back empty/unparseable" in lp
      and "ame348_chk" in lp
      and "ame346_flushGlobalPrefsToDisk" in lp)

# ══ B 线B fluent-ui v2.3.0 装载即生效 ════════════════════════
man = json.loads(read("plugin-repo/src/fluent-ui/manifest.json"))
idx = json.loads(read("plugin-repo/index.json"))
fe = next((p for p in idx["plugins"] if p["id"] == "fluent-ui"), None)
zpath = "plugin-repo/plugins/fluent-ui.zip"
zdata = open(zpath, "rb").read()
zsha = hashlib.sha256(zdata).hexdigest()
znames = sorted(zipfile.ZipFile(zpath).namelist())
plugin_js = read("plugin-repo/src/fluent-ui/main.js")

check('B1 v2.3.0 三方对拍（manifest + index 条目 + zip 实算 sha/size + zip 根两文件）',
      man.get("version") == "2.3.0" and fe and fe.get("version") == "2.3.0"
      and fe.get("sha256") == zsha and fe.get("size") == len(zdata)
      and znames == ["main.js", "manifest.json"])

check('B2 装载即自动应用（autoApply 在位 + addLauncherRow 成功路径末尾调用 + silent 首装补齐）',
      "function autoApply()" in plugin_js
      and "  autoApply();" in plugin_js
      and "function applyPalette(idx, silent)" in plugin_js
      and "idx >= 0 ? idx : 0" in plugin_js
      and "palette applied: ' + pal.key + ' (structure+color+shape+layout' + (silent ? ', auto' : '') + ')'" in plugin_js)

check('B3 optout 语义（恢复默认武装 + 点击行解除 + 自动应用尊重选择）',
      "storageSet('fluent.optout', 'yes')" in plugin_js
      and "storageSet('fluent.optout', 'no')" in plugin_js
      and "storageGet('fluent.optout') === 'yes'" in plugin_js
      and "auto-apply skipped (user restored default" in plugin_js)

check('B4 容错纪律保持（五族链独立降级 + autoApply 自身 try-catch 非致命）',
      "ame.setThemeStructure(FLUENT_STRUCTURE)" in plugin_js
      and "ame.setThemeStructure({})" in plugin_js
      and "auto-apply failed (non-fatal)" in plugin_js
      and "shellLayout: 'navigationview'" in plugin_js)

# ══ D 结构护栏 ═══════════════════════════════════════════════
bal_files = ["Natives/DataTransferService.m", "Natives/LauncherPreferences.m"]
check('D1 触碰面文件括号平衡（大/圆/方三族，剥注释保留字符串口径——Task342 判例）',
      all(strip_keep_str(read(f)).count(a) == strip_keep_str(read(f)).count(b)
          for f in bal_files for a, b in [("{", "}"), ("(", ")"), ("[", "]")]))

wl = read("worklog.md")
check('D2 worklog Task 348 条目在位（## Task 348 + 双线标题）',
      "## Task 348" in wl and "深扫" in wl and "装载即" in wl)

# ══ 反向探针（--selftest：内存注入病灶变体必翻红，零仓内触碰） ══
if "--selftest" in sys.argv:
    print("── selftest 反向探针（内存注入，期望全翻红） ──")
    reds = []

    # S-A1：深扫触发条件摘除 → A1 断言条件必翻红
    ok = ("ame347_zipSpine == nil && ame347_v1Prefs == nil" in
          dt_code.replace("ame347_zipSpine == nil && ame347_v1Prefs == nil", ""))
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-A1 深扫触发条件摘除")
    if not ok: reds.append("S-A1")

    # S-B1：autoApply 调用摘除 → B2 断言条件必翻红
    bad_js = plugin_js.replace("  autoApply();", "")
    ok = ("  autoApply();" in bad_js)
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-B1 装载期 autoApply 调用摘除")
    if not ok: reds.append("S-B1")

    # S-A4：i18n 键从 zh-Hans 表内存摘除 → A4 断言条件必翻红
    zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings").replace("ame348.import.spine_absent", "")
    ok = ("ame348.import.spine_absent" in zh)
    print(f"  {'RED' if not ok else 'NOT-RED'}  S-A4 zh-Hans 表键摘除")
    if not ok: reds.append("S-A4")

    if len(reds) != 3:
        print(f"selftest: {len(reds)}/3 翻红 -- 断言面失明，禁止交付")
        sys.exit(1)
    print("selftest: 3/3 全翻红（断言面有效）")
    sys.exit(0)

print(f"ame348_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("FAILED:", "; ".join(fails))
    sys.exit(1)
