#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task330 自检门：四线根修锚点 + 结构完整性断言。
线A=ModService 默认实例版本轴统一；线B=Runtime 首方内容自愈；
线C=SurfaceVC 触点时刻几何自愈；线D=ZL2M3Switch 拇指圆形化 + 列表页复用残留清除。
"""
import re
import sys

ROOT = "/home/z/my-project/repo-prisma2/Natives"
checks = []
failed = []


def check(name, path, pattern, count=1, rx=False):
    checks.append(name)
    try:
        src = open(path, encoding="utf-8").read()
    except OSError as e:
        failed.append(f"{name}: cannot read {path}: {e}")
        return
    hits = len(re.findall(pattern, src)) if rx else src.count(pattern)
    if hits < count:
        failed.append(f"{name}: expect >= {count} hit(s), got {hits} -- pattern={pattern[:70]}")


def balanced(path):
    checks.append(f"bracket-balance: {path.split('/')[-1]}")
    src = open(path, encoding="utf-8").read()
    for op, cl in [("{", "}"), ("(", ")")]:
        if src.count(op) != src.count(cl):
            failed.append(
                f"bracket-balance: {path.split('/')[-1]} {op}{cl} {src.count(op)} vs {src.count(cl)}"
            )


# ---- 线A：ModService 默认实例版本轴统一 ----
A = f"{ROOT}/ModService.m"
check("A1 pass defined", A, "+ (void)ame330_unifyDefaultInstanceIntoVersionAxis {")
check("A2 call wired into ame329 tail", A, "[ModService ame330_unifyDefaultInstanceIntoVersionAxis];")
check("A3 plist exempted (ame329 set)", A, '@".ame269_backup", @"custom_gamedir",\n        @"launcher_preferences.plist"')
check("A4 plist exempted (ame330 set)", A, '@"import_report.json", @".ame269_backup", @"custom_gamedir",\n        @"launcher_preferences.plist"')
check("A5 two-layer guard", A, 'rangeOfString:@"/"].location != NSNotFound) return;')
check("A6 ambiguity guard", A, "default-instance unify skipped")
check("A7 marker guard", A, "无主实例绝不盲搬")
check("A8 moveEntry reuse", A, "ame329_moveEntry(ame330_fm,")
check("A9 anchor log", A, "[Ame330] default instance data unified into version axis")

# ---- 线B：Runtime 首方内容自愈 ----
B = f"{ROOT}/AmePluginRuntime.m"
check("B1 refresh defined", B, "+ (void)ame330_refreshFirstPartyContent {")
check("B2 boot hook", B, "[self ame330_refreshFirstPartyContent];")
check("B3 atomic write", B, "NSDataWritingAtomic")
check("B4 builtin-only scope", B, "仅首方内置件")
check("B5 C-face root (compile-mine guard)", B, "ame317_pluginsRootDir()")
check("B6 anchor log", B, "Task330 first-party content refresh")
check("B7 before load loop", B, "ame330_refreshFirstPartyContent];\n\n    for (NSString *pid in [AmePluginManager installedPluginIds]) {")

# ---- 线C：SurfaceVC 触点时刻几何自愈 ----
C = f"{ROOT}/SurfaceViewController.m"
check("C1 reconcile defined", C, "- (void)ame330_touchTimeReconcile {")
# ★ Task331 演进注记：v2 的"freeform 未武装即弹回"首守卫升级为"触点时刻即时武装"
#   分支（洞A：防抖窗口内首触点按全屏因子映射=开小窗偏移头号存活面），断言随之重锚。
check("C2 freeform engage branch (Task331 v3)", C, "if (!g_ame267_freeformScaled) {")
# ★ Task331 演进注记：v2 的沉降定时器硬守卫（拖拽期/沉降期触点被冻结在陈旧
#   因子上=洞B）由帧指纹权威闸取代，断言随之重锚。
check("C3 frame-fingerprint authority gate (Task331 v3)", C,
      "CGRectEqualToRect(self.touchView.frame, ame331_lastFactorFrame)")
check("C4 foreground guard", C, "if (!g_ame250_appActive) return;")
check("C5 sendTouchPoint hook", C, "ame330_touchTimeReconcile];\n    // Task 78")
check("C6 didBecomeActive hook", C, "ame330_touchTimeReconcile];\n    }\n    [self updateSavedResolution];")
# ★ Task331 演进注记：核心复用断言跟随 v3 局部变量重锚（ame330_res → ame331_res）。
check("C7 core reuse (Task328)", C, "[self ame328_recomputeBeliefChainFromTouchViewWithRes:ame331_res]")
check("C8 anchor log", C, "touch-time belief reconcile healed stale freeform factors")

# ---- 线D：M3 开关圆形拇指 + 列表页复用残留 ----
D = f"{ROOT}/ZL2M3Kit.m"
check("D1 thumb circle", D, "self.thumbView.layer.cornerRadius = thumb / 2.0;")
L = f"{ROOT}/ZL2PluginListViewController.m"
check("D2 reuse-residue clear", L, "cell.detailTextLabel.text = nil;")
check("D3 about-section rationale", L, '装机截图实锤"关于"区复读')

# ---- 结构完整性 ----
for p in [A, B, C, D, L]:
    balanced(p)

print(f"task330 selfcheck: {len(checks)} assertion(s)")
for c in checks:
    print(f"  ok  {c}")
if failed:
    print("FAILED:")
    for f in failed:
        print(f"  xx  {f}")
    sys.exit(1)
print("all green")
