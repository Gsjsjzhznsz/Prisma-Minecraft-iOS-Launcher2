#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task456 自检门（三症状残余落码轮）：
  ① 启动卡死残余 = 重建回声链根修三件套（Task346 沉降窗 / Ame380 外观去抖 /
     SceneDelegate 游戏面换根保护）
  ② 侧边栏齿轮按钮不显示 = 版本卡结构性重钉（卡高常量单点 + flow 高自链推导
     + 矮窗劣化 target 恒 ≤ avail）
  ③ 小屏设备不是 ZL2 侧边栏 = shellLayout 默认蓝图 navigationview + 紧凑设备
     常驻门槛 500pt 自适应
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


theme = (ROOT / "Natives" / "ZL2Theme.m").read_text(encoding="utf-8", errors="replace")
shell = (ROOT / "Natives" / "ZL2ShellViewController.m").read_text(encoding="utf-8", errors="replace")
scene = (ROOT / "Natives" / "SceneDelegate.m").read_text(encoding="utf-8", errors="replace")
home = (ROOT / "Natives" / "ZL2HomeViewController.m").read_text(encoding="utf-8", errors="replace")
buildtag = (ROOT / "Natives" / "BuildTag.h").read_text(encoding="utf-8", errors="replace")

print("== R 修复形态执法 ==")

# R1 沉降窗：静态声明 + post 入口拦截 + 窗口更新 + 吞掉留痕
check("R1a 沉降窗静态声明（ame456_settleUntil）",
      "static CFAbsoluteTime ame456_settleUntil = 0.0;" in theme)
check("R1b post 入口沉降拦截（先于根探测，吞掉即 return）",
      re.search(r"static void ame346_postRootRebuildNow\(void\) \{\s*\n\s*@try \{\s*\n\s*// ★ Task456：沉降窗拦截", theme) is not None)
check("R1c 沉降窗拦截判据（settleUntil > 0 && now < settleUntil）",
      "if (ame456_settleUntil > 0.0 && ame456_now0 < ame456_settleUntil)" in theme)
check("R1d 沉降窗窗口更新（广播前 +0.8s）",
      "ame456_settleUntil = ame346_lastRebuildAt + 0.8;" in theme)
check("R1e 吞掉留痕日志",
      "Task456: root rebuild request swallowed in settle window" in theme)

# R2 shellLayout 默认蓝图（getter 返回面 + 旧 topbar 回退 getter 退役；setter 日志
#    回退参数同步 navigationview = 有效值日志语义一致）
check("R2 shellLayout 默认 navigationview（小屏 ZL2 侧栏内置化）",
      'return Ame347StructureOverride(@"shellLayout", @"navigationview");' in theme
      and 'return Ame347StructureOverride(@"shellLayout", @"topbar");' not in theme)

# R3 Ame380 外观广播去抖
check("R3a 去抖待播态（armed + pending 终值覆盖）",
      "static BOOL ame456_debounceArmed = NO;" in shell
      and "static BOOL ame456_pendingDark = NO;" in shell
      and "if (ame456_debounceArmed) return;" in shell)
check("R3b 350ms 延后广播",
      "(int64_t)(0.35 * NSEC_PER_SEC)" in shell)
check("R3c 翻回零广播（终值 == 上次广播值即 return）",
      "if (ame380_hasLastDark && ame456_finalDark == ame380_lastDark) return;" in shell)
check("R3d 广播面唯一（AmeAppearanceTraitChanged 在壳内恰 1 处）",
      shell.count('postNotificationName:@"AmeAppearanceTraitChanged"') == 1)

# R4 游戏面换根保护
check("R4a 非壳根跳过换根",
      "![ame456_currentRoot isKindOfClass:[ZL2ShellViewController class]]" in scene)
check("R4b 跳过留痕日志",
      "Task456: root rebuild skipped (non-shell root" in scene)

# R5 紧凑设备常驻门槛（判定同款字面量在壳内 ≥2 处：Task450⑥ 原判定 + Task456
#    门槛自适应；500/640 双档三元式在位）
check("R5 紧凑设备门槛自适应（<500 判定同款 + 500/640 双档）",
      "CGFloat ame456_regularMin = ame456_compactDevice ? 500.0 : ZL2ShellRegularMinWidth;" in shell
      and shell.count("MIN(UIScreen.mainScreen.bounds.size.width,") >= 2)

# R6 版本卡结构性重钉
check("R6a 卡高常量单点（ame456_versionCardHeight）",
      "@property (nonatomic, strong) NSLayoutConstraint *ame456_versionCardHeight;" in home
      and "_ame414_versionHeight" not in home)
