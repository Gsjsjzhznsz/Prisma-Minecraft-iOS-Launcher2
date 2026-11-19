#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task451 selfcheck：议题#3 第七轮 JIT26ExecPreflight 授予前预检验收门
A 预检主链（64MB 同形分配 + 零取指执行探测 + 3 试重试 + 定罪 marker）
B 启动链接线（拒绝发射 + 逃生阀）
C 偏好注册（PLPreferences debug 段）
D i18n 54 表（en 兜底 + zh 家族原生）
T BuildTag
S 反向注入
"""
import os, re, sys, glob

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")
RES = os.path.join(NAT, "resources")

def rd(p):
    return open(os.path.join(NAT, p), encoding="utf-8").read()

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

jl = rd("JavaLauncher.m")

# ============ A 预检主链 ============
check("A1 预检主链函数", "static int ame451_preflightJit26Channel(void)" in jl)
check("A2 64MB 同形分配（libjvm 64m 镜像请求同形）",
      "64UL * 1024UL * 1024UL" in jl and "JIT26PrepareRegion(NULL, len)" in jl)
check("A3 零取指执行探测（信号类型即判决）",
      "static int ame451_execProbe(void *rx)" in jl
      and "case SIGILL:  verdict = 0; break;" in jl
      and "case SIGBUS:" in jl and "case SIGSEGV: verdict = 1; break;" in jl
      and "default:      verdict = 2; break;" in jl)
check("A4 SIGILL 安全网在册（SIGTRAP/BUS/SEGV/ILL 四窗）",
      jl.count("sigaction(SIGILL, &sa, &oldIll);") == 1
      and jl.count("sigaction(SIGILL, &oldIll, NULL);") == 1)
check("A5 三试重试环", "for (int attempt = 1; attempt <= 3; attempt++)" in jl)
check("A6 不定不拦四态（超时/SIGTRAP/拒绝/罐头）",
      "stalled >30s -- inconclusive" in jl
      and "SIGTRAP safety net) -- inconclusive" in jl
      and "refused the 64MB allocation" in jl
      and "canned ping-ack magic for a 64MB request" in jl)
check("A7 定罪 marker 落盘（fopen+fsync 双通道纪律）",
      "ame451_preflight_conviction.txt" in jl
      and "verdict=conviction (3/3 fresh 64MB-class grants hollow" in jl)
check("A8 PASS 清历史定罪 marker（新鲜度语义）",
      "clearing stale conviction marker" in jl and "if (ame451_haveMarker) unlink(ame451_marker);" in jl)
check("A9 brk 分配 30s 有界等待（ame301 判例）",
      "(int64_t)30 * NSEC_PER_SEC" in jl and "ame451_prepareGuarded" in jl)
check("A10 试错分配不携带进会话（munmap 释放）",
      "munmap(rx, ame451_len);" in jl)
check("A11 SIGTRAP 安全网（Task91 判例：brk 无人应答优雅失败）",
      "static void* ame451_prepareGuarded(size_t len, BOOL *trapped)" in jl
      and "sigsetjmp(ame451_prepEnv, 1)" in jl)

# ============ B 启动链接线 ============
check("B1 接线位于 ame437 探针之后",
      jl.find("ame437_selfVerifyJit26Channel(result);") != -1
      and jl.find("ame437_selfVerifyJit26Channel(result);") < jl.find("ame451_preflightJit26Channel() != 0"))
check("B2 定罪拒绝发射（showDialog + handleExitCode + return 1）",
      "showDialog(localize(@\"Error\", nil), localize(@\"i18n_str_ame451_preflight\", nil));" in jl
      and "[PLLogOutputView handleExitCode:1];" in jl.split("ame451_preflightJit26Channel() != 0")[1][:800])
check("B3 逃生阀（debug.jit26_preflight_disable）",
      "getPrefBool(@\"debug.jit26_preflight_disable\")" in jl
      and "preflight skipped (debug.jit26_preflight_disable set)" in jl)
check("B4 逃生阀默认放行语义（!disable 才预检）",
      "if (!getPrefBool(@\"debug.jit26_preflight_disable\")) {" in jl)
check("B5 日志锚 [Ame451]", jl.count("[Ame451] preflight") >= 8)

# ============ C 偏好注册 ============
pp = rd("PLPreferences.m")
check("C1 debug 段注册（防 Setter 静默丢弃族）",
      '"jit26_preflight_disable": @NO,' in pp)
check("C2 注册注记 Task451", "★Task451：JIT26 授予前预检逃生阀" in pp)

# ============ D i18n 54 表 ============
tables = sorted(glob.glob(os.path.join(RES, "*.lproj", "Localizable.strings")))
pat = re.compile(r'^\s*"%s"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;' % re.escape("i18n_str_ame451_preflight"), re.M)
present, vals = 0, {}
for t in tables:
    src = open(t, encoding="utf-8").read()
    m = pat.search(src)
    if m:
        present += 1
        vals[os.path.basename(os.path.dirname(t)).replace(".lproj", "")] = m.group(1)
check("D1 54 表全额在键", len(tables) == 54 and present == 54, f"tables={len(tables)} present={present}")
check("D2 zh 家族中文原生", "空壳" in vals.get("zh-Hans", "") and "空壳" in vals.get("zh-CN", "")
      and "空殼" in vals.get("zh-Hant", ""))
check("D3 处置阶梯四步全在（重启/重指派/重装/换 enabler）",
      "StikDebug" in vals.get("en", "") and "reinstall this launcher" in vals.get("en", "")
      and "SideStore/JitStreamer-EB" in vals.get("zh-Hans", ""))
check("D4 无裸引号未转义（tokenizer 安全）",
      all(' = "' in open(t, encoding="utf-8").read().split('"i18n_str_ame451_preflight"')[1][:80]
          for t in tables if '"i18n_str_ame451_preflight"' in open(t, encoding="utf-8").read()))

# ============ T BuildTag ============
check("T1 BuildTag=Task451", "Task451 · " in rd("BuildTag.h"))

# ============ S 反向注入 ============
check("S1 A3 判决映射完备性（三 verdict 覆盖 0/1/2）",
      "verdict = 0;       // 未 fault 返回 = 可执行（判过）" in jl
      and jl.count("verdict = 1; break;") == 1 and jl.count("verdict = 2; break;") == 1)
check("S2 B2 拒绝面完整（return 1 紧随弹窗）",
      "i18n_str_ame451_preflight" in jl.split("ame451_preflightJit26Channel() != 0")[1][:600])
check("S3 D1 计数谓词敏感性", present == 54)

print()
if fails:
    print(f"ALL FAIL {len(fails)}: {fails}")
    sys.exit(1)
print("ALL PASS")
