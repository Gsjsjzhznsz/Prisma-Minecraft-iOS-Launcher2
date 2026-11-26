#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task462 自检门：「其他修改找回」外科重应用轮（用户诉「确实变回去了。但是我的其他修改怎么全部不见了。」）。

回退构成（Task462 = Task461 树 + 449/450/455/460 修改面外科找回）：
  R1 Task450⑥ 小屏设备简单侧栏（min 维度 < 500pt 摘 AI 项+文件项，15 期⑥）
  R2 Task450④ 版本列表三修（json 缺失 referenced 入列 + 派生子行默认展开语义倒置 + 扫描父根补挂，15 期④）
  R3 Task450⑤ 转盘宽度上钳 300→460 自适应 iPad（15 期⑤）
  R4 Task450③ 隔离数据播种 copy-from-parent（FabricUtils/NeoForge 安装落盘后播种六数据面，15 期③）
  R5 Task449① MD3 语言原生名（NSLocale displayNameForKey 全量 + 撞名去重，14 期①）
  R6 Task449 性能采纳（小堆 ≤1024MB ParallelGC×2 对标 Witch：G1 Full GC 冻结缓解，14 期性能）
  R7 Task455 附带真雷 Task255 裸键查表根修（control.auto_control_update_check 点分前缀）
  R8 Task460 抽屉 z 序根修单面移植（paneWrap bringSubviewToFront，窄屏抽屉窗格不可见根修）
  R9 Task449⑤ 硬编码中文清扫（filexlate/iso/jitgate/gyro/mg_demo/mf_* 家族 localize 化）
  R10 i18n 54 表全量恢复（460 代际表回归：af 4376/en 4669/ja 4513/km 4496…，r0 误伤面）

随树退役面（X 继承 Task461 全量执法——★Task463 判例翻转：设置折叠已按用户诉求恢复在场，其余锁定面不变）：
  壁纸清扫管线（PC=0 雷 ame450_isCardFamilyColor）/ 455 启动抑制 /
  456 蓝图翻转+沉降窗 / 458 选中双族 / 460 非折叠退役符号 / topbar 粉色钦定蓝图
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []
CHECKS = [0]


