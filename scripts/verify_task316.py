#!/usr/bin/env python3
"""verify_task316.py -- Task316 round verifier.

四批次：
  A. 伪液态玻璃圆角根修（radiusGlass 24 令牌 + 浮窗六处 + 游戏内菜单 24 对齐）
  B. 6.5.5 新功能 UI 适配（ZL2 手柄类型三选/滚轮速度/控制管理手柄组/仓库预选）
  C. 下载页分类筛选同步 ZL2（页面全链 + Modrinth facet + CF slug 解析 + i18n ×54）
  D. 文件层桌面/安卓同构（FileLayoutService 迁移引擎/跨启动器导入器/main 接线/
     整合包实例扁平化/CMake 注册/ZL2 入口行）
"""
import glob
import os
import re
import sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CHECKS = []
def check(name, cond, detail=""):
    CHECKS.append((name, bool(cond), detail))

def rd(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()

# ── A. 玻璃圆角 ──
th = rd("Natives/AmeTheme.h"); tm = rd("Natives/AmeTheme.m"); fm = rd("Natives/AmeFloatingMenu.m")
check("A1 radiusGlass 令牌声明", "+ (CGFloat)radiusGlass;" in th)
check("A2 radiusGlass 实现 24", "+ (CGFloat)radiusGlass { return 24.0; }" in tm)
check("A3 浮窗玻璃半径六处 radiusGlass", fm.count("[AmeTheme radiusGlass]") >= 6, f"count={fm.count('[AmeTheme radiusGlass]')}")
check("A4 浮窗零 radiusL 残留", "[AmeTheme radiusL]" not in fm)
check("A5 游戏内菜单面板 24 对齐", "ame252_glassViewWithCornerRadius:24.0" in rd("Natives/SurfaceViewController+Navigation.m"))

# ── B. 6.5.5 新功能 UI 适配 ──
sp = rd("Natives/ZL2SettingPages.m")
check("B1 手柄类型三选 nintendo", '@"nintendo"' in sp and "controller_configurator.title.type.nintendo" in sp)
check("B2 nintendo_layout 联写", 'setPrefBool(@"control.nintendo_layout", [key isEqualToString:@"nintendo"]);' in sp)
check("B3 滚轮速度行 25-300", 'minimum:25 maximum:300 suffix:@"%"]' in sp and 'setPrefFloat(@"control.scroll_speed"' in sp)
check("B4 控制管理手柄映射组", "ame_scanGamepads" in sp and "control.default_gamepad_ctrl" in sp)
check("B5 手柄仓库直达分类2", "repo.initialCategoryIndex = 2;" in sp)
rh = rd("Natives/ControlRepoViewController.h"); rm = rd("Natives/ControlRepoViewController.m")
check("B6 仓库页 initialCategoryIndex 接口+应用", "initialCategoryIndex" in rh and "self.initialCategoryIndex > 0" in rm)

# ── C. 分类筛选全链 ──
page = rd("Natives/ZL2AssetSearchViewController.m")
check("C1 页面 categoryFilter 属性+面板字段", "categoryFilter" in page and "categoryFieldControl" in page)
check("C2 category 键透传", 'filters[@"category"] = self.categoryFilter;' in page)
check("C3 分类 slug 表五类型", all(k in page for k in ('@"mod":', '@"modpack":', '@"resourcepack":', '@"shader":', '@"world":')))
check("C4 Modrinth categories facet", "[\\\"categories:%@\\\"]" in rd("Natives/installer/modpack/ModrinthAPI.m"))
cf = rd("Natives/installer/modpack/CurseForgeAPI.m")
check("C5 CF slug 解析器+categories 参数", "ame316_categoryIdForSlug" in cf and 'params[@"categories"] = ame316_catId.stringValue;' in cf)
check("C6 CF 匹配失败静默不筛", "not matched under classId" in cf)
i18n_ok = 0
for p in glob.glob("Natives/resources/*.lproj/Localizable.strings"):
    t = rd(p)
    if '"dl.asset.filter.category"' in t and '"dl.asset.category.any"' in t:
        i18n_ok += 1
check("C7 i18n 双键 ×54 表", i18n_ok == 54, f"tables={i18n_ok}")
check("C8 objc runtime 导入", "#import <objc/runtime.h>" in page)

# ── D. 文件层桌面/安卓同构 ──
flh = rd("Natives/FileLayoutService.h"); flm = rd("Natives/FileLayoutService.m")
check("D1 服务头注释三件套", "shared_core" in flh and "custom_gamedir" in flh)
check("D2 共享核心符号链接化", "fl_absorbIntoSharedCoreDir" in flm and "shared_core" in flm)
check("D3 回滚护栏（链接失败退回）", "rolled back" in flm)
check("D4 整合包实例扁平化", "custom_gamedir/%@ (from instance" in flm)
check("D5 profile gameDir 绝对路径重写", "ame316_rewriteProfilesAt" in flm and "宁不迁移不误伤" in flm)
check("D6 跨启动器导入五识别", all(k in flm for k in ("MultiMC/Prism", ".minecraft 全量根", "HMCL/PCL", "mmc-pack.json", "launcher_profiles.json")))
check("D7 导入只拷不删", "copyItemAtPath" in flm and flm.count("removeItemAtPath:src") == 0)
main_m = rd("Natives/main.m")
check("D8 main 预 init 迁移接线", "[FileLayoutService ame316_migrateIfNeeded];" in main_m)
mis = rd("Natives/ModpackImportService.m")
check("D9 整合包工作区根=instances 顶层", b'stringByAppendingPathComponent:@"instances"' in open('Natives/ModpackImportService.m','rb').read())
check("D10 profile gameDir 绝对路径写", "return [self absoluteGameDirForModpackId:modpackId];" in mis)
cm = rd("Natives/CMakeLists.txt")
check("D11 CMake 注册 FileLayoutService.m", "FileLayoutService.m" in cm)
check("D12 ZL2 启动器页双入口行", "游戏目录与实例" in sp and "导入外部启动器数据" in sp)
check("D13 UniformTypeIdentifiers 链接", "UniformTypeIdentifiers" in cm)

# ── 平衡性附加（括号）──
import subprocess
for f in ["Natives/FileLayoutService.m", "Natives/ZL2AssetSearchViewController.m",
          "Natives/ZL2SettingPages.m", "Natives/AmeFloatingMenu.m",
          "Natives/ModpackImportService.m"]:
    t = rd(f)
    head = subprocess.run(["git", "show", f"HEAD:{f}"], capture_output=True, text=True).stdout
    # 判据：与 HEAD 的括号差值不变（task139 注释感知扫描为本仓权威平衡门禁，
    # 此处只防本轮净引入不平衡——ModpackImportService 注释含失衡 ASCII 括号为存量）
    delta_now = (t.count("{") - t.count("}"), t.count("(") - t.count(")"))
    delta_head = (head.count("{") - head.count("}"), head.count("(") - head.count(")"))
    check(f"E平衡 {os.path.basename(f)}", delta_now == delta_head, f"{delta_head}->{delta_now}")

passed = sum(1 for _, ok, _ in CHECKS if ok)
failed = [(n, d) for n, ok, d in CHECKS if not ok]
print(f"\nverify_task316: {passed} passed, {len(failed)} failed")
if failed:
    print("FAILED:", [n for n, _ in failed])
    for n, d in failed:
        if d: print(f"  {n}: {d}")
    sys.exit(1)
print("ALL GREEN")
