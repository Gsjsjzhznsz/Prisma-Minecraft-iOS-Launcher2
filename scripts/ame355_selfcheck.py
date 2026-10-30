#!/usr/bin/env python3
# ame355_selfcheck.py -- Task355 门禁（一代仓库开放议题 #16/#17/#19/#20/#21 五线移植修复）
# A 一代议题 #19 内存线（VA 预检向下探测取最大可行档 + Task173 钳制口径换
#   jetsam 上限=available+phys_footprint，防瞬时可用缩水漂移钳）
# B 一代议题 #20 JIT 门禁线（单飞护栏 gPL355GateInFlight + 超时弹窗取消补
#   onAbandon，双等待环/双 handler 病历根治）
# C 一代议题 #21 锁存线（修饰键轻点锁存尊重按钮显式 isToggle=false，缺省
#   保持 Task179 语义零回归）
# D 一代议题 #16 指针线（GCMouse 在场即锁定系统指针）
# E 一代议题 #17 渲染器线（prefer_vulkan 仅 MoltenVK 渲染器放行，非法组合
#   钳回 default）
# S 反向探针（关键标记摘除/退化变体必须可检出，零仓内触碰）
# 断言纪律：含字符串字面量的断言用原文（raw）；strip 后文本仅用于纯结构检查。
import os, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

