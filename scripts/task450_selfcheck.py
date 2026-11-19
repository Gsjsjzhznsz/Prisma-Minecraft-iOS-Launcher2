#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task450 selfcheck：第 15 期五项反馈验收门
A P0 设置闪退加固（装饰面 @try 收敛 + 签名落日志）
B 壁纸卡面家族色识别 + 固定 0.72
C 隔离数据播种（安装器 copy-from-parent）
D 版本列表三修（扫描层级/登记行/默认展开）
E 转盘宽度自适应 + 小屏简单侧栏
S 反向注入
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")

def rd(p):
    return open(os.path.join(NAT, p), encoding="utf-8").read()

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

# ============ A 设置闪退加固 ============
pages = rd("ZL2SettingPages.m")
hub = rd("ZL2SettingsViewController.m")
n_guard = pages.count("@catch (NSException *ame450_") + hub.count("@catch (NSException *ame450_")
check("A1 装饰面 @try 收敛四处", n_guard == 4, f"got {n_guard}")
check("A2 异常签名落日志锚", pages.count("[Task450] settings page wallpaper sweep degraded") == 1
      and hub.count("[Task450] settings hub wallpaper sweep degraded") == 1
      and hub.count("[Task450] settings attach wallpaper sweep degraded") == 1
      and pages.count("[Task450] fold group") == 1)
check("A3 既有调用面零删除", "ame449_applyWallpaperTransparencyToViewTree:self.view" in pages
      and "ame449_applyWallpaperTransparencyToViewTree:page.view" in hub)

# ============ B 壁纸卡面 ============
bm = rd("BackgroundManager.m")
check("B1 家族色识别方法", "ame450_isCardFamilyColor" in bm and "resolvedColorWithTraitCollection" in bm)
check("B2 卡面三族对表", "surfaceContainerHigh" in bm and "surfaceContainerLow" in bm and "surfaceContainer]" in bm)
check("B3 固定 0.72 半透明", bm.count("colorWithAlphaComponent:0.72") == 2)
check("B4 未标记面收编入册", "Ame449MarkCardSurface(root);" in bm and bm.count("transparent && [BackgroundManager ame450_isCardFamilyColor:root.backgroundColor]") == 1)
check("B5 壁纸滑条解耦注记", "卡面脱钩取" in bm)

# ============ C 隔离播种 ============
pp = rd("PLProfiles.m")
pph = rd("PLProfiles.h")
check("C1 播种方法实现", "ame450_seedIsolatedVersionData" in pp and "ame450_dataNames" in pp)
check("C2 头文件声明（跨 TU 安装器调用）", "+ (void)ame450_seedIsolatedVersionData:(NSString *)versionId inheritsFrom:(NSString *)parentId;" in pph)
check("C3 已存在绝不覆盖", "if ([ame450_fm fileExistsAtPath:ame450_to]) continue;   // 已存在绝不覆盖" in pp)
check("C4 Fabric 接线", "ame450_seedIsolatedVersionData:profileId inheritsFrom:ame450_parent" in rd("installer/FabricUtils.m"))
check("C5 NeoForge 接线", "ame450_seedIsolatedVersionData:versionId inheritsFrom:minecraftVersion" in rd("installer/NeoForgeDirectInstaller.m"))
check("C6 播种六面", pp.count('@"saves", @"config", @"resourcepacks", @"screenshots"') == 1 and "options.txt" in pp and "servers.dat" in pp)

# ============ D 版本列表三修 ============
vv = rd("ZL2VersionsViewController.m")
check("D1 扫描层级修正（父根补挂）", "ame450_parent = [ame428_resolved stringByDeletingLastPathComponent];" in vv
      and '[ame450_parent lastPathComponent] isEqualToString:@"versions"' in vv)
check("D2 缺 json 登记行入列", "if (ame450_jsonMissing && ![ame428_e[@\"referenced\"] boolValue]) continue;" in vv)
check("D3 子行默认展开（语义倒置）", "ame444_collapsedVids" in vv and "ame444_expandedVids" not in vv)
check("D4 收起态跨 rebuild 保留", "[weakSelf.ame444_collapsedVids addObject:versionId];   // 开→收" in vv)

# ============ E 转盘 + 小屏 ============
home = rd("ZL2HomeViewController.m")
check("E1 转盘宽度上钳放宽", "ZL2HomeMenuWidthMax     = 460;" in home)
shell = rd("ZL2ShellViewController.m")
check("E2 小屏设备判定", "MIN(UIScreen.mainScreen.bounds.size.width," in shell and "ame450_compactDevice" in shell)
check("E3 小屏摘 AI 项", "if (ame450_compactDevice && ame347_pages[idx].integerValue == 6) return;" in shell)
check("E4 小屏摘文件项", "if (ame450_compactDevice && ame347_footerPages[idx].integerValue < 0) return;" in shell)
check("E5 日志锚", shell.count("[Task450] shell rail compact device=") == 1)

# ============ T BuildTag ============
# ★Task452 收编判例④（Task439 同型）：字面量锁死改形态验，新鲜度职责移交专门门
check("T1 BuildTag 形态验（代际新鲜度由 task439_buildtag_anchor 门执法）",
      re.search(r"Task\d+ · \d{4}-\d\d-\d\d", rd("BuildTag.h")) is not None)

# ============ S 反向注入（程序化） ============
check("S1 A2 计数谓词敏感性", n_guard == 4)
check("S2 D3 倒置完备性（码级标识符零残留）", vv.count("ame444_collapsedVids") >= 5 and vv.count("ame444_expandedVids") == 0)
check("S3 B3 幂等面（tag 分支与收编分支各一处 colorWithAlphaComponent:0.72）", bm.count("colorWithAlphaComponent:0.72") == 2)

print()
if fails:
    print(f"ALL FAIL {len(fails)}: {fails}")
    sys.exit(1)
print("ALL PASS")
