#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task457 自检门（游戏启动 JIT26 op4 brk 无应答闪退根因修复轮）：
  装机 .ips（bca7c538 = Task456 构建）符号化实锤：
    launchMinecraft block → launchJVM → init_bypassDyldLibValidation →
    searchAndPatch("dyld_mmap") → redirectFunctionMirrored →
    JIT26PrepareRegionForPatching+4 brk #0xf00d（EXC_BREAKPOINT brk 61453，
    后台 default-QOS 队列）＝调试器未应答 op4 超调用，裸函数 SIGTRAP 致死。
  修复面：
    A. utils.m/.h：op1/op4 brk 超调用 Safe 护栏（Task91 信号网 + Task301
       20s 有界看门狗合体）
    B. dyld_bypass_validation.m：redirectFunctionMirrored 三重防线（Safe op4
       + vm_protect 返回值检查 + memcmp 写回校验）+ hooked_mmap op1 Safe 化
       （失败 → 干净 MAP_FAILED）+ init 返回 BOOL + op4 通道金丝雀
    C. JavaLauncher.m 两调用点对 FALSE 弹 ame457 诊断窗优雅退出 + i18n 全
       54 语种入册 + BuildTag Task457
R = 修复形态执法 / X = 全仓扫描（家族零容忍）/ S = 敏感性自证（放行样本）
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []


def check(name, ok, detail=""):
    print(("  [PASS] " if ok else "  [FAIL] ") + name + (("  -- " + detail) if (detail and not ok) else ""))
    if not ok:
        FAILS.append(name)


utils_m = (ROOT / "Natives" / "utils.m").read_text(encoding="utf-8", errors="replace")
utils_h = (ROOT / "Natives" / "utils.h").read_text(encoding="utf-8", errors="replace")
dyld = (ROOT / "Natives" / "dyld_bypass_validation.m").read_text(encoding="utf-8", errors="replace")
jl = (ROOT / "Natives" / "JavaLauncher.m").read_text(encoding="utf-8", errors="replace")
buildtag = (ROOT / "Natives" / "BuildTag.h").read_text(encoding="utf-8", errors="replace")

print("== R 修复形态执法（A：Safe 护栏） ==")

# R1a Safe 护栏双变体在位 + 信号网结构（Task91 判例同款：sigsetjmp + armed 标志）
check("R1a JIT26PrepareRegionSafe / JIT26PrepareRegionForPatchingSafe 落位",
      "BOOL JIT26PrepareRegionSafe(void *addr, size_t len)" in utils_m
      and "BOOL JIT26PrepareRegionForPatchingSafe(void *addr, size_t size)" in utils_m)
check("R1b 信号网结构（sigsetjmp + ame457_trapArmed + siglongjmp）",
      "sigsetjmp(ame457_trapEnv, 1)" in utils_m
      and "siglongjmp(ame457_trapEnv, 1)" in utils_m
      and "static volatile sig_atomic_t ame457_trapArmed" in utils_m)
check("R1c Task301 有界看门狗（20s 信号量 + 超时留痕 + 泄漏优于冻结）",
      "(int64_t)20 * NSEC_PER_SEC" in utils_m
      and "brk hypercall watchdog timeout (20s)" in utils_m
      and "leaking the blocked thread" in utils_m)
check("R1d 非(net) SIGTRAP 不吞（恢复默认语义原样致死，Task91 同款）",
      "不属于本安全网的 SIGTRAP" in utils_m and "signal(sig, SIG_DFL);" in utils_m)
check("R1e utils.h Safe 声明面（双变体 + 病历注释）",
      "BOOL JIT26PrepareRegionSafe(void *addr, size_t len);" in utils_h
      and "BOOL JIT26PrepareRegionForPatchingSafe(void *addr, size_t len);" in utils_h
      and "brk 61453" in utils_h)

print("== R 修复形态执法（B：dyld_bypass 三重防线） ==")

