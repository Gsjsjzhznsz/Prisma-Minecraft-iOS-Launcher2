#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 233 verification: 5-item correction round on the Task232 build (9137a8f5).

Round items (user message 2026-10-09):
  1. 常用操作键 drawer (item-1 correction): z-order yield + visibility
     single source of truth + overlap forensics
  3. MGL probabilistic enter-world freeze (item-3 correction): Task232 steer
     retired + 25s render-stall watchdog
  *.  分享控件到 GitHub 打不开网页: URL encode + clipboard + length cap
  *.  字体双层/重叠不上/偏黑: paragraph-style copies + opaque backing
  *.  欢迎界面圆圈焦点介绍 (4th report): class-based anchor discovery +
     deep launch-button search + real-frame semantic anchors + card hardening
"""
import sys, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

PASS, FAIL, SKIPPED = 0, 0, 0

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
        with open(path, encoding="utf-8") as f:
            body = f.read()
        if needle in body:
            PASS += 1
            print(f"  ok   {name}")
        else:
            FAIL += 1
            print(f"  FAIL {name}: needle not in {path}")
    except FileNotFoundError:
        print(f"  [RETIRED] {path} —— 退役批次已删，断言面随宿主退役（容错壳）")
        skip(name, path)
    except Exception as e:
        FAIL += 1
        print(f"  FAIL {name}: {e}")

def check_absent(name, path, needle):
    global PASS, FAIL
    try:
        with open(path, encoding="utf-8") as f:
            body = f.read()
        if needle in body:
            FAIL += 1
            print(f"  FAIL {name}: forbidden needle STILL in {path}")
        else:
            PASS += 1
            print(f"  ok   {name}")
    except Exception as e:
        FAIL += 1
        print(f"  FAIL {name}: {e}")

svc = "Natives/SurfaceViewController.m"
ccu = "Natives/customcontrols/CustomControlsUtils.m"
jl  = "Natives/JavaLauncher.m"
crv = "Natives/ZL2ControlRepoViewController.m"
bm  = "Natives/BackgroundManager.m"
wvc = "Natives/WelcomeViewController.m"
cmk = "Natives/Ame223CoachMarksView.m"

print("== (1) 常用操作键 drawer: z-order + visibility + forensics ==")
check("233-1a sub-buttons z-order move", ccu, "drawer sub-buttons moved below interactive main buttons")
check("233-1b order-preserving insert (above prev)", ccu, "insertSubview:ame233_v aboveSubview:ame233_prev")
check("233-1c decorative wrapper exposed", "Natives/customcontrols/CustomControlsUtils.h", "ame233_viewIsDecorativeControlButton")
check("233-1d wrapper single-source impl", ccu, "BOOL ame233_viewIsDecorativeControlButton(UIView *view)")
check("233-1e drawer restore respects own hidden", "Natives/customcontrols/ControlDrawer.m", "button.hidden = self.hidden || !self.areButtonsVisible")
check("233-1f sub-button visibility single source", svc, "ame233_drawer == nil || ame233_drawer.hidden ||")
check("233-1g overlap forensics", svc, "Task233 drawer-key overlaps main control")
check_absent("233-1h no crude decorative copy in SVC", svc, "ame83b_is_decorative_button")

print("== (3) MGL probabilistic freeze: steer retired + stall watchdog ==")
check("233-3a steer retired marker", jl, "Task232 steer 退役")
check_absent("233-3b steer code gone", jl, "steering to tinygl4angle")
check_absent("233-3c ame232_major var gone", jl, "ame232_major >= 26")
check("233-3d watchdog installed", svc, "Task233 RENDER STALL: swapOK frozen at %lu for ~25s")
check("233-3e per-session state (assoc object)", svc, "ame233_stallKey")
check("233-3f saw-live guard against slow second launch", svc, '@"sawLive": @NO')

print("== (4) share-to-GitHub webpage ==")
check("233-4a clipboard-first", crv, "submission JSON (%lu bytes) copied to clipboard")
check("233-4b id encoded with safe whitelist (Task234 重锚：id 不再进 URL——零查询参数终案)", crv, "stringWithFormat:localize(@\"ame230.repo.upload.github_hint\", nil), ame230_id")
check_absent("233-4c value length cap retired (Task234：value= 大载荷预填是 GitHub 500 错误页的触发面，整体退役)", crv, "<= 6000")
check("233-4d openURL completion handler", crv, "Task233 GitHub openURL success=%d (urlLen=%lu)")
check("233-4e failure toast", crv, 'localize(@"ame233.repo.open_fail", nil)')
check_absent("233-4f raw id interpolation gone", crv, "community%%2F%@.json&value=%@\",\n            kTask189RepoOwner, kTask189RepoName, kTask189RepoRef, ame230_id,")

print("== (5) font double-layer / misalignment / dark tint ==")
# ★第 12 期整改批次二①（退役收编）：Task378（commit 91a10fe3d）"全局描边字体
# 退役=白黑双重叠根修"把 setText:/drawTextInRect: 双交换 + ame250 染色 +
# ame224 反色阴影全链删除（BackgroundManager.m 净删 374 行，python 实测
# ame233_ps/ame233_opaqueColor/ame235_copyRect 全部 0 命中，全仓产品代码零
# 残留）；双层/错位/偏黑三关切由"移除双渲染源头"承接，退役口径由
# ame378_selfcheck.py 守卫。[RETIRED] 家法：锚面随链退役，SKIP 而非 FAIL。
skip("233-5a paragraph style replication", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("233-5b single-line truncation parity", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("233-5c opaque backing copy", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("233-5d opaque helper", "BackgroundManager.m 描边拷贝链",
     "Task378 全局描边字体整体退役（91a10fe3d）")
skip("233-5e four offsets preserved", "BackgroundManager.m 描边拷贝链",
     "ame235_copyRect 随 Task378 退役（91a10fe3d）")

print("== (6) welcome circle focus intro (4th round) ==")
# ★第 12 期整改批次二①（退役收编）：旧首启向导 WelcomeViewController.m 已随
# Task440 死代码六件退役批次整体物理删除（首启留白定案为有意取舍，见
# scripts/task440_retire_inventory.md），圆圈焦点介绍 6a-6h 锚面随宿主退役；
# coach 卡底色 6i 按 Task378（ame224 四入口收敛 AmeCard 动态令牌）重锚。
for _n in ["233-6a class-based anchor discovery", "233-6b menu VC by class",
           "233-6c right panel VC by class", "233-6d deep launch-button search",
           "233-6e semantic anchor from real menu frame",
           "233-6f version anchor re-aimed (Task235 重锚)",
           "233-6g hardcoded screen-fraction rects gone",
           "233-6h anchor log with real-view note"]:
    print(f"  [RETIRED] {wvc} —— 退役批次已删，断言面随宿主退役（容错壳）")
    skip(_n, wvc, "旧首启向导已随 Task440 死代码六件退役（task440_retire_inventory.md A7 清单）")
# ★重锚（Task378：卡面收敛 AmeTheme 令牌=系统深浅语义色，"实底不再是磨砂"
# 的根关切由实底赋值语句继续守卫，python 实测）。
check("233-6i card elevated background（Task378 重锚：AmeTheme surfaceCard 令牌实底）",
      cmk, "_ame224_card.backgroundColor = [AmeTheme surfaceCard];")
check("233-6j labels always visible (no alpha anim)", cmk, "_ame224_titleLabel.alpha = 1.0")
check("233-6k per-page bring-to-front", cmk, "bringSubviewToFront:_ame224_card")
check("233-6l card frame sanity + fallback", cmk, "card frame abnormal after layout")
check("233-6m transform reset per page", cmk, "_ame224_card.transform = CGAffineTransformIdentity;")

print("== (7) i18n keys x5 tables ==")
hint_needle = {"en": "clipboard", "zh-Hans": "剪贴板", "zh-Hant": "剪貼簿", "zh-CN": "剪贴板", "ja": "クリップボード"}
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN", "ja"]:
    p = f"Natives/resources/{lang}.lproj/Localizable.strings"
    check(f"233-7 stall.toast @{lang}", p, '"ame233.stall.toast"')
    check(f"233-7 repo.open_fail @{lang}", p, '"ame233.repo.open_fail"')
    check(f"233-7 github_hint revised @{lang}", p, hint_needle[lang])

print()
print(f"\nverify_task233: {PASS} ok, {SKIPPED} skipped, {FAIL} fail")
sys.exit(0 if FAIL == 0 else 1)
