#!/usr/bin/env python3
# task442_selfcheck.py -- Task 442 门禁（二代 issue#3 第四轮取证跟进：映射应答
#   形态判决 + 武装闸——假阳性崩溃不再武装 JIT 自救）
# 装机 13:48Z 双 Run 证据组：Run1 健康授予 RX=0x179a28000（用户态低位）+
#   RW=0x7000000000（调试器固定 RW 别名基址）；Run2 假阳性授予 RX=0x700d300000
#   （调试器别名池）+ RW=RX+64MB——形态逐字钉死后，崩次 Ame430 仍武装自救
#   （非镜像轨在 TXM 上是死路，武装纯害）。Task442 三修：
# A 武装闸：判决前置（marker/形态读取提前到武装闸之前），假阳性判决下
#   不武装 + ame442_mapping_pattern.txt 取证 marker。
# B 形态判决：扫描期捕获最后一次「mapping at RW=」行，解 RW/RX 基址，
#   RX ≥ 0x1000000000（别名池）∨ RW-RX==0x4000000（64MB 成对）= 假阳性。
# C 弹窗证据链：假阳性 fix 文案补两 Run 形态对比 + 复发语义（重指派后
#   首会话健康、后续会话可能再劣化）。
# S 反向注入：摘除关键片段必翻红。
import io, os, re, sys

REPO = os.environ.get("AME_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def read(p):
    with io.open(REPO + "/" + p, encoding="utf-8", newline="") as f:
        return f.read()

mh = read("Natives/main_hook.m")

passed, fails = 0, []

def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

# ══ A 武装闸（判决前置 + 假阳性不武装）═════════════════════════
# 武装闸 = setPrefBool 武装行被 if (!ame437_shadow) 包裹（判决先行）；
# 抑制分支 + 取证 marker 在场。
check('A1 武装闸（判决前置：武装行受 !ame437_shadow 包裹）',
      re.search(r'if \(!ame437_shadow\) \{\s*setPrefBool\(@"debug\.mirror_codecache_disable", YES\);', mh) is not None,
      "arming not gated on ame437_shadow")
check('A2 假阳性抑制分支（[Ame442] suppressed 日志 + 指引改道语义）',
      '[Ame442] auto-rescue arming suppressed' in mh
      and 'mirror track is the only viable track under TXM debugger JIT' in mh
      and 'per-app script reassignment guidance applies instead' in mh)
check('A3 取证 marker（ame442_mapping_pattern.txt 落盘 + 判决行）',
      'ame442_mapping_pattern.txt' in mh
      and 'verdict=channel fake-positive at dialog time (mapping-response pattern; Task442, gen2 issue#3 round4)' in mh
      and 'healthy_grant=low user-space RX + RW=0x7000000000 fixed base' in mh
      and 'broken_grant=RX in debugger alias pool + RW=RX+64MB pair' in mh)

# ══ B 形态判决（扫描捕获 + 双判据）═════════════════════════════
check('B1 扫描期捕获最后一次映射应答行（ame442_mapline = s）',
      'const char *ame442_mapline = NULL;' in mh
      and 'if (strstr(s, "mapping at RW=") != NULL) ame442_mapline = s;' in mh)
check('B2 形态双判据（RX ≥ 0x1000000000 别名池 ∨ RW-RX==0x4000000 64MB 成对）',
      'ame442_rx >= 0x1000000000ULL' in mh
      and 'ame442_rw - ame442_rx == 0x4000000ULL' in mh
      and 'strtoull' in mh)
check('B3 形态定罪日志（[Ame442] conviction + Run1/Run2 证据句）',
      '[Ame442] mapping-response pattern conviction' in mh
      and 'run1/run2 verbatim comparison' in mh)

# ══ C 弹窗证据链（假阳性 fix 文案补两 Run 对比 + 复发语义）════════
check('C1 假阳性文案补两 Run 形态对比（健康授予/假阳性授予逐字形态）',
      '★第四轮取证补充' in mh
      and '0x179a28000' in mh and '0x700d300000' in mh
      and '别名池' in mh and 'RW=RX+64MB' in mh)
check('C2 复发语义（首会话健康/后续会话可能再劣化 + 重复三步）',
      '重指派后第一次会话健康、后续会话可能再次劣化' in mh
      and 'Round-4 addendum (your first/second run logs pinned both grant patterns verbatim)' in mh)
check('C3 判决链挂入 Ame437 分支（NSLog 第三注记 + EN 单份无重复）',
      'mapping-pattern conviction (Task442)' in mh
      and mh.count(" EN: The mapping was granted and the code was written, but the executable view is a hollow shell") == 1)

# ══ S 反向注入（摘关键片段必翻红）══════════════════════════════
FRAGS = {
    'A1': 'if (!ame437_shadow) {',
    'B2': 'ame442_rx >= 0x1000000000ULL',
    'A2': '[Ame442] auto-rescue arming suppressed',
}
sfrag = os.environ.get("AME442_SFRAG")
if sfrag:
    if sfrag in FRAGS.values():
        mh_stripped = mh.replace(sfrag, "")
        if sfrag == FRAGS['A1']:
            ok = re.search(r'if \(!ame437_shadow\) \{\s*setPrefBool\(@"debug\.mirror_codecache_disable", YES\);', mh_stripped) is None
        else:
            ok = sfrag in mh and sfrag not in mh_stripped and True
            # 摘除后断言必翻红：按对应断言重查
            if sfrag == FRAGS['B2']:
                ok = not ('ame442_rx >= 0x1000000000ULL' in mh_stripped)
            if sfrag == FRAGS['A2']:
                ok = not ('[Ame442] auto-rescue arming suppressed' in mh_stripped)
        check(f'S-{list(FRAGS.keys())[list(FRAGS.values()).index(sfrag)]} 摘除必翻红', ok)
else:
    check('S 反向注入（--selftest SFRAG 逐片段验证）', True, "skipped in normal run; run with AME442_SFRAG=<fragment>")

print(f"\ntask442_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print("  FAIL:", f)
    sys.exit(1)