# R2 redirectFunctionMirrored：Safe op4 + vm_protect 检查 + 写回校验
check("R2a op4 改走 Safe（无应答 → 弃钩留痕，不裸 brk）",
      "if (!JIT26PrepareRegionForPatchingSafe(patchAddr, sizeof(patch)))" in dyld
      and "hook %s aborted before vm_remap" in dyld)
check("R2b vm_protect(mirror RW) 返回值执法（TXM 拒改保护 → 不 memcpy）",
      "kern_return_t ame457_prot = vm_protect(" in dyld
      and "if (ame457_prot != KERN_SUCCESS)" in dyld
      and "aborted without writing" in dyld)
check("R2c 写回校验（memcmp 16 字节 + 目标指针读回）",
      "memcmp((const void *)patchAddr, patch, 16) != 0" in dyld
      and "*(void **)((char *)patchAddr + 16) != target" in dyld
      and "mirrored write did not land" in dyld)

# R3 hooked_mmap op1 Safe 化（失败 → 干净 MAP_FAILED）
check("R3 hooked_mmap op1 Safe + MAP_FAILED 收敛",
      "if (!JIT26PrepareRegionSafe(map, len))" in dyld
      and "returning MAP_FAILED instead of hollow region" in dyld
      and "errno = EINVAL;" in dyld)

# R4 init 返回 BOOL + op4 金丝雀 + dopamine 结果收编 + 两钩落位判定
check("R4a init 签名 BOOL + 快路径返回 TRUE",
      "BOOL init_bypassDyldLibValidation(void) {" in dyld
      and "if (bypassed) return TRUE;" in dyld)
check("R4b op4 通道金丝雀（匿名 RW 探针页 round-trip，死通道 → 优雅 FALSE）",
      "op4 canary verdict=%d (scratch-page round-trip)" in dyld
      and "JIT26PrepareRegionForPatchingSafe(ame457_scratch, 16)" in dyld
      and "JIT26 op4 channel dead -- dyld hooks would crash; aborting bypass gracefully" in dyld)
check("R4b+ canary 条件收紧（★Task464：与 mirrored 内部 op4 实际调用条件一致）",
      "redirectFunction == redirectFunctionMirrored\n        && DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {" in dyld)
check("R4c 金丝雀探针页释放（无泄漏）",
      "munmap(ame457_scratch, getpagesize());" in dyld)
check("R4d dopamine 回退结果收编 + 两钩落位判定返回",
      "fcntlPatchSuccess = redirectFunction(\"dyld_fcntl (Dopamine)\", fcntlAddr, hooked___fcntl);" in dyld
      and "return ame457_mmapHookOK && fcntlPatchSuccess;" in dyld)

print("== R 修复形态执法（C：调用点优雅退出 + i18n + 代际） ==")

# R5 JavaLauncher 两调用点
check("R5a launchJVM 调用点：FALSE → 诊断窗 + handleExitCode + return 1",
      "if (!init_bypassDyldLibValidation()) {" in jl
      and "[PLLogOutputView handleExitCode:1];" in jl
      and "Task457: dyld library-validation bypass incomplete (JIT26 debugger did not serve brk #0xf00d op4) -- aborting launch gracefully" in jl)
check("R5b headless 调用点：FALSE → 诊断窗 + return -1",
      jl.count("if (!init_bypassDyldLibValidation()) {") == 2
      and "Task457: dyld library-validation bypass incomplete (headless) -- aborting gracefully" in jl)
check("R5c i18n ame457 键两调用点同引（诊断窗文案唯一来源）",
      jl.count("i18n_str_ame457_dyldhook") == 2)

# R6 i18n 全语种入册（锚点 ame451 键同面 54 文件）+ BuildTag 代际
lproj_key = 0
lproj_anchor = 0
for f in (ROOT / "Natives" / "resources").glob("*/Localizable.strings"):
    t = f.read_text(encoding="utf-8", errors="replace")
    if "i18n_str_ame457_dyldhook" in t:
        lproj_key += 1
    if "i18n_str_ame451_preflight" in t:
        lproj_anchor += 1