check("R6b flow 高自链推导（flow.bottom = 尾行钮.top−6，旧 top=flow.bottom+6 退役）",
      "[_versionFlow.bottomAnchor constraintEqualToAnchor:_versionSettingsButton.topAnchor constant:-6]," in home
      and "constraintEqualToAnchor:_versionFlow.bottomAnchor constant:6]" not in home)
check("R6c 卡高写入单点（ame456_setVersionCardFlowHeight，@implementation 内）",
      "- (void)ame456_setVersionCardFlowHeight:(CGFloat)ame456_flow {" in home
      and home.index("- (void)ame456_setVersionCardFlowHeight:(CGFloat)ame456_flow {") > home.index("@implementation ZL2HomeViewController"))
check("R6d 矮窗劣化 target 恒 ≤ avail（单行绝对下限，三行软下限越权退役）",
      "fmax(ZL2HomeVersionFlowItemH, fmin(ame414_full, ame414_avail))" in home
      and "ame414_softFloor" not in home)
check("R6e 卡高初值 = 五行口径 + chrome（首布局前零视觉回退）",
      "_versionFlow.viewportHeight\n                                                             + 2.0 * ZL2HomeCardPadding + 6.0 + ZL2HomeCardFooterHeight + 4.0];" in home)

print("== X 全仓扫描 ==")

# X1 AppLanguageChanged 广播面清单锁定（Task455 X2 既有面 + 本轮零新增）
ame_surface = theme.count('postNotificationName:@"AppLanguageChanged"')
setting_surface = (ROOT / "Natives" / "ZL2SettingPages.m").read_text(encoding="utf-8", errors="replace").count('postNotificationName:@"AppLanguageChanged"')
transfer_surface = (ROOT / "Natives" / "DataTransferService.m").read_text(encoding="utf-8", errors="replace").count('postNotificationName:@"AppLanguageChanged"')
check("X1 AppLanguageChanged 广播面 = 锁定清单 1+1+2（零新增）",
      ame_surface == 1 and setting_surface == 1 and transfer_surface == 2,
      f"ZL2Theme={ame_surface} SettingPages={setting_surface} DataTransfer={transfer_surface}")

# X2 沉降窗不留第二实现（全仓 settle 家族仅 ZL2Theme）
hits = []
for p in (ROOT / "Natives").glob("*.m"):
    if p.name.startswith("ame") or "external" in str(p):
        continue
    t = p.read_text(encoding="utf-8", errors="replace")
    if "ame456_settleUntil" in t and p.name != "ZL2Theme.m":
        hits.append(p.name)
check("X2 沉降窗实现面唯一（ZL2Theme.m）", not hits, ",".join(hits))

# X3 旧断钉形态全仓清零（flow 独立高常量 + 尾行 top=flow.bottom+6 家族）
legacy = []
for p in (ROOT / "Natives").glob("ZL2*.m"):
    t = p.read_text(encoding="utf-8", errors="replace")
    if "constraintEqualToAnchor:_versionFlow.bottomAnchor constant:6]" in t:
        legacy.append(p.name)
check("X3 尾行 top=flow.bottom 断钉形态全仓零容忍", not legacy, ",".join(legacy))

# X4 外观广播旧即时形态清零（dedup armed 直播退役，防回潮）
check("X4 Ame380 即时广播旧形态退役（dedup armed 直播清零）",
      'appearance broadcast dark=%d (dedup armed)' not in shell)

print("== S 敏感性自证 ==")

# S1 沉降窗不吞首建 flush（初值 0.0 = 未开播，首帧 flush 必放行）
check("S1 沉降窗初值 0.0（未广播前 flush 必放行）",
      "static CFAbsoluteTime ame456_settleUntil = 0.0;" in theme)
# S2 真翻转放行样本：去抖后终值 != 上次广播值 → 广播路径存在
check("S2 去抖真翻转放行路径（broadcast 调用在翻回守卫之后）",
      shell.index("if (ame380_hasLastDark && ame456_finalDark == ame380_lastDark) return;")
      < shell.index('postNotificationName:@"AmeAppearanceTraitChanged"'))
# S3 navigationview 默认不锁插件覆盖面（Ame347StructureOverride 覆盖读取器仍在位）
check("S3 插件结构覆盖面保留（覆盖读取器未旁路）",
      "Ame347StructureOverride(@" in theme)
# S4 BuildTag 代际
check("S4 BuildTag 代际锚（★Task457 重锚：每轮门禁强制重锚判例）",
      'ame415_buildTag = @"Task458 · 2026-11-20"' in buildtag)

print()
if FAILS:
    print(f"task456_selfcheck FAIL {len(FAILS)}: " + ", ".join(FAILS))
    sys.exit(1)
print("task456_selfcheck ALL PASS")
