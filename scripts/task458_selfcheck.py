#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task458 自检门（用户复诉「我的md3界面怎么变成了fui。zl2格式去哪里了。
还有下载中心的插件和控件给我恢复。」三诉落码轮）：

  ①② md3→fui / zl2 格式丢失 = Task456 默认蓝图内置化后默认骨架沿用插件族
      WinUI 选中语义的观感错位 —— 根修 = 选中语义双族分流（结构令牌插件覆盖
      在位 → WinUI 抬升 + 滑移指示条契约原样；默认蓝图 → ZL2/MD3
      secondaryContainer 胶囊 + radiusM + 无边缘指示条，ZalithLauncher2 原版
      语义，ZL2DownloadRailItem 同源）
  ③ 下载中心插件/控件丢失 = Task432 SD 工位收敛与用户心智位相左 —— 根修 =
      仓库三轨 Task323 原版形态 1:1 复位（nav 宿主 + 符号/轨序同源 + localize
      既有键复用零新增），设置域入口保留双面共存

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


theme = read("Natives/ZL2Theme.m")
theme_h = read("Natives/ZL2Theme.h")
shell = read("Natives/ZL2ShellViewController.m")
dl = read("Natives/ZL2DownloadViewController.m")
settings = read("Natives/ZL2SettingPages.m")
preview = read("Natives/Preview/AmeFluentPreviewMain.m")
smoke_raw = read("scripts/ui_fluent_smoke.sh")
buildtag = read("Natives/BuildTag.h")

print("== R 修复形态执法 ==")

# R1 分流判据 API（ZL2Theme 实现 + 头文件契约 + nil 安全判据形态）
check("R1a ame347_shellLayoutPluginOverridden 实现（entry.count==2 判据）",
      "+ (BOOL)ame347_shellLayoutPluginOverridden {" in theme
      and "ame347_structureOverride[@\"shellLayout\"]" in theme
      and "ame458_entry.count == 2" in theme)
check("R1b 头文件契约声明在位",
      "+ (BOOL)ame347_shellLayoutPluginOverridden;" in theme_h)

# R2 选中语义双族分流（ame_setSelected）
check("R2a 分流判据读取（ame458_pluginOverride 局部判定单点）",
      shell.count("BOOL ame458_pluginOverride = [ZL2Theme ame347_shellLayoutPluginOverridden];") == 1
      and "if (ame458_pluginOverride) {" in shell)
check("R2b 默认族 MD3/ZL2 胶囊（secondaryContainer + onSecondaryContainer）",
      "self.backgroundColor = selected ? [ZL2Theme secondaryContainer] : [UIColor clearColor];" in shell
      and "UIColor *tint = selected ? [ZL2Theme onSecondaryContainer] : [ZL2Theme onSurfaceVariant];" in shell)
check("R2c 插件族 WinUI 契约原样（Task414 Highest 抬升字面量保留 = ame378 rail-highest 同面）",
      "self.backgroundColor = selected ? [ZL2Theme surfaceContainerHighest] : [UIColor clearColor];" in shell
      and "UIColor *tint = selected ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];" in shell)
check("R2d 圆角双族同源（默认 radiusM / 插件 radiusS 条件式）",
      "self.layer.cornerRadius = ame458_pluginOverride ? [ZL2Theme radiusS] : [ZL2Theme radiusM];" in shell)
check("R2e init 首帧圆角条件式（旧 radiusS 裸行退役）",
      "[ZL2Theme ame347_shellLayoutPluginOverridden]\n                                      ? [ZL2Theme radiusS] : [ZL2Theme radiusM];" in shell
      and "        self.layer.cornerRadius = [ZL2Theme radiusS];\n" not in shell)

# R3 ame389 滑移指示条默认恒隐（M3 无边缘指示条）
check("R3a 默认蓝图早退恒隐（判据与 ame_setSelected 同源）",
      "if (![ZL2Theme ame347_shellLayoutPluginOverridden]) {" in shell
      and shell.count("ame347_shellLayoutPluginOverridden") >= 3)
check("R3b 滑移条 unhide 写面唯一（插件覆盖态分支内恰 1 处）",
      shell.count("self.ame389_slideIndicator.hidden = NO;") == 1
      and shell.index("self.ame389_slideIndicator.hidden = NO;")
      > shell.index("if (![ZL2Theme ame347_shellLayoutPluginOverridden]) {"))

# R4 下载中心仓库三轨回归（Task323 原版形态 1:1）
check("R4a 三轨标题 localize 既有键复用（零新增键）",
      'localize(@"ame369.common.control_repo", @"控件仓库")' in dl
      and 'localize(@"ame369.common.gamepad_repo", @"手柄仓库")' in dl
      and 'localize(@"ame318.repo.title", @"插件仓库")' in dl)
check("R4b 符号与 divider 形态同源（square.grid.2x2/dial/shippingbox + 三仓库组前置线）",
      '@"square.grid.2x2", @"dial", @"shippingbox"' in dl
      and "@YES, @NO, @NO];" in dl
      and dl.count("@YES") == 3)
check("R4c nav 宿主嵌入三件（case 8/9/10 + edgesForExtendedLayout + 手柄分类直达）",
      "case 8:" in dl and "case 9:" in dl and "case 10:" in dl
      and "ame458_repo.initialCategoryIndex = 2;" in dl
      and dl.count("initWithRootViewController") == 3
      and dl.count("edgesForExtendedLayout = UIRectEdgeNone;") == 3)