def strip_code(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

utils = read("Natives/utils.m")
utils_code = strip_code(utils)
jl = read("Natives/JavaLauncher.m")
jl_code = strip_code(jl)
gate = read("Natives/PLJITGate.m")
gate_code = strip_code(gate)
svc = read("Natives/SurfaceViewController.m")
svc_code = strip_code(svc)

# ══ A 一代议题 #19 内存线 ════════════════════════════════════
check('A1 Task173 钳制口径换进程上限（task_info TASK_VM_INFO + phys_footprint + limit=avail+foot）',
      "task_info(mach_task_self(), TASK_VM_INFO," in utils
      and "phys_footprint >> 20" in utils
      and "[Task355] safe heap ceiling: jetsam limit=" in utils
      and "ame355_limitMB = availMB + (int)ame355_footMB;" in utils_code)

check('A2 task_info 失败回退旧瞬时口径（legacy transient reading 留痕，天花板函数不裸奔）',
      "task_info unavailable, legacy transient reading" in utils
      and "ceilingMB = availMB - 1200;" in utils_code)

check('A3 VA 预检向下探测（512MB 步进 + 1024MB 下限 + 最大可行档续启）',
      "while (ame355_try >= 1024) {" in jl_code
      and "ame355_try -= 512;" in jl_code
      and "if (validateVirtualMemorySpace(ame355_try)) { ame355_ok = ame355_try; break; }" in jl_code
      and "[JavaLauncher] Task355: VA probe %dMB failed -- proceeding with largest reservable heap %dMB (issue #19)" in jl)

check('A4 结构性不可启动仍如实拒启（1024MB 以下不可预留 = 原对话框 + return 1 保留）',
      "Insufficient contiguous virtual memory space. Lower memory allocation and try again." in jl
      and "Insufficient contiguous virtual memory space. Increased Memory Limit entitlement is missing, please add it via GetMoreRam app." in jl
      and jl_code.count("return 1;") >= 1
      and "Task173 钳制先行" in jl)

check('A5 钳制 toast 复用既有键零新增 i18n（ame189.utils.mem_clamped + ame141 钳制链原样在场）',
      "ame189.utils.mem_clamped" in jl
      and "ame173_safeHeapCeilingMB();" in utils_code
      and "launch memory %dMB exceeds safe ceiling %dMB -- clamping" in utils)

# ══ B 一代议题 #20 JIT 门禁线 ════════════════════════════════
check('B1 单飞护栏静态位 + 重复进入抑制（onAbandon 恢复启动器交互态，不产生第二套等待）',
      "static BOOL gPL355GateInFlight = NO;" in gate
      and "Task355: duplicate gate entry while a JIT wait is already in flight" in gate
      and "if (onAbandon) onAbandon();" in gate_code)

check('B2 置位/清位计数严格（YES×2=主等待环+重挂链；NO×3=static声明+两完成块入口先清位再分支）',
      gate.count("gPL355GateInFlight = YES;") == 2
      and gate.count("gPL355GateInFlight = NO;") == 3
      and "static BOOL gPL355GateInFlight = NO;" in gate
      and gate.count("gPL355GateInFlight = NO;   // ★ Task355：先清位再分支（重试再进入合法）") == 2)

check('B3 置位点在等待环入口（Task267 可取消弹窗之前；快速路径不置位不挡道）',
      gate.index("gPL355GateInFlight = YES;") < gate.index("Task267：等待期可取消弹窗")
      and "从这里起进入等待环" in gate)

check('B4 重挂链占位 + 超时弹窗取消补 onAbandon（旧 handler:nil 悬挂病历收口）',
      "重挂链同样占单飞位" in gate
      and "Task355: JIT timeout alert cancelled -- abandoning launch" in gate
      and gate.index("Task355: JIT timeout alert cancelled")
          < gate.rindex("[self invokeAfterJITEnabledWithHandler:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];"))

# ══ C 一代议题 #21 锁存线 ════════════════════════════════════
check('C1 修饰键锁存尊重按钮显式 isToggle（nil→缺省锁存；显式 false→常规按住直通）',
      'id ame355_toggleProp = sender.properties[@"isToggle"];' in svc
      and "(ame355_toggleProp == nil) ? YES : [ame355_toggleProp boolValue];" in svc_code
      and "if (ame355_latchEnabled && AME176_IS_MOD_KEY(keycode)) {" in svc_code)

check('C2 出厂布局零回归口径可 grep（缺省维持 Task179 锁存语义注释在场）',
      '键缺省（出厂"保持 SHIFT/' in svc
      and "锁存语义，存量潜行玩法零回归" in svc)

# ══ D 一代议题 #16 指针线 ════════════════════════════════════
check('D1 prefersPointerLocked 硬件鼠标在场即锁定（旧 isGrabbing||virtualMouseEnabled 条件退役）',
      "return GCMouse.mice.count > 0;" in svc_code
      and "GCMouse.mice.count > 0 && (isGrabbing || virtualMouseEnabled)" not in svc_code
      and "Task355（一代议题 #16 根修）" in svc)

check('D2 连接/断开重评估钩子原样在场（setNeedsUpdateOfPrefersPointerLocked 双通知处）',
      svc.count("setNeedsUpdateOfPrefersPointerLocked") >= 3)

# ══ E 一代议题 #17 渲染器线 ══════════════════════════════════
check('E1 prefer_vulkan 仅 MoltenVK 放行（非法组合钳回 default，profile 值不改写）',
      '[graphicsApi isEqualToString:@"prefer_vulkan"]' in jl
      and "![renderer isEqualToString:@ RENDERER_NAME_VULKAN]" in jl_code
      and 'graphicsApi = @"default";' in jl
      and "dual Vulkan-on-Metal ownership = error -1" in jl)

check('E2 钳制 toast 双语明示 + 日志留痕（NMToast 已引入，主线程派发）',
      "Vulkan API 仅支持 MoltenVK 渲染器" in jl
      and "[JavaLauncher] Task355: graphicsApi=prefer_vulkan is only valid with the" in jl
      and "#import \"NMToast.h\"" in jl)

# ══ S 反向探针（关键标记摘除/退化必须可检出，零仓内触碰） ════
# S-A 内存线护栏退化必须翻红
check('S-A1 VA 探测链摘除（硬拒启复辟）→ 变体可检出',
      "while (ame355_try >= 1024) {" in jl_code
      and "while (ame355_try >= 1024) {" not in jl_code.replace("while (ame355_try >= 1024) {", "while (NO) {"))
check('S-A2 上限口径退化（回瞬时 available 单项）→ 变体可检出',
      "ame355_limitMB = availMB + (int)ame355_footMB;" in utils_code
      and "ame355_limitMB = availMB + (int)ame355_footMB;"
          not in utils_code.replace("ame355_limitMB = availMB + (int)ame355_footMB;",
                                    "ame355_limitMB = availMB;"))
# S-B 单飞护栏退化必须翻红
check('S-B1 入口护栏禁用变体可检出',
      "if (gPL355GateInFlight) {" in gate_code
      and "if (gPL355GateInFlight) {"
          not in gate_code.replace("if (gPL355GateInFlight) {", "if (NO && gPL355GateInFlight) {"))
check('S-B2 超时取消补 onAbandon 摘除 → 变体可检出',
      "Task355: JIT timeout alert cancelled -- abandoning launch" in gate
      and "Task355: JIT timeout alert cancelled -- abandoning launch"
          not in gate.replace("Task355: JIT timeout alert cancelled -- abandoning launch", "Task355_DISABLED"))
# S-C 锁存门/指针门/渲染器闸摘除必须翻红
check('S-C1 锁存门摘除（退回无条件锁存）→ 变体可检出',
      "if (ame355_latchEnabled && AME176_IS_MOD_KEY(keycode)) {" in svc_code
      and "if (ame355_latchEnabled && AME176_IS_MOD_KEY(keycode)) {"
          not in svc_code.replace("if (ame355_latchEnabled && AME176_IS_MOD_KEY(keycode)) {",
                                  "if (AME176_IS_MOD_KEY(keycode)) {"))
check('S-C2 指针门退化（抓取态条件复辟）→ 变体可检出',
      "return GCMouse.mice.count > 0;" in svc_code
      and "return GCMouse.mice.count > 0;"
          not in svc_code.replace("return GCMouse.mice.count > 0;",
                                  "return GCMouse.mice.count > 0 && (isGrabbing || virtualMouseEnabled);"))
check('S-C3 渲染器闸摘除（prefer_vulkan 全放行）→ 变体可检出',
      "![renderer isEqualToString:@ RENDERER_NAME_VULKAN]" in jl_code
      and "![renderer isEqualToString:@ RENDERER_NAME_VULKAN]"
          not in jl_code.replace("![renderer isEqualToString:@ RENDERER_NAME_VULKAN]", "NO"))

print()
if fails:
    print(f"ame355_selfcheck: {len(fails)} FAIL / {passed} PASS")
    for f in fails:
        print(f"  - {f}")
    sys.exit(1)
print(f"ame355_selfcheck: ALL GREEN ({passed} assertions)")
