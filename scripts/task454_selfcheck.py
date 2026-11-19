#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task454 selfcheck：「设置闪退」根因修复验收门（崩溃 .ips 符号化实锤轮）

根因：Task449（57240655f 设置折叠改造）在 ZL2SettingCards.m 给
ame449_collapsed property 声明了 getter=ame449_isCollapsed，又手写同名 getter
且体内用点语法 self.ame449_collapsed 读自身 → 点语法即 getter 分派 = 无限自
递归（用户设备实栈 31,403 帧 → 主线程栈溢出 SIGSEGV @ StackGuard）。调用面：
设置页建组 enableCollapsing → applyCollapsedAnimated 块 row.hidden =
self.ame449_collapsed 首读即爆；被 Task453「打开即闪退」根修解锁后首次可达。

本门三道防线：
  R 修复形态执法（getter 直读 ivar）
  X getter/setter 自递归家族全仓静态扫描（自定义访问器 property 全量清点，
    手写访问器体内禁点语法读写自身 property——Task453 X/O 门同型家族执法）
  S 判例留档 + 扫描器敏感性自证
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def rd(p):
    return open(os.path.join(NAT, p), encoding="utf-8").read()

# ============ R 修复形态（Task454 判例本体） ============
cards = rd("ZL2SettingCards.m")
m = re.search(r"-\s*\(BOOL\)ame449_isCollapsed\s*\{([^}]*)\}", cards)
check("R1 ame449_isCollapsed 手写 getter 在场且可提取", m is not None)
if m:
    body = m.group(1)
    check("R2 getter 体零点语法自读（self.ame449_collapsed 归零）",
          "self.ame449_collapsed" not in body)
    check("R3 getter 直读 ivar（_ame449_collapsed 在场）",
          "_ame449_collapsed" in body)
check("R4 property 声明 getter= 改名语义保留（Task449 折叠面不回退）",
      "getter=ame449_isCollapsed" in cards)
check("R5 根因判例注释留档（UUID 实锤 + 31403 栈深 + Task449 引入）",
      "★Task454 设置闪退根因修复" in cards and "58f8b2d2" in cards and "31403" in cards)

# ============ X getter/setter 自递归家族全仓静态扫描 ============
prop_pat = re.compile(r"@property\s*\(([^)]*)\)\s*[\w<>\*\s]+?\s*(\w+)\s*;")
custom = []   # (file, prop, accessorName, kind)
recursed = []
n_files = 0
for dirpath, dirnames, filenames in os.walk(NAT):
    rel = os.path.relpath(dirpath, NAT)
    if rel.split(os.sep)[0] in ("external",) or rel.startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith((".m", ".h")):
            continue
        n_files += 1
        p = os.path.join(dirpath, fn)
        txt = open(p, encoding="utf-8").read()
        decls = []
        for mm in prop_pat.finditer(txt):
            attrs, prop = mm.group(1), mm.group(2)
            g = re.search(r"getter\s*=\s*(\w+)", attrs)
            s = re.search(r"setter\s*=\s*(\w+):", attrs)
            if g:
                decls.append((prop, g.group(1), "getter"))
            if s:
                decls.append((prop, s.group(1), "setter"))
        for prop, accessor, kind in decls:
            custom.append((fn, prop, accessor, kind))
            if kind == "getter":
                impl = re.search(r"-\s*\([\w \*]+\)" + re.escape(accessor) + r"\s*\{", txt)
                if impl:
                    body = txt[impl.end():]
                    endm = re.search(r"^\}", body, re.M)
                    body = body[:endm.start()] if endm else body[:400]
                    if re.search(r"self\." + re.escape(prop) + r"\b", body):
                        recursed.append(f"{fn}: getter {accessor} dot-reads self.{prop}")
            else:
                impl = re.search(r"-\s*\(\s*void\s*\)" + re.escape(accessor) + r"\s*:", txt)
                if impl:
                    body = txt[impl.end():]
                    endm = re.search(r"^\}", body, re.M)
                    body = body[:endm.start()] if endm else body[:400]
                    if re.search(r"self\." + re.escape(prop) + r"\s*=", body):
                        recursed.append(f"{fn}: setter {accessor}: dot-writes self.{prop}")
check("X1 自定义访问器 property 全量清点非空转（覆盖面 > 5）", len(custom) > 5, f"got {len(custom)}")
check("X2 手写访问器体点语法自读/自写清零（递归家族零容忍）",
      len(recursed) == 0, "; ".join(recursed[:4]))
check("X3 扫描覆盖面（.m/.h 文件 > 50）", n_files > 50, f"scanned {n_files}")

# ============ S 判例留档 + 敏感性自证 ============
SYN = ("@property (nonatomic, assign, getter=bad_isOk) BOOL bad_ok;\n"
       "- (BOOL)bad_isOk {\n    return self.bad_ok;\n}\n")
_decl = re.search(r"@property\s*\(([^)]*)\)\s*[\w<>\*\s]+?\s*(\w+)\s*;", SYN)
_prop, _acc = (_decl.group(2), re.search(r"getter\s*=\s*(\w+)", _decl.group(1)).group(1)) if _decl else (None, None)
_impl = re.search(r"-\s*\([\w \*]+\)" + re.escape(_acc or "") + r"\s*\{", SYN) if _acc else None
_body = SYN[_impl.end():] if _impl else ""
_bad_hit = _impl is not None and re.search(r"self\." + re.escape(_prop or "") + r"\b", _body) is not None
check("S1 X 门谓词敏感性（合成自递归 getter 可命中）", _bad_hit)
check("S2 R 谓词敏感性（R2 对回归敏感：合成坏体可命中）",
      re.search(r"self\.ame449_collapsed", "- (BOOL)ame449_isCollapsed {\n    return self.ame449_collapsed;\n}") is not None)

print()
if fails:
    print(f"Task454 selfcheck: {len(fails)} FAIL -> {fails}")
    sys.exit(1)
print("Task454 selfcheck: ALL PASS")
