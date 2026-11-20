#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task460 自检门（用户钦定「我要的是非折叠侧边栏的zl2式」+ Prisma II 装机截图轮）：

  用户第四轮接续反馈 + 本轮钦定语 = 侧边栏不许折叠：Task376 折叠二态
  （280↔64 WinUI compact 语义）/ Task455 会话级折叠 / .ui 预览驱动键 /
  窗格开关钮全链退役，窗格恒 ZL2 式 280pt 展开带标题。

  附带真雷收口 = 窄屏抽屉 z 序：paneWrap 构建序最早 = 视图栈最底，抽屉
  打开时被 dimOverlay（35% 黑罩）与内容区（栈顶）盖住 = 窗格不可见
  （「小屏不是 zl2 侧边栏」几何面）——置顶根修（MD3 modal drawer 层级）。

  镜像轨契约保留：fui NavigationView 镜像（AmeFluentPreviewMain ame416_*）
  的 -zl2pane 消费面与 NavItem ame_setCompact 方法体原样 = fui 插件覆盖态
  验收面零回归（Task458 判例延续）。

R = 修复形态执法 / X = 全仓扫描（家族零容忍）/ S = 敏感性自证（放行样本）
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []


def check(name, ok, detail=""):
    print(("  [PASS] " if ok else "  [FAIL] ") + name + (("  -- " + detail) if (detail and not ok) else ""))
    if not ok:
        FAILS.append(name)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


shell = read("Natives/ZL2ShellViewController.m")
preview = read("Natives/Preview/AmeFluentPreviewMain.m")
smoke = read("scripts/ui_fluent_smoke.sh")
theme = read("Natives/ZL2Theme.m")
buildtag = read("Natives/BuildTag.h")

print("== R 修复形态执法 ==")

# R1a 折叠开关钮全链退役（属性/创建/动作/约束四件零残留——代码面判据非注释面）
check("R1a 窗格开关钮代码面全链退役",
      "self.paneToggleButton" not in shell
      and "ZL2ShellIconButton *paneToggleButton" not in shell
      and "ame388_toggleLeading" not in shell.replace("// ★ Task460：ame388_toggleLeading（折叠开关钮前导）随开关钮退役。", "")
      and "BOOL ame376_paneCollapsed;" not in shell
      and "self.ame376_paneCollapsed" not in shell)

# R1b 紧凑宽常量退役（定义行零出现；历史注释允许）
check("R1b ZL2ShellPaneCompactWidth 定义退役",
      "static const CGFloat ZL2ShellPaneCompactWidth" not in shell)

# R1c 窗格宽恒 280 三点同源（创建 / 派发 constant / 内容区+头带前导 ternary）
check("R1c 窗格宽恒 280 三点同源在位",
      "self.ame376_paneWidth = [self.paneWrap.widthAnchor constraintEqualToConstant:ZL2ShellPaneWidth];" in shell
      and "self.ame376_paneWidth.constant = ZL2ShellPaneWidth;" in shell
      and "self.ame347_contentLeading.constant = self.ame347_regular ? ZL2ShellPaneWidth : 0.0;" in shell
      and "self.ame350_headerWrapLeading.constant = self.ame347_regular ? ZL2ShellPaneWidth : 0.0;" in shell)

# R1d 标题直接前导 + 恒可见（非折叠头行唯标题形态）
check("R1d 标题锚头行直接 8pt + 恒可见在位",
      "[self.paneTitle.leadingAnchor constraintEqualToAnchor:self.ame379_paneHeader.leadingAnchor constant:8.0]," in shell
      and "self.paneTitle.hidden = NO;" in shell)

# R1e Task455 头行 pin 零回归（999 等式形态保留）
check("R1e ame455 头行尾随 pin（999）零回归",
      shell.count("ame455_headerTrailing") >= 3
      and "self.ame455_headerTrailing.priority = 999;" in shell)

# R1f 判例注释在位（用户钦定语留档）
check("R1f Task460 非折叠钦定判例注释在位",
      "我要的是非折叠侧边栏的zl2式" in shell
      and "★Task460" in shell)

# R2a 抽屉 z 序根修（置顶行落在 ame347_applyDrawerGeometryAnimated 方法体内）
m = re.search(r"- \(void\)ame347_applyDrawerGeometryAnimated:\(BOOL\)animated \{.*?\n\}", shell, re.S)
body = m.group(0) if m else ""
check("R2a 抽屉 z 序根修（paneWrap 置顶于 drawer 几何派发体内）",
      "[self.view bringSubviewToFront:self.paneWrap];" in body)

# R2b 抽屉开合三路径保留（汉堡 toggle / 遮罩点击 / 导航项关闭）
check("R2b 抽屉开合三路径在位（汉堡/遮罩/导航项）",
      "[weakSelf ame_setDrawerOpen:!weakSelf.ame347_drawerOpen animated:YES];" in shell
      and "action:@selector(ame_dimTapped)" in shell
      and "[weakSelf ame_setDrawerOpen:NO animated:YES];" in shell)

# R2c Ame379 头行自证日志新形态（toggle 字段退役）
check("R2c [Ame379] 日志重锚（header/title 二读数）",
      "[Ame379] pane header -- header=%@ title=%@ titleLen=%lu" in shell
      and "toggle=%@ tglTrans" not in shell)