def check(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(f"{name} {detail}")
        print(f"  RED  {name} {detail}")


def rd(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


print("== R 恢复形态执法（450⑥④⑤③ / 449①性能⑤ / 455 裸键 / 460 抽屉 z 序） ==")
shell = rd("Natives/ZL2ShellViewController.m")
check("R1-1 450⑥ compactDevice 判定退役反转（★Task477 一代抽屉清场 = 小屏摘项面随伴退役）",
      "ame450_compactDevice" not in shell)
check("R1-2 450⑥ 主列摘 AI 项守卫退役反转（★Task477）", "ame347_pages" not in shell)
check("R1-3 450⑥ 底部摘文件项守卫退役反转（★Task477）", "ame347_footerPages" not in shell)
check("R8-1 460 抽屉 z 序置顶退役反转（★Task477 paneWrap 清场）", "paneWrap" not in shell)

vers = rd("Natives/ZL2VersionsViewController.m")
check("R2-1 450④ 折叠态属性语义倒置",
      "@property (nonatomic, strong) NSMutableSet<NSString *> *ame444_collapsedVids;" in vers
      and "ame444_expandedVids" not in vers)
check("R2-2 450④ 子行默认展开（非收起才展开）",
      "![self.ame444_collapsedVids containsObject:ame444_vid]" in vers)
check("R2-3 450④ json 缺失 referenced 入列",
      "ame450_jsonMissing && ![ame428_e[@\"referenced\"] boolValue] ) continue".replace(" )", ")") in vers
      and "ame450_jsonMissing" in vers)
check("R2-4 450④ 扫描父根补挂（versions/<x> 落点）",
      "[ame450_parent lastPathComponent] isEqualToString:@\"versions\"]" in vers)

home = rd("Natives/ZL2HomeViewController.m")
check("R3-1 450⑤ 转盘上钳 460", "ZL2HomeMenuWidthMax     = 460;" in home)
check("R3-2 450⑤ 旧 300 上钳退役", "ZL2HomeMenuWidthMax     = 300;" not in home)

pph = rd("Natives/PLProfiles.h")
ppm = rd("Natives/PLProfiles.m")
fu = rd("Natives/installer/FabricUtils.m")
nf = rd("Natives/installer/NeoForgeDirectInstaller.m")
# ★Task472 退役化重锚：版本隔离退役——ame450 播种族（隔离数据面）随体系
#   整体删除，R4 四断言反转为缺席执法。
check("R4-1 472 隔离退役：ame450 播种 API 声明+实现缺席",
      "ame450_seedIsolatedVersionData" not in pph and "ame450_seedIsolatedVersionData" not in ppm)
check("R4-2 472 隔离退役：FabricUtils 播种调用点缺席", "ame450_seedIsolatedVersionData" not in fu)
check("R4-3 472 隔离退役：NeoForge 播种调用点缺席", "ame450_seedIsolatedVersionData" not in nf)
check("R4-4 472 隔离退役：播种六数据面缺席",
      "已存在绝不覆盖" not in ppm and "ame428_moveItemNames" not in ppm)

sp = rd("Natives/ZL2SettingPages.m")
check("R5-1 449① NSLocale 全量路径", "displayNameForKey:NSLocaleIdentifier value:code" in sp)
check("R5-2 449① 撞名去重方法在场", "ame_languageDisplayNamesForCodes:(NSArray<NSString *> *)codes" in sp)
check("R5-3 449① 语言行接入去重表",
      "[langNames addObjectsFromArray:\n        [ZL2LauncherSettingsPage ame_languageDisplayNamesForCodes:builtinCodes]];" in sp)
check("R5-4 449① 旧 16 条手写映射退役", '@"zh-CN": @"简体中文 (zh-CN)",' not in sp)

jl = rd("Natives/JavaLauncher.m")
check("R6-1 449 小堆 ParallelGC 档", "} else if (allocmem <= 1024) {" in jl
      and '"-XX:+UseParallelGC"' in jl and '"-XX:ParallelGCThreads=2"' in jl)

ctrl = rd("Natives/ZL2ControlRepoViewController.m")
check("R7-1 Task255 裸键根修（点分前缀）",
      'getPrefBool(@"control.auto_control_update_check")' in ctrl)
check("R7-2 Task255 裸键形态退役（消费端）",
      'getPrefBool(@"auto_control_update_check")' not in ctrl)

check("R9-1 449⑤ filexlate 家族 localize 化",
      'localize(@"ame449.filexlate.kind_fmt"' in rd("Natives/FileLayoutService.m"))
check("R9-2 ★Task475 mg_demo 种子家族退役（code 零引用 + 在线仓库安装链在场）",
      'ame449.plugin.mg_demo_name' not in rd("Natives/PLRendererPluginService.m")
      and 'installRendererPluginFromZip:ame475_tmpZip' in rd("Natives/ZL2RendererRepoViewController.m")
      and 'ZL2RendererRepoViewController.m' in rd("Natives/CMakeLists.txt"))
check("R9-3 449⑤ manifest 隔离文案 localize 化",
      'localize(@"ame449.plugin.mf_not_json"' in rd("Natives/AmePluginRuntime.m"))
check("R9-4 449⑤ JITGate magnifier localize 化",
      'localize(@"ame449.jitgate.magnifier_no_response"' in rd("Natives/PLJITGate.m"))
# ★Task472 退役化重锚：iso 迁移流随隔离退役删除，文案键无代码站点。
check("R9-5 472 隔离退役：iso 迁移文案站点缺席",
      'ame449.iso.move_skip_fmt' not in ''.join(re.sub(r'//.*', '', x) for x in ppm.split('\n')))
check("R9-6 449⑤ gyro 样本后缀 localize 化",
      'localize(@"ame449.gyro.samples_suffix"' in rd("Natives/ZL2GyroTunerViewController.m"))
check("R9-7 449⑤ 账户钮 localize 化",
      'title:localize(@"login.option.add", nil)]' in home
      and 'title:localize(@"account.menu.delete", nil)]' in home)
# ★Task472 退役化重锚：iso 设置页文案随隔离行退役删除。
check("R9-8 472 隔离退役：iso 设置页文案站点缺席",
      'ame449.iso.no_profile' not in ''.join(re.sub(r'//.*', '', x) for x in sp.split('\n')))

print("== R10 i18n 54 表全量恢复执法 ==")
res = ROOT / "Natives" / "resources"
# ★Task465：ame451_preflight/ame457_dyldhook 两弹窗键 54 表退役 → 各表地板 −2
expect_lines = {"af": 4374, "ar": 4425, "de": 4443, "en": 4667, "es": 4430, "fr": 4438,
                "it": 4428, "ja": 4511, "km": 4494, "ko": 4423, "pt-BR": 4447, "ru": 4446,
                "zh-CN": 4663, "zh-Hans": 4666, "zh-Hant": 4664}
for lang, expect in expect_lines.items():
    f = res / f"{lang}.lproj" / "Localizable.strings"
    n = len(f.read_text(encoding="utf-8", errors="replace").splitlines()) if f.exists() else 0
    check(f"R10 {lang}.lproj ≥ {expect} 行（460 代际表回归 + Task465 −2）", n >= expect, f"got {n}")
check("R10 ame449.iso 键入 zh-Hans 表",
      "ame449.iso.no_profile" in rd("Natives/resources/zh-Hans.lproj/Localizable.strings"))
check("R10 451/457 退役键不在 en 表 + ame449.iso 时代键在场（★Task465 翻转：退役执法，回潮检测由行数地板承担）",
      "ame451" not in rd("Natives/resources/en.lproj/Localizable.strings")
      and "ame457" not in rd("Natives/resources/en.lproj/Localizable.strings")
      and "ame449.iso.no_profile" in rd("Natives/resources/en.lproj/Localizable.strings"))

print("== X 锁定面继承执法（Task461 X 全量继承，本轮找回零污染） ==")
SCAN_FILES = list((ROOT / "Natives").rglob("*.m")) + list((ROOT / "Natives").rglob("*.h"))


def scan_count(pattern):
    n = 0
    pat = re.compile(pattern)
    for f in SCAN_FILES:
        n += len(pat.findall(f.read_text(encoding="utf-8", errors="replace")))
    return n


check("X1 折叠面恢复在场（★Task463 判例翻转：用户诉求恢复设置折叠）",
      scan_count(r"ame449_enableCollapsing") >= 3
      and scan_count(r"ame449_collapsed") >= 8)
check("X2-1 壁纸清扫符号归零", scan_count(r"ame449_sweep") == 0)
check("X2-2 PC=0 雷符号归零", scan_count(r"ame450_isCardFamilyColor") == 0)
check("X2-3 壁纸透明管线归零", scan_count(r"ame449_applyWallpaperTransparency") == 0)
check("X3-1 Task455 启动抑制归零", scan_count(r"ame455_consumeStartupRebuild") == 0)
check("X3-2 Task455 会话折叠键归零", scan_count(r"ame455\.") == 0)
check("X4-1 Task456 沉降窗/去抖归零",
      scan_count(r"ame456_debounceArmed|ame456_versionCardHeight|ame456_versionCardChrome") == 0)
check("X4-2 Task459 钳制字面量归零", scan_count(r"ame459_") == 0)
check("X4-3 Task460 非折叠退役符号归零", scan_count(r"ame460_") == 0)
check("X5 Task458 选中双族归零", scan_count(r"ame347_shellLayoutPluginOverridden") == 0)
theme = rd("Natives/ZL2Theme.m")
check("X6-1 默认蓝图保持 topbar（粉色钦定形态）",
      'Ame347StructureOverride(@"shellLayout", @"topbar")' in theme
      and 'Ame347StructureOverride(@"shellLayout", @"navigationview")' not in theme)
cards = rd("Natives/ZL2SettingCards.m")
check("X6-2 设置卡折叠态在场（★Task463 判例翻转）", "ame449_enableCollapsingWithTitle" in cards)
check("X7-1 448 侧栏折叠机制退役反转（★Task477 一代抽屉清场 = ame376 折叠面随伴退役零残留）",
      "ame376_paneCollapsed" not in rd("Natives/ZL2ShellViewController.m"))
check("X7-2 壁纸功能本体在场（ame429）",
      "ame429" in rd("Natives/ZL2BackgroundHost.m"))

print("== S 敏感性样本 ==")
tag = rd("Natives/BuildTag.h")
check("S1 BuildTag Task478 · 2026-11-26（侧边栏双形态+渲染器在线仓库轮代际重锚）", "Task478 · 2026-11-26" in tag)
check("S2 电池注册 task462", "task462_selfcheck" in rd("scripts/task432_gate_battery.sh"))

print(f"\n========================================")
if FAILS:
    print(f"task462_selfcheck RED —— {len(FAILS)} failed / {CHECKS[0]} total")
    sys.exit(1)
print(f"task462_selfcheck: {CHECKS[0]} passed, 0 failed")
print("ALL GREEN")