check("R4d 双 import 复位（Task432 退役面回滚）",
      '#import "ZL2ControlRepoViewController.h"' in dl
      and '#import "ZL2PluginRepoViewController.h"' in dl)

# R5 预览 harness 默认蓝图轨（-zl2theme default 跳过 fluent 注入）
check("R5a 预览 default 旗标判定（条件跳过 AmePreviewApplyFluentTokens）",
      '[ame458_args[ame458_themeIdx + 1] isEqualToString:@"default"]' in preview
      and "if (!ame458_defaultTheme) {" in preview
      and "AmePreviewApplyFluentTokens();" in preview)
check("R5b 真壳默认轨留痕日志（装机/CI 判读锚）",
      "default-theme track (embermire baseline" in preview)

# R6 冒烟脚本默认轨（真壳 MD3 观感截图验收面）
check("R6 冒烟默认轨（-zl2shell real -zl2theme default + 截图名）",
      "-zl2page home -zl2shell real -zl2theme default" in smoke_raw
      and "ame-zl2-real-default-home-dark.png" in smoke_raw)

print("== X 全仓扫描 ==")

# X1 分流判据写面唯一（ame347 覆盖表只经 setter 写入；读侧只读）
check("X1 ame347 覆盖表写面唯一（ame347_structureOverride 赋值仅 init/setter）",
      theme.count("ame347_structureOverride =") == 2)   # 静态声明 nil init + setter 兜底分配
# X2 WinUI 选中行底语义收敛（surfaceContainerHighest 行底字面量壳内恰 1 处 = 分流分支）
check("X2 Highest 行底字面量唯一（防第三族回潮）",
      shell.count("[ZL2Theme surfaceContainerHighest] : [UIColor clearColor]") == 1)
# X3 设置域仓库入口双面共存（Task432 SD 工位面零回归）
check("X3 设置域仓库三行组在位（ame_push 双面共存）",
      'localize(@"ame369.common.control_repo", @"控件仓库")' in settings
      and 'localize(@"ame369.common.gamepad_repo", @"手柄仓库")' in settings
      and "[[ZL2PluginRepoViewController alloc] init]" in settings)
# X4 下载页轨道计数一致性（titles/symbols/dividerBefore 三数组同长 11）
dl_titles = re.search(r"NSArray<NSString \*> \*titles = @\[.*?\];", dl, re.S)
dl_symbols = re.search(r"NSArray<NSString \*> \*symbols = @\[.*?\];", dl, re.S)
dl_div = re.search(r"NSArray<NSNumber \*> \*dividerBefore = @\[.*?\];", dl, re.S)
check("X4 轨道三数组同长（titles=symbols=dividerBefore=11）",
      dl_titles is not None and dl_symbols is not None and dl_div is not None
      and dl_titles.group(0).count("localize(@" ) == 11
      and dl_symbols.group(0).count('@"') == 11
      and dl_div.group(0).count("@NO") + dl_div.group(0).count("@YES") == 11
      and dl_div.group(0).count("@YES") == 3)
# X5 预览镜像轨 fluent-dark 字面量保留（ame378 smoke-nav-track 同面零回归）
check("X5 冒烟 fluent-dark 轨字面量保留（插件覆盖态契约验收面不动）",
      "-zl2shell nav -zl2theme fluent-dark" in smoke_raw)

print("== S 敏感性自证 ==")

# S1 nil 安全（nil 覆盖表/缺键/畸形条目三态 → NO = 默认 MD3 族）
check("S1 判据 nil 安全形态（无强制解包/无 hasPrefix 文案依赖）",
      "NSArray *ame458_entry = ame347_structureOverride[@\"shellLayout\"];" in theme
      and "return ame458_entry.count == 2;" in theme)
# S2 插件族/默认族着色互斥（onSecondaryContainer 不落插件族分支、onSurface 不落默认族分支）
winui_idx = shell.index("if (ame458_pluginOverride) {")
else_idx = shell.index("} else {", winui_idx)
tail_idx = shell.index("self.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)", winui_idx)
winui_body = shell[winui_idx:else_idx]
default_body = shell[else_idx:tail_idx]
check("S2 双族着色互斥样本",
      "[ZL2Theme onSecondaryContainer]" not in winui_body
      and "[ZL2Theme onSurface] " in winui_body
      and "[ZL2Theme onSurface]" not in default_body.replace("onSurfaceVariant", "")
      and "[ZL2Theme onSecondaryContainer]" in default_body)
# S3 插件结构覆盖面保留（setter/读取器未旁路 = fui 全维度换装契约面不变）
check("S3 插件结构覆盖面保留",
      "Ame347StructureOverride(@" in theme
      and "+ (BOOL)ame347_setPluginThemeStructure:(NSString *)pluginId" in theme)
# S4 BuildTag 代际
check("S4 BuildTag 代际锚（★Task460 重锚：每轮门禁强制重锚判例）",
      'ame415_buildTag = @"Task460 · 2026-11-21"' in buildtag)

print()
if FAILS:
    print(f"task458_selfcheck FAIL {len(FAILS)}: " + ", ".join(FAILS))
    sys.exit(1)
print("task458_selfcheck ALL PASS")