check("R6a i18n 全语种入册（ame457 键面 == ame451 锚点键面）",
      lproj_key == lproj_anchor and lproj_key >= 54,
      f"ame457={lproj_key} anchor={lproj_anchor}")
check("R6b BuildTag = Task464 · 2026-11-22（op4 误杀修正轮代际重锚）",
      'ame415_buildTag = @"Task464 · 2026-11-22"' in buildtag)

print("== X 全仓扫描 ==")

# X1 dyld_bypass_validation.m 裸 op1/op4 调用清零（超调用必须走 Safe）
bare = []
for sym in ("JIT26PrepareRegion(", "JIT26PrepareRegionForPatching("):
    for m in re.finditer(re.escape(sym), dyld):
        line = dyld[max(0, m.start() - 120):m.start()]
        line_head = dyld[:m.start()].rsplit("\n", 1)[-1]
        if line_head.lstrip().startswith("//"):
            continue  # 注释面不计
        bare.append(sym)
check("X1 dyld_bypass_validation.m 裸超调用清零（Safe 化家族零容忍）", not bare, ",".join(bare))

# X2 brk #0xf00d C 串字面量锁定 = 4（op1/op2/op3/op4 naked 各一；注释面不计）
asm_brk = utils_m.count('brk #0xf00d \\n')
check("X2 brk #0xf00d asm C 串 = 4（op1/op2/op3/op4 naked 各一）",
      asm_brk == 4, f"count={asm_brk}")

# X3 Task91 legacy 网不被本轮回潮破坏（brk0x69 安全网仍在位）
check("X3 Task91 legacy 安全网在位（JIT26CreateRegionLegacySafe）",
      "JIT26CreateRegionLegacySafe" in utils_m and "g_jit26TrapEnv" in utils_m)

# X4 旧「无护栏直调」形态退役面（utils.h 病历注释在场防遗忘）
check("X4 utils.h 病历留档（.ips 判例防遗忘）",
      "brk 61453" in utils_h and "Task91" in utils_h and "Task301" in utils_h)

print("== S 敏感性自证 ==")

# S1 金丝雀只在 Mirrored 路径（Direct/HW 通道零影响）
# ★Task464：canary 条件收紧为双行形态（+FORCE_MIRRORED|HAS_TXM），锚随判例更新
check("S1 金丝雀仅 Mirrored 且带 op4 实调条件（redirectFunctionDirect/HW 不受影响）",
      dyld.index("redirectFunction == redirectFunctionMirrored\n        && DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {") > dyld.index("redirectFunction = redirectFunctionMirrored;"))
check("S2 redirectFunctionDirect 函数体无 Safe 注入（零回归面）",
      "JIT26PrepareRegionForPatchingSafe" not in dyld.split("bool redirectFunctionHWBreakpoint")[0].split("bool redirectFunctionMirrored")[0])
# S3 诊断窗文案阶梯与 ame451 家族一致（弹窗键 + 三语种样本在场）
check("S3 诊断文案三语种样本（en/zh-Hans/zh-Hant）",
      all("i18n_str_ame457_dyldhook" in (ROOT / "Natives" / "resources" / d / "Localizable.strings").read_text(encoding="utf-8", errors="replace")
          for d in ("en.lproj", "zh-Hans.lproj", "zh-Hant.lproj")))
# S4 Fast 路径幂等（二次调用直接 TRUE，headless 双路径不重复建钩）
check("S4 bypassed 快路径幂等（headless 双调用点语义安全）",
      "if (bypassed) return TRUE;" in dyld)

print()
if FAILS:
    print(f"task457_selfcheck FAIL {len(FAILS)}: " + ", ".join(FAILS))
    sys.exit(1)
print("task457_selfcheck ALL PASS")
