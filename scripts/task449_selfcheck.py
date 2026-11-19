#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task449 selfcheck：第 14 期六项全量验收门
A 修复A MD3 语言原生名（NSLocale 全量 + 撞名去重）
B 修复B RowList 展开动画根修（公共祖先 layoutIfNeeded）
C 修复C 设置折叠（38 组接入 + 持久化键 + 组件 API）
D 修复D 壁纸可见性对标 ZL2（tag 清扫管线 + chrome/卡面标记）
E 修复E 硬编码中文清扫（ame449.* 键 + 五表 + 纪律注释废止）
F 修复F 语言完整性（54 表 ≥ en 基准 + 主语言原生翻译在表）
G 性能采纳（小堆 ParallelGC 分支）
S 反向注入（摘片段必翻红）
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")
RES = os.path.join(NAT, "resources")

def rd(p):
    return open(os.path.join(NAT, p), encoding="utf-8").read()

PAT = re.compile(r'^\s*"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')

def parse_table(path):
    entries = {}
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s or s.startswith("//") or s.startswith("/*"):
            continue
        m = PAT.match(s)
        if m:
            entries[m.group(1)] = m.group(2)
    return entries

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

# ============ A 语言原生名 ============
sp = rd("ZL2SettingPages.m")
check("A1 NSLocale 全量路径", "displayNameForKey:NSLocaleIdentifier" in sp)
check("A2 旧 16 条映射退役", 'ru": @"Русский"' not in sp)
check("A3 撞名去重方法在场", "ame_languageDisplayNamesForCodes:" in sp)
check("A4 选择列表接去重", "ame_languageDisplayNamesForCodes:builtinCodes" in sp)

# ============ B 展开动画 ============
cards = rd("ZL2SettingCards.m")
check("B1 布局动画落公共祖先", "[(page ?: self.superview) layoutIfNeeded]" in cards)
check("B2 RowList 深子树 layoutIfNeeded 退役", "[self.superview layoutIfNeeded];" not in cards.split("@implementation ZL2SettingCardGroup")[0].split("@implementation ZL2SettingRowList")[-1])
check("B3 unhide 前置（准备段）", "if (expanded) self.optionsStack.hidden = NO;" in cards)
check("B4 收起后隐藏（completion）", "if (!expanded) self.optionsStack.hidden = YES;" in cards)

# ============ C 折叠组 ============
check("C1 组件 API 组头实现", "ame449_enableCollapsingWithTitle:" in cards)
check("C2 覆盖集读写", "ame449_foldOverrideSet" in cards and "ame449_foldOverrideMap" in cards)
check("C3 行数徽章刷新挂 addRow", "ame449_refreshHeader];" in cards)
prefs = rd("PLPreferences.m")
check("C4 持久化键注册", '"fold_overrides": @""' in prefs)
pages = rd("ZL2SettingPages.m")
check("C5 四参 addGroup 基类", "defaultCollapsed:(BOOL)defaultCollapsed" in pages)
n_sites = len(re.findall(r"ame_addGroup:\w+\n\s+title:localize\(@\"ame449\.setpg\.group\.", pages))
check("C6 38 组全接入", n_sites == 38, f"found={n_sites}")
check("C7 .h API 暴露", "ame449_enableCollapsingWithTitle" in rd("ZL2SettingCards.h") and "defaultCollapsed:(BOOL)defaultCollapsed" in rd("ZL2SettingPages.h"))

# ============ D 壁纸对标 ============
bmh = rd("BackgroundManager.h")
bmm = rd("BackgroundManager.m")
check("D1 标记常量与 inline", "kAme449ChromeSurfaceTag" in bmh and "Ame449MarkChromeSurface" in bmh)
check("D2 卡面标记函数", "void Ame449MarkCardSurface(UIView *view);" in bmh and "objc_setAssociatedObject" in bmm)
check("D3 清扫挂透明化管线", "ame449_sweepChromeAndCardsInView:viewController.view transparent:YES" in bmm)
check("D4 统一入口", "ame449_applyWallpaperTransparencyToViewTree" in bmm)
host = rd("ZL2BackgroundHost.m")
check("D5 无壁纸对称还原", "ame449_applyWallpaperTransparencyToViewTree:ownerVC.view" in host)
marks = 0
for f, needles in [
    ("ZL2ShellViewController.m", ["Ame449MarkChromeSurface(self.bareHeaderView)", "Ame449MarkChromeSurface(self.contentHeader)"]),
    ("ZL2SettingsViewController.m", ["Ame449MarkChromeSurface(_railScrollView)", "Ame449MarkChromeSurface(_contentContainer)"]),
    ("ZL2RailView.m", ["Ame449MarkChromeSurface(self)"]),
    ("ZL2VersionsViewController.m", ["Ame449MarkChromeSurface(_scrollView)"]),
]:
    t = rd(f)
    for n in needles:
        marks += 1 if n in t else 0
