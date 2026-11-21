#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task461 自检门：非折叠钦定 + 「回退3天以前」全树回退轮（用户指令「这才是3天前」+ 粉色装机截图 235C8E02 定谳）。

★Task463 判例翻转（2026-11-22）：用户明确诉求「设置折叠怎么没有恢复」——推翻本门
原判「设置折叠退役」一项（X1/X6-2 由「归零执法」翻转为「在场执法」）；其余锁定面
（壁纸清扫/455/456/458/459/460/topbar 粉色钦定）维持退役零容忍不变。

回退构成（Task461 = Task448 构建树 3f34a1d606 + 四件外科重应用）：
  基线 3f34a1d606（Task448 · 2026-11-18，用户钦定「3天以前的样子」= 粉色 bare 壳 + topbar 蓝图 + 浅色色板）
  + Task451 JIT26ExecPreflight（游戏发射空壳 RX 黑屏防线，议题#3 慢性面）
  + Task452 JSC 解释器钉死 + 首帧链分段签名 + 主页/背景宿主 @try（打开即崩类防线；清扫挂点 hunk 随 449 退役剔除）
  + Task457 dyld 旁路 Safe 三重防线（op4 brk 无应答闪退根修，依赖 451 预检）
  + Task458 下载中心仓库三轨 hunk 单面移植（用户钦定「下载中心的插件和控件给我恢复」）
  + Task459 余量钳制最小适配（n≤5 分支同享 fmin(full,avail)，卡尾刷新/齿轮恒在首屏）

随树退役面（X 全仓零容忍）：
  Task449 设置折叠 38 组（ame449_enableCollapsing 族 + ZL2SettingCards 折叠态）
  Task449/450 壁纸清扫管线（ame449_sweep / ame450_isCardFamilyColor——后者即「打开即闪退」PC=0 雷）
  Task455 启动抑制/会话级展开/版本缓存（ame455_consumeStartupRebuild）
  Task456 蓝图翻转+回声沉降窗+去抖（默认蓝图必须保持 topbar=用户粉色钦定形态）
  Task458 选中双族/预览旗标（ame347_shellLayoutPluginOverridden——裸壳默认下导航轨语义面不适用）
  Task459 chrome 重钉字面量 / Task460 非折叠退役符号
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


print("== R 修复形态执法（重应用四件 + 钳制） ==")
jl = rd("Natives/JavaLauncher.m")
check("R1-1 Task451 预检函数在场", "ame451" in jl and "Preflight" in jl)
check("R1-2 Task451 逃生阀注册（debug 段键名无前缀形态）", '"jit26_preflight_disable": @NO' in rd("Natives/PLPreferences.m"))
dyld = rd("Natives/dyld_bypass_validation.m")
check("R2-1 Task457 Safe 变体在场", "JIT26PrepareRegionSafe" in dyld or "JIT26PrepareRegionForPatchingSafe" in dyld)
check("R2-2 Task457 vm_protect 返回值执法", "vm_protect" in dyld)
check("R2-3 Task457 JavaLauncher 诊断窗调用点", "Task457: dyld library-validation bypass incomplete" in jl)
main_m = rd("Natives/main.m")
check("R3-1 Task452 JSC 钉死 setenv", 'setenv("JSC_useJIT", "0", 1)' in main_m)
check("R3-2 Task452 逃生阀注册（debug 段键名无前缀形态）", '"plugin_jit_allow": @NO' in rd("Natives/PLPreferences.m"))
home = rd("Natives/ZL2HomeViewController.m")
check("R3-3 Task452 主页 @try 收敛", "ame452_buildOK" in home)
bg = rd("Natives/ZL2BackgroundHost.m")
check("R3-4 Task452 背景宿主 @try", "@catch" in bg)
dl = rd("Natives/ZL2DownloadViewController.m")
check("R4-1 下载三轨-控件仓库", "ame369.common.control_repo" in dl)
check("R4-2 下载三轨-手柄仓库", "ame369.common.gamepad_repo" in dl)
check("R4-3 下载三轨-插件仓库", "ame318.repo.title" in dl)
check("R5-1 钳制 n≤5 分支同享 fmin(full,avail)",
      "ame414_target = fmax((CGFloat)ZL2HomeVersionFlowItemH, fmin(ame414_full, ame414_avail));" in home)
