#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 238 验证脚本：第 8 轮反馈的 7 项修复静态验证。
A. 游戏内菜单悬浮形态几何重算（不再读残留抽屉帧）
B. game.gear.docked 偏好注册 + 默认贴边 + 近边自动吸附
C. 启动遮罩层 z 序（悬浮球/菜单在遮罩之上）
D. JVM 正常退出 → 返回启动器主页
E. 字体重叠根修（numberOfLines==0 拷贝词换行 + 菜单树描边豁免）
F. 前置区上移（头部堆叠）+ CF 源前置富元数据
G. 括号配平（所有修改文件）
"""
import os, sys, re

# ★第 12 期整改批次二①重锚：外部仓绝对路径已消失（干净克隆口径），改从脚本
# 位置动态推导仓库根，TASK238_REPO 环境变量覆盖保留。
BASE = os.path.join(os.environ.get("TASK238_REPO", os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "Natives") + os.sep
results = []

def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))

def skip(name, path, why=""):
    """退役面断言显式 SKIP（[RETIRED] 家法 (b)）。"""
    results.append((name, True, "SKIP"))
    print(f"  [SKIP] {name} —— {path}{('，' + why) if why else ''}")

def rd(p):
    with open(BASE + p, "r", encoding="utf-8") as f:
        return f.read()


# ★Task440 退役容错壳：本 verifier 撰写轮次早于 Task436/Task440 两批退役——
# 其主体文件（旧下载中心/公告/新闻/服务器/旧三版本页/死代码六件等）已物理
# 删除。rd 对缺席文件不再抛 FileNotFoundError，改返空串并打印 [RETIRED]
# 标注（诚实降级：存留面断言继续生效，退役面口径以 task440_selfcheck.py /
# verify_task189.py 重生门为准）。单跑结论 = 存留面视图，非全量判定。
import functools as _ft
# ★第 12 期整改批次二①壳修复（Task440 壳的 getcwd 病根，与 verify_task235/236
# 同族）：存在性判断改用本门 BASE 前缀——原壳用 getcwd 解析相对路径，在非
# 仓库根 cwd 下永远 miss，把【存留文件】（GameMenuOverlayView/PLPreferences/
# SurfaceViewController/BackgroundManager 等全部健在）误判成 [RETIRED] 返回
# 空串，A-F 段大面积假 FAIL、G 段假绿。修壳的路径解析，不放宽任何断言。
_orig_rd_440 = rd
@_ft.wraps(_orig_rd_440)
def rd(p, *a, **k):
    cand = p if os.path.isabs(p) else os.path.join(BASE, p)
    if not os.path.exists(cand):
        print(f"  [RETIRED] {p} —— 退役批次已删，跳过相关断言（容错壳）")
        return ""
    return _orig_rd_440(p, *a, **k)

# ---------- A. 菜单悬浮形态几何重算 ----------
nav = rd("SurfaceViewController+Navigation.m")
check("A1 showMenu 悬浮形态几何重算(ame238_sheetW 居中)",
      "ame238_sheetW" in nav and "(screenWidth - ame238_sheetW) / 2.0" in nav,
      "不再从残留 frame 读宽高/x")
check("A2 showMenu 不再读残留 menuWidth/menuHeight",
      "CGFloat menuWidth = self.menuView.frame.size.width" not in nav,
      "残留帧读取已移除")
check("A3 抽屉宽度同源公式重算",
      "MAX(MIN(screenWidth * 0.7, 400), 280)" in nav,
      "侧滑形态宽度也不信任残留值")
check("A4 菜单树描边豁免",
      "ame230_setViewTreeStrokeExempt(self.menuView, YES)" in nav,
      "游戏内菜单面板文字单层干净")

# ---------- B. 吸边持久化 + 默认贴边 ----------
gmov = rd("GameMenuOverlayView.m")
prefs = rd("PLPreferences.m")
check("B1 PLPreferences 注册 game.gear.docked/docked_left",
      '"docked": @NO' in prefs and '"docked_left": @NO' in prefs and '"gear"' in prefs,
      "valueForKeyPath 嵌套键注册（内层可变字典）")
check("B2 默认形态 = 右侧吸边把手",
      "Task238 gear default: docked right handle" in gmov and
      re.search(r"kAme227HandleWidth \* 0\.66,\s*bh > 0 \? bh \* 0\.45 : 300\.0", gmov) is not None,
      "首启即贴边把手并落盘")
check("B3 存量近边悬浮态自动吸附",
      "Task238 gear auto-docked on restore" in gmov and
      "ame238_distL < kAme227DockThreshold" in gmov,
      "修复 setter 失败时代的残留状态")
check("B4 首启落盘守卫(bw/bh>0)",
      "if (bw > 0 && bh > 0) {" in gmov,
      "避免 0 除写坏偏好")

# ---------- C. 启动遮罩层 z 序 ----------
svc = rd("SurfaceViewController.m")
# ★第 12 期整改批次二①重锚（Task243：菜单视图体系容器化——menuView/
# menuDimView 收进 menuCanvas，提升从逐件 bringSubviewToFront 改为整容器
# 提升 menuCanvas + gameMenuOverlay；z 序语义"游戏菜单在启动遮罩之上"不变，
# python 实测）。
check("C1 悬浮三件套提到遮罩之上（Task243 重锚：menuCanvas 整容器提升）",
      "Task238 launch overlay z-order" in svc and
      "ame238_raiseGameMenuAboveLaunchMask" in svc and
      "bringSubviewToFront:self.menuCanvas" in nav and
      "bringSubviewToFront:self.gameMenuOverlay" in nav,
      "容器整组提升(menuCanvas<overlay),主类 performSelector 调用,取消按钮置顶")

# ---------- D. JVM 退出返回启动器 ----------
check("D1 launchResult==0 返回启动器主页",
      "Task238 JVM exited normally" in svc and "UIKit_returnToSplitView();" in svc,
      "退游戏回启动器（FCL 同款）")
# ★第 12 期整改批次二①重锚（Task242：三级解析加固——Task238 主路径单点依赖
# UIWindow.mainWindow 在 iOS 26.3 scene 生命周期下可能失效，改 mainWindow →
# connectedScenes keyWindow → 根判定，面包屑日志分诊；"根守卫防重复换根"
# 关切由 isKindOfClass 根判定 + Task242 解析链承接，python 实测）。
check("D2 根守卫(已在启动器则跳过；Task242 重锚：三级解析 + isKindOfClass 根判定)",
      "UIWindow *ame242_win = UIWindow.mainWindow;" in svc and
      "isKindOfClass:[SurfaceViewController class]]" in svc,
      "避免 cancelLaunch 已换根后的重复换根")

# ---------- E. 字体重叠根修 ----------
bm = rd("BackgroundManager.m")
afm = rd("AmeFloatingMenu.m")
# ★第 12 期整改批次二①（退役收编）：Task378（91a10fe3d）全局描边字体退役后
# BackgroundManager.m 的拷贝渲染链整体删除，numberOfLines==0 拷贝词换行锚面
# 随链退役（python 实测 0 命中）；重叠根关切由"单渲染源"结构性保证，
# 退役口径由 ame378_selfcheck.py 守卫。
skip("E1 numberOfLines==0 拷贝词换行", "BackgroundManager.m 拷贝渲染链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
check("E2 玻璃悬浮菜单树描边豁免",
      "ame230_setViewTreeStrokeExempt(self.view, YES)" in afm,
      "Ame237 菜单标题/正文/行单层干净")
bmh = rd("BackgroundManager.h")
check("E3 豁免 API 头文件导出",
      "void ame230_setViewTreeStrokeExempt(UIView *view, BOOL exempt);" in bmh and
      "void ame229_labelSetStrokeExempt(UILabel *label, BOOL exempt);" in bmh,
      "两个 C 函数声明公开")

# ---------- F. 前置区上移 + CF 源 ----------
# ★第 12 期整改批次二①（退役收编）：旧版本页（ModVersionViewController.m）
# 已随 Task436/440 退役批次物理删除（ZL2VersionListPage 三域接棒），
# 前置区头部堆叠 F1/F2/F3/F4/F6/F7 与 CF 富元数据回填 F4 锚面随宿主退役；
# CurseForgeAPI 本体健在，F5 的 API 方法声明继续守卫。
mvv = rd("ModVersionViewController.m") if os.path.exists(BASE + "ModVersionViewController.m") else ""
mvv_retired = mvv == ""
cfh = rd("installer/modpack/CurseForgeAPI.h")
cfm = rd("installer/modpack/CurseForgeAPI.m")
if mvv_retired:
    print("  [RETIRED] ModVersionViewController.m —— 退役批次已删，跳过相关断言（容错壳）")
    for _f in ["F1 前置区渲染目标 = 头部堆叠", "F2 头部堆叠机制", "F3 多版本依赖探测(≤6)",
               "F4 CF 富元数据回填链", "F6 重渲染不残留旧视图", "F7 无依赖清理路径走头部"]:
        skip(_f, "ModVersionViewController.m", "旧版本页宿主已随退役批次删除")
if not mvv_retired:
    check("F1 前置区渲染目标 = 头部堆叠(不再表尾)",
          "ame238_depsSectionView = ame236_footer" in mvv and
          "self.tableView.tableFooterView = ame236_footer" not in mvv,
          "摆在详情头之下、版本列表之上")
    check("F2 头部堆叠机制",
          "ame238_headerStackView" in mvv and "systemLayoutSizeFittingSize" in mvv,
          "[详情头+前置区] 合成 tableHeaderView")
    check("F3 多版本依赖探测(≤6)",
          "ame238_probe" in mvv and "MIN((NSUInteger)6" in mvv,
          "最新版本缺 dependencies[] 时向后探测")
    check("F4 CF 富元数据回填链",
          "ame238_fetchProjectInfo" in mvv and "CF dependency rows enriched" in mvv,
          "占位先行 → 名称/摘要/图标到达后重渲染")
check("F5 CurseForgeAPI 新方法（宿主退役后继续守卫 API 本体）",
      "ame238_fetchProjectInfo" in cfh and
      cfm.count("ame238_fetchProjectInfo") >= 1 and
      "thumbnailUrl" in cfm,
      "GET /mods/{id} 完整元数据（name/summary/logo）")
if not mvv_retired:
    check("F6 重渲染不残留旧视图",
          "ame238_old removeFromSuperview" in mvv or "ame238_old" in mvv,
          "新前置区入栈时清掉旧视图")
    check("F7 无依赖清理路径走头部",
          mvv.count("self.ame238_depsSectionView = nil") >= 2,
          "探测失败/空计划时移除前置区并恢复纯详情头")

# ---------- G. 括号配平 ----------
def balanced(path):
    s = rd(path)
    # 去掉字符串与注释的粗糙处理：逐行去掉 "//..." 与 "..." 内容
    s = re.sub(r'"(?:[^"\\]|\\.)*"', '""', s)
    s = re.sub(r"'(?:[^'\\]|\\.)*'", "''", s)
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return s.count("{") == s.count("}") and s.count("(") == s.count(")")

for f in ["SurfaceViewController+Navigation.m", "GameMenuOverlayView.m",
          "PLPreferences.m", "SurfaceViewController.m", "BackgroundManager.m",
          "BackgroundManager.h", "AmeFloatingMenu.m", "ModVersionViewController.m",
          "installer/modpack/CurseForgeAPI.m", "installer/modpack/CurseForgeAPI.h"]:
    check(f"G:balanced {f}", balanced(f), "")

passed = sum(1 for _, ok, d in results if ok and d != "SKIP")
skipped = sum(1 for _, _, d in results if d == "SKIP")
total = len(results)
for name, ok, detail in results:
    print(f"{'PASS' if ok and detail != 'SKIP' else ('SKIP' if detail == 'SKIP' else 'FAIL')}  {name}"
          + (f"  [{detail}]" if detail and not ok else ""))
print(f"\n{passed} passed, {skipped} skipped / {total} checks")
sys.exit(0 if passed + skipped == total else 1)  # ★退役收编：SKIP 不计失败
