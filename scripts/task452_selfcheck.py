#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task452 自检门：「打开即闪退」判读轮四件交付断言。

判读链（装机 eac50ad latestlog 实锤）：
  日志止于 [Ame417] shell rail glyphs 且无异常块（stderr 无缓冲 _IONBF +
  管道读取线程毫秒级排水，Task441 判例 N+28 取证口径）= 硬信号级死亡；
  死亡窗口 [背景宿主安装 → buildViews → autoCheck] 三段静默带内；
  窗口内唯一新执行面 = Task449/450 壁纸清扫（wallpaper=1 专属）；
  设备处于议题#3 已定罪 JIT26 空壳 RX 通道，启动器自身 JSC（插件引擎）
  与 JVM 同享可执行映射通道而 Task451 预检只护游戏发射 = 结构性裸露。

四件交付（全部可静态断言）：
  A1  main.m JSC 解释器钉死（JSC_useJIT 环境族 + 逃生阀门控 + 签名日志）
  A2  PLPreferences 注册 debug.plugin_jit_allow
  A3  首帧链分段签名（壳 2 段 + 主页 4 段 = 6 处 [Task452] open 锚）
  A4  新执行面 @try 收敛（主页 buildViews / 背景宿主重建 / 清扫管线 双挂点）
  A5  BuildTag Task452 重锚
"""
import io
import re
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def rd(rel):
    p = os.path.join(REPO, rel)
    with io.open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

fails = []
def check(name, ok):
    print(("PASS  " if ok else "FAIL  ") + name)
    if not ok:
        fails.append(name)

main_m = rd("Natives/main.m")
pref_m = rd("Natives/PLPreferences.m")
shell_m = rd("Natives/ZL2ShellViewController.m")
home_m = rd("Natives/ZL2HomeViewController.m")
host_m = rd("Natives/ZL2BackgroundHost.m")
bg_m = rd("Natives/BackgroundManager.m")
tag_h = rd("Natives/BuildTag.h")

# ---- A1 main.m JSC 解释器钉死 ----
check("A1-1 main.m JSC_useJIT setenv", 'setenv("JSC_useJIT", "0", 1)' in main_m)
check("A1-2 main.m JSC 环境族 4 键", all(k in main_m for k in (
    'setenv("JSC_useJIT", "0", 1)',
    'setenv("JSC_useBaselineJIT", "0", 1)',
    'setenv("JSC_useDFGJIT", "0", 1)',
    'setenv("JSC_useFTLJIT", "0", 1)')))
check("A1-3 逃生阀门控 debug.plugin_jit_allow", 'getPrefBool(@"debug.plugin_jit_allow")' in main_m)
check("A1-4 钉死分支签名日志", "JSC interpreter pinned" in main_m)

# ---- A2 PLPreferences 注册 ----
check("A2 plugin_jit_allow 注册", '@"plugin_jit_allow": @NO,' in pref_m)

# ---- A3 首帧链分段签名（6 段）----
anchors = [
    (shell_m, "[Task452] open: shell background-host installed"),
    (shell_m, "[Task452] open: shell viewDidLoad done"),
    (home_m, "[Task452] open: home buildViews done (ok="),
    (home_m, "[Task452] open: home launch-state done"),
    (home_m, "[Task452] open: home first layout begin"),
    (shell_m, "[Task452] open: home did appear (first frame landed)"),
]
check("A3-1 壳背景宿主签名", anchors[0][1] in anchors[0][0])
check("A3-2 壳 viewDidLoad 收尾签名", anchors[1][1] in anchors[1][0])
check("A3-3 主页 buildViews 完成签名", anchors[2][1] in anchors[2][0])
check("A3-4 主页 launch-state 签名", anchors[3][1] in anchors[3][0])
check("A3-5 主页首布局签名", anchors[4][1] in anchors[4][0])
check("A3-6 首帧完成签名", anchors[5][1] in anchors[5][0])

# ---- A4 新执行面 @try 收敛 ----
check("A4-1 主页 buildViews @try",
      "@try {" in home_m and 'NSException *ame452_ex' in home_m
      and "home buildViews EXCEPTION signature" in home_m)
check("A4-2 buildViews 失败下游门控",
      "if (ame452_buildOK) {" in home_m
      and "home downstream skipped" in home_m)
check("A4-3 背景宿主重建 @try",
      "@try {" in host_m and "background-host rebuild EXCEPTION signature" in host_m)
# ★Task461 判例重锚：A4-4/A4-5 清扫挂点断言随 Task449/450 壁纸清扫管线整链退役
#   而退役（Task461 回退树 = 448 基线，ame449_sweep 全仓归零由 task461_selfcheck
#   X2-1/X2-2 执法）；A4 家族收敛为 A4-1~A4-3 三件（主页/门控/背景宿主）。
check("A4-4 清扫挂点随 449 退役判例（BackgroundManager 无 ame449_sweep 残留）",
      "ame449_sweep" not in bg_m)

# ---- A5 BuildTag 重锚 ----
check("A5 BuildTag Task468 · 2026-11-23（启动链恢复首预发行版轮代际重锚）", 'Task468 · 2026-11-23' in tag_h)

print()
if fails:
    print("task452_selfcheck: %d FAIL" % len(fails))
    sys.exit(1)
print("task452_selfcheck: ALL PASS")