check("R5-2 钳制旧早退 set(ideal) 退役", "_ame414_versionHeight.constant = ame414_ideal;" not in home)
check("R5-3 Task443 补减项保留", "_quickNavCard.frame.size.height" in home and "ZL2HomeCardGap" in home)
check("R5-4 Task415c 软下限保留", "ame414_floor3" in home)

print("== X 回退面归零（全仓扫描） ==")
SCAN_FILES = list((ROOT / "Natives").rglob("*.m")) + list((ROOT / "Natives").rglob("*.h"))


def scan_count(pattern):
    n = 0
    pat = re.compile(pattern)
    for f in SCAN_FILES:
        n += len(pat.findall(f.read_text(encoding="utf-8", errors="replace")))
    return n


check("X1-1 折叠 API 在场（★Task463 判例翻转：用户诉求恢复设置折叠，推翻 461 非折叠钦定之折叠项）",
      scan_count(r"ame449_enableCollapsing") >= 3
      and scan_count(r"ame449_isCollapsed") >= 3
      and scan_count(r"ame449_applyCollapsedAnimated") >= 3)
check("X1-2 折叠态属性在场（Task463 翻转）", scan_count(r"ame449_collapsed") >= 8)
check("X2-1 壁纸清扫符号归零", scan_count(r"ame449_sweep") == 0)
check("X2-2 PC=0 雷符号归零", scan_count(r"ame450_isCardFamilyColor") == 0)
check("X2-3 壁纸透明管线归零", scan_count(r"ame449_applyWallpaperTransparency") == 0)
check("X3-1 Task455 启动抑制归零", scan_count(r"ame455_consumeStartupRebuild") == 0)
check("X3-2 Task455 会话折叠键归零", scan_count(r"ame455\.") == 0)
check("X4-1 Task456 沉降窗/去抖归零", scan_count(r"ame456_debounceArmed|ame456_versionCardHeight|ame456_versionCardChrome") == 0)
check("X4-2 Task459 钳制字面量归零", scan_count(r"ame459_") == 0)
check("X4-3 Task460 非折叠退役归零", scan_count(r"ame460_") == 0)
check("X5-1 Task458 选中双族归零", scan_count(r"ame347_shellLayoutPluginOverridden") == 0)
theme = rd("Natives/ZL2Theme.m")
check("X6-1 默认蓝图保持 topbar（粉色钦定形态）", 'Ame347StructureOverride(@"shellLayout", @"topbar")' in theme
      and 'Ame347StructureOverride(@"shellLayout", @"navigationview")' not in theme)
cards = rd("Natives/ZL2SettingCards.m")
check("X6-2 设置卡折叠态在场（Task463 翻转）", "ame449_enableCollapsingWithTitle" in cards)
check("X7-1 448 侧栏折叠机制原样在场（Task376 设计）", "ame376_paneCollapsed" in rd("Natives/ZL2ShellViewController.m"))
check("X7-2 壁纸功能本体在场（ame429，数据面恢复后可用）", "ame429" in rd("Natives/ZL2BackgroundHost.m"))

print("== S 敏感性样本 ==")
tag = rd("Natives/BuildTag.h")
check("S1 BuildTag Task464 · 2026-11-22（op4 误杀修正轮代际重锚）", "Task464 · 2026-11-22" in tag)
en = rd("Natives/resources/en.lproj/Localizable.strings")
zh = rd("Natives/resources/zh-Hans.lproj/Localizable.strings")
check("S2 ame451 键在场（en/zh-Hans）", "ame451" in en and "ame451" in zh)
check("S3 ame457 键在场（en/zh-Hans）", "ame457" in en and "ame457" in zh)
check("S4 电池注册 task461", "task461_selfcheck" in rd("scripts/task432_gate_battery.sh"))

print(f"\\n========================================")
if FAILS:
    print(f"task461_selfcheck RED —— {len(FAILS)} failed / {CHECKS[0]} total")
    sys.exit(1)
print(f"task461_selfcheck: {CHECKS[0]} passed, 0 failed")
print("ALL GREEN")
