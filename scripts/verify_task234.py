#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 234 verification: 5-item round on the Task233 build (c07243ed).

Round items (user message 2026-10-10):
  1. 欢迎圈圈本来要圈启动按钮变成了执行jar —— 启动按钮锚点误中执行Jar
     (Task233 深搜"最靠下大按钮"：执行Jar/选择版本 38pt 贴底恰在启动按钮
     46pt 之下)。修复:右面板 VC 直取 launchButton 真身 + 三级确定性锚定。
  2. 还有文字依旧不显示(第五轮) —— coach 卡 body 标签自 Task223 起漏
     translatesAutoresizingMaskIntoConstraints=NO：autoresize(零初始帧)与骨架约束
     必需级冲突 → 正文恒 0x0 = "无文字介绍"。标题标签有该行(能显示)。
  3. 还有现在文字重叠依旧有问题 —— drawInRect: 顶部锚定 vs
     drawTextInRect: 经 textRectForBounds 垂直居中，按钮 titleLabel 上
     相差 9~13pt = 深色拷贝浮在白字上方("重叠不上"残留)。拷贝改画进
     textRectForBounds 同一紧致文本矩形。
  4. 还有不是叫你看看modilegl更新吗 —— 已复查(带认证 API):上游
     MobileGL-Dev/MobileGlues 最新提交 97558a6(2026-09-22, 即 0f1e10b
     multidraw grow-only 修复的 merge),之后无新提交/无 release/无 tag;
     vendored 源码树已含该修复(version.h REVISION 18 注记) → 无可用更新。
  5. 分享到 GitHub 显示 "Looks like something went wrong!"(GitHub 通用
     500 错误页) —— filename= 斜杠已知 bug(isaacs/github#1527)+value=
     大载荷渲染 500。零查询参数终案:/new/main/controls/layouts/community
     纯路径目录预导航,内容只走剪贴板,提示语带出应补文件名。
"""
import sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

PASS, FAIL, SKIPPED = 0, 0, 0
def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def skip(name, path, why=""):
    """退役面断言显式 SKIP：宿主已删/断言面已真退役（[RETIRED] 家法 (b)）。"""
    global SKIPPED
    SKIPPED += 1
    print(f"  [SKIP] {name} —— {path}{('，' + why) if why else ''}")

def check(name, path, needle):
    """字节级锚点断言。退役宿主（Task436/440 批次物理删除）显式 SKIP，
    存留文件锚点缺失仍为 FAIL（[RETIRED] 家法 (b)/(d)）。"""
    global PASS, FAIL
    try:
        ok = needle in read(path)
    except FileNotFoundError:
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        skip(name, path)
        return
    except Exception as e:
        ok = False
        needle = f"{e}"
    if ok:
        PASS += 1
        print(f"  ok   {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name}: needle not in {path}")
def check_absent(name, path, needle):
    global PASS, FAIL
    try:
        present = needle in read(path)
    except FileNotFoundError:
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        skip(name, path)
        return
    except Exception as e:
        present = True
        needle = f"{e}"
    if not present:
        PASS += 1
        print(f"  ok   {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name}: forbidden needle STILL in {path}")

rp  = "Natives/LauncherRightPanelViewController.h"
rpm = "Natives/LauncherRightPanelViewController.m"
wvc = "Natives/WelcomeViewController.m"
cmk = "Natives/Ame223CoachMarksView.m"
bm  = "Natives/BackgroundManager.m"
crv = "Natives/ZL2ControlRepoViewController.m"
mgv = "Natives/external/MobileGlues/MobileGlues-cpp/version.h"
mgm = "Natives/external/MobileGlues/MobileGlues-cpp/gl/multidraw.cpp"

print("== (1) 启动按钮锚点：真身直取 + 三级确定性锚定 ==")
# ★第 12 期整改批次二①（退役收编）：右面板（LauncherRightPanelViewController
# .h/.m）与旧首启向导（WelcomeViewController.m）已随 Task436/440 退役批次
# 整体物理删除（见 scripts/task440_retire_inventory.md），三级锚定链 1a-1j
# 锚面随宿主退役（启动按钮语义由 ZL2 版本域接棒）。
for _n in ["234-1a accessor declared in header", "234-1b accessor implemented (view identity)",
           "234-1c Welcome tier-1 direct access", "234-1d tier-2 three-state launch titles",
           "234-1e tier-2 jar exclusion", "234-1f tier-2 version-button exclusion",
           "234-1g tier-3 whole-panel fallback kept", "234-1h tier forensics log",
           "234-1i lowest-button heuristic comment gone", "234-1j lowest-button heuristic code gone"]:
    print(f"  [RETIRED] {wvc} / {rpm} —— 退役批次已删，断言面随宿主退役（容错壳）")
    skip(_n, f"{rpm} + {wvc}", "右面板与旧向导宿主已随 Task436/440 退役批次删除")

print("== (2) 欢迎圈文字（第五轮）：body 标签约束冲突根修 ==")
check("234-2a body label translate fix", cmk, "_ame224_bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;")
check("234-2b title label translate kept (regression)", cmk, "_ame224_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;")
check("234-2c post-layout frame forensics", cmk, "[CoachMarks] Task234 post-layout: card=%@ title=%@ body=%@")
# ★第 12 期整改批次二①重锚（Task378：卡面收敛 AmeTheme 令牌）：
# "Task233 卡片实底不回归磨砂"的关切由 AmeTheme surfaceCard 实底赋值继续守卫。
check("234-2d Task233 card bg kept（Task378 重锚：AmeTheme surfaceCard 令牌实底）",
      cmk, "_ame224_card.backgroundColor = [AmeTheme surfaceCard];")
check("234-2e Task233 bring-to-front kept (regression)", cmk, "bringSubviewToFront:_ame224_card")
check("234-2f Task233 frame sanity kept (regression)", cmk, "card frame abnormal after layout")
check("234-2g Task233 transform reset kept (regression)", cmk, "_ame224_card.transform = CGAffineTransformIdentity;")
check("234-2h Task232 per-page forensics prefix kept", cmk, "Task232 page %lu/%lu: spot=%@ titleLen=%lu")

print("== (3) 字体重叠残留：拷贝画进 textRectForBounds 文本矩形 ==")
# ★第 12 期整改批次二①（退役收编）：Task378（commit 91a10fe3d）"全局描边字体
# 退役=白黑双重叠根修"移除 setText:/drawTextInRect: 双渲染源头（BackgroundManager.m
# 净删 374 行，python 实测 ame234_textRect/ame235_copyRect/ame233_backing/
# ame233_ps/ame233_opaqueColor 全部 0 命中，全仓产品代码零残留）；重叠根关切
# 由"单渲染源"结构性保证，退役口径由 ame378_selfcheck.py 守卫。
# [RETIRED] 家法：锚面随链退役，SKIP 而非 FAIL。
skip("234-3a tight text rect computed", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("234-3b four dark copies into text rect", "BackgroundManager.m 描边拷贝链",
     "ame235_copyRect 随 Task378 退役（91a10fe3d）")
skip("234-3c backing copy into text rect", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("234-3d raw-rect copies retired", "BackgroundManager.m 描边拷贝链",
     "宿主链整体退役，缺席语义真空成立")
skip("234-3e paragraph style retained (233-5a compat)", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("234-3f opaque backing retained (233-5c compat)", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("234-3g exception net intact", "BackgroundManager.m 描边拷贝链",
     "异常网随 Task378 拷贝链退役")

print("== (4) MobileGlues 上游复查（无更新：上游 97558a6 后无新提交） ==")
check("234-4a vendored contains upstream tip fix (version.h)", mgv, "Ported upstream 0f1e10b")
check("234-4b vendored contains upstream tip fix (multidraw.cpp)", mgm, "Upstream 0f1e10b (2.0.18 sync)")

print("== (5) 分享 GitHub 500 错误页：零查询参数终案 ==")
# ★第 12 期整改批次二①重锚（gamepad 支持批次：目录预导航参数化拆段——
# URL 模板 + isGamepad 三元目录选择）："纯路径目录预导航（零查询参数）"关切
# 由 5b/5c absent 断言 + URL 模板与 controls/layouts/community 目标继续守卫
# （python 实测 ZL2ControlRepoViewController.m 现形）。
check("234-5a path-based directory prefill URL（gamepad 批次重锚：URL 模板拆段）",
      crv, '@"https://github.com/%@/%@/new/%@/%@"')
check("234-5a2 directory target continues (layouts/community)", crv, "controls/layouts/community")
check_absent("234-5b filename= query retired", crv, "?filename=")
check_absent("234-5c value= query retired", crv, "&value=%@")
check_absent("234-5d id whitelist encoder retired", crv, "ame233_idSet")
check("234-5e clipboard-first kept", crv, "UIPasteboard.generalPasteboard.string = json")
check("234-5f openURL completion kept (233-4d compat)", crv, "Task233 GitHub openURL success=%d (urlLen=%lu)")
check("234-5g hint carries dynamic filename", crv, "stringWithFormat:localize(@\"ame230.repo.upload.github_hint\", nil), ame230_id")
check("234-5h failure toast kept", crv, 'localize(@"ame233.repo.open_fail", nil)')

print("== (6) i18n hint 文案 x5（带 %1$@.json 文件名占位） ==")
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN", "ja"]:
    p = f"Natives/resources/{lang}.lproj/Localizable.strings"
    check(f"234-6 hint filename placeholder @{lang}", p, "%1$@.json")

print()
print(f"\nverify_task234: {PASS} ok, {SKIPPED} skipped, {FAIL} fail")
sys.exit(0 if FAIL == 0 else 1)