# R3a 壳回读键面退役（ame376.paneCollapsed 键字面量全文件零出现）
check("R3a 壳零 ame376.paneCollapsed 键面",
      "ame376.paneCollapsed" not in shell)

# R3b 预览真壳驱动链退役（-zl2pane 解析/expanded 变量/键写入三件零残留）
m417 = re.search(r"- \(void\)ame417_buildRealShell \{.*?\n\}", preview, re.S)
body417 = m417.group(0) if m417 else ""
check("R3b 真壳构建器折叠驱动退役（恒 280 展开渲染）",
      'indexOfObject:@"-zl2pane"' not in body417
      and "ame417_expanded" not in preview
      and "ame376.paneCollapsed" not in preview
      and "non-collapsible, pane 280 expanded, Task460" in preview)

# R3c smoke 真壳轨收敛单轨（real-pane 唯一真壳图证）
check("R3c smoke 真壳轨收敛（real-pane 单轨）",
      '"real-pane:home -zl2shell real"' in smoke
      and "real-collapsed" not in smoke
      and "real-expanded" not in smoke)

# R4 镜像轨契约保留（fui NavigationView 镜像 -zl2pane 消费面 + ame_setCompact 方法体与镜像消费点）
check("R4 镜像轨契约保留（ame416 -zl2pane + ame_setCompact 方法体 + 镜像消费点）",
      '- (void)ame_setCompact:(BOOL)compact {' in shell
      and 'NSUInteger ame416_paneIdx = [ame414_args indexOfObject:@"-zl2pane"];' in preview
      and "ame_setCompact:(" in preview)

# R5 shellLayout 默认蓝图零回归（Task456 内置化形态不动）
check("R5 shellLayout 默认蓝图 = navigationview 零回归",
      'return Ame347StructureOverride(@"shellLayout", @"navigationview");' in theme)

# R6 BuildTag 代际
check("R6 BuildTag = Task460 · 2026-11-21",
      'ame415_buildTag = @"Task460 · 2026-11-21"' in buildtag)

print("== X 全仓扫描 ==")

# X1 ame376.paneCollapsed 键字面量全仓零容忍（Natives 全域）
hits = []
for p in sorted(list((ROOT / "Natives").glob("*.m")) + list((ROOT / "Natives").glob("*.h"))
                + list((ROOT / "Natives").glob("Preview/*.m"))):
    t = p.read_text(encoding="utf-8", errors="replace")
    if "ame376.paneCollapsed" in t:
        hits.append(p.name)
check("X1 ame376.paneCollapsed 键字面量全仓零容忍", not hits, " ".join(hits))

# X2 紧凑宽常量全仓零定义
hits = []
for p in sorted(list((ROOT / "Natives").glob("*.m")) + list((ROOT / "Natives").glob("*.h"))):
    t = p.read_text(encoding="utf-8", errors="replace")
    if "static const CGFloat ZL2ShellPaneCompactWidth" in t:
        hits.append(p.name)
check("X2 ZL2ShellPaneCompactWidth 全仓零定义", not hits, " ".join(hits))

# X3 开关钮 a11y 站点唯一保留（汉堡钮同键站点 = nav_a11y 计 1）
check("X3 nav_a11y 站点唯一保留（开关钮站点退役）",
      shell.count('localize(@"ame369.shell.nav_a11y"') == 1)

# X4 壳窗格恒展开（壳侧零 ame_setCompact 派发调用——镜像轨调用不涉壳文件）
check("X4 壳侧零 ame_setCompact 派发调用",
      re.search(r"\[item ame_setCompact:", shell) is None
      and re.search(r"\[self\.navItems\w* ame_setCompact:", shell) is None)

print("== S 敏感性自证 ==")

# S1 窗格宽定义值敏感性（280 字面量唯一且恒定）
defs = re.findall(r"static const CGFloat ZL2ShellPaneWidth\s*=\s*([\d.]+);", shell)
check("S1 ZL2ShellPaneWidth 定义恰一处且 = 280",
      len(defs) == 1 and abs(float(defs[0]) - 280.0) < 1e-9)

# S2 派发体内零二态分支（compact/Collapsed 判据零出现）
m376 = re.search(r"- \(void\)ame376_applyPaneGeometry:\(BOOL\)animated \{.*?\n\}", shell, re.S)
body376 = m376.group(0) if m376 else ""
check("S2 派发体零二态分支（compact/collapsed 判据零出现）",
      body376 != "" and "compact" not in body376.lower()
      and "Collapsed" not in body376 and "ame_setCompact" not in body376)

# S3 抽屉偏移仍以常量单源（-(ZL2ShellPaneWidth + 12.0) 形态保留）
check("S3 抽屉屏外偏移常量单源保留",
      "-(ZL2ShellPaneWidth + 12.0)" in shell)

# S4 窄屏抽屉语义保留（ame347_regular 分支 + drawerOpen 态位零回归）
check("S4 窄屏抽屉语义零回归（regular 判据 + drawerOpen 态位）",
      "ame347_paneShown = self.ame347_regular || self.ame347_drawerOpen;" in shell
      and "- (void)ame_setDrawerOpen:(BOOL)open animated:(BOOL)animated {" in shell)

print()
if FAILS:
    print("task460_selfcheck RED -- %d FAIL: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
n_checks = 23
print("task460_selfcheck ALL PASS (%d assertions)" % n_checks)