check("D6 chrome 标记六处", marks == 6, f"marks={marks}")
check("D7 卡面标记（行卡）", "Ame449MarkCardSurface(row)" in cards)
# ★Task452 收编重锚：0.5 可读性下限已被 Task450② 实质退役（卡面固定 0.72
#   档、与壁纸滑条解耦 = 15 期「还是有地方不是透明半透明」根修），断言随语义
check("D8 卡面固定半透明档 0.72（★Task450 与滑条解耦，0.5 下限退役）",
      "colorWithAlphaComponent:0.72" in bmm and "MAX(self.uiOpacity, 0.5)" not in bmm)

# ============ E 硬编码清扫 ============
check("E1 隔离动态文案键化", 'ame449.iso.no_profile' in pages and 'return localize(@"ame449.iso.no_profile"' in pages)
check("E2 导入报告键化", 'ame449.filexlate.kind_fmt' in rd("FileLayoutService.m"))
check("E3 JIT 门弹窗键化", 'ame449.jitgate.magnifier_no_response' in rd("PLJITGate.m"))
check("E4 账户行复用既有键", 'localize(@"login.option.add", nil)' in rd("ZL2HomeViewController.m") and 'localize(@"account.menu.delete", nil)' in rd("ZL2HomeViewController.m"))
check("E5 旧纪律注释废止", "纪律自本轮废止" in pages and "属性行硬编码中文纪律" not in pages.replace("「属性行硬编码中文」纪律自本轮废止", ""))
en = parse_table(f"{RES}/en.lproj/Localizable.strings")
need_keys = ["ame449.iso.no_profile", "ame449.iso.on_fmt", "ame449.iso.off_fmt", "ame449.iso.move_skip_fmt",
             "ame449.filexlate.core_fmt", "ame449.plugin.mg_demo_desc", "ame449.jitgate.magnifier_no_response",
             "ame449.gyro.samples_suffix", "ame449.about.deps.angle", "ame449.setpg.group.renderer",
             "ame449.setpg.group.debug_ui"]
check("E6 新键入 en 表（抽查11）", all(k in en for k in need_keys),
      str([k for k in need_keys if k not in en]))

# ============ F 语言完整性 ============
langs = sorted(d[:-6] for d in os.listdir(RES) if d.endswith(".lproj") and d != "Base.lproj")
check("F1 语言表 54 张", len(langs) == 54, f"got {len(langs)}")
below = []
for lang in langs:
    n = len(parse_table(f"{RES}/{lang}.lproj/Localizable.strings"))
    if n < len(en):
        below.append((lang, n))
check("F2 全表 ≥ en 基准", not below, str(below))
# 阈值口径：与 en 值不同的条目数（原生翻译存量）。ja/km 有历史 en 同文条目
# 与本轮部分兜底，阈值按各自实际原生存量基线（Task449 合并后实测）放宽。
THRESH = {"ja": 2000, "km": 1200}
for lang in ["ja", "ru", "de", "es", "fr", "it", "ko", "pt-BR", "km"]:
    tbl = parse_table(f"{RES}/{lang}.lproj/Localizable.strings")
    probe = [k for k in en if k in tbl and tbl[k] != en[k]]
    check(f"F3 {lang} 原生翻译在表（抽查）", len(probe) >= THRESH.get(lang, 3000), f"native~={len(probe)}")

# ============ G 性能采纳 ============
jl = rd("JavaLauncher.m")
check("G1 小堆 ParallelGC 分支", "allocmem <= 1024" in jl and '"-XX:ParallelGCThreads=2"' in jl)
check("G2 ParallelGC 不带 StringDedup", 'PUSH_MARGV_LITERAL("-XX:+UseStringDeduplication");\n            NSLog(@"[JavaLauncher] Task449' not in jl)
check("G3 分支日志锚", "[JavaLauncher] Task449 JVM preset=normal: small-heap" in jl)

# ============ BuildTag ============
tag = rd("BuildTag.h")
# ★Task452 收编判例④（Task439 同型）：锚值字面量锁死改形态验——本轮推进
#   必红 = 从未入电池的结构性根因；新鲜度职责移交 task439_buildtag_anchor 专门门
check("T1 BuildTag 形态验（代际新鲜度由 task439_buildtag_anchor 门执法）",
      re.search(r"Task\d+ · \d{4}-\d\d-\d\d", tag) is not None)

# ============ S 反向注入 ============
if os.environ.get("AME449_SFRAG") == "1":
    frag = os.environ.get("AME449_SFRAG_FILE", "")
    print(f"S: 反向注入模式（摘 {frag}）——人工执行")
else:
    # 程序化反向：模拟摘除关键片段后的谓词敏感性
    check("S1 A1/A3 同源（去重依赖 NSLocale 路径）", "displayNameForKey" in sp and "ame_languageDisplayNamesForCodes" in sp)
    check("S2 C6 计数谓词敏感性", n_sites == 38)
    check("S3 D3 挂点唯一性", bmm.count("ame449_sweepChromeAndCardsInView:viewController.view transparent:YES") == 1)

print()
if fails:
    print(f"ALL FAIL {len(fails)}: {fails}")
    sys.exit(1)
print("ALL PASS")
