#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task453 selfcheck：「打开即闪退」根因修复验收门（崩溃日志符号化实锤轮）

根因：Task450② ame450_isCardFamilyColor 的 dispatch_once 块内把三族色数组当
block 表枚举（for (UIColor *(^token)(void) in @[UIColor…]) → token() 把 UIColor
对象偏移 16 当 block invoke 指针跳转 = PC=0 EXC_BAD_ACCESS / CODESIGNING Invalid
Page）。wallpaper=1 设备壳 viewDidLoad→ame429 刷新→ame449 清扫→本方法
dispatch_once 首路径必崩；编译期零告警、CI 无壁纸零覆盖、450/451/452 三代构
建均含本雷（用户崩溃日志 0f1c98c1 符号化实锤，栈底 ZL2ShellViewController
viewDidLoad → ame429_installBackgroundHost → ame429_refresh block →
makeViewControllerTransparent → ame449_sweep → ame450_isCardFamilyColor +
dispatch_once → NULL）。

本门四道防线：
  R 修复形态执法（Task453 判例本体）
  X 全仓 block 型 for-in 循环变量清单执法（同类雷静态扫描，允许清单入册制）
  O dispatch_once 第二实参必须字面量 ^{ 起步（nil-block 传参类雷零容忍）
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

# ============ R 修复形态（Task453 判例本体） ============
bm = rd("BackgroundManager.m")
check("R1 三族色循环改为直接枚举 UIColor（恰 1 处）",
      bm.count("for (UIColor *ame450_t in @[[ZL2Theme surfaceContainer], [ZL2Theme surfaceContainerHigh], [ZL2Theme surfaceContainerLow]]") == 1)
check("R2 旧雷零残留（block 指针声明与调用双计数归零）",
      bm.count("(^token)(void)") == 0 and bm.count("= token();") == 0)
check("R3 家族色赋值链完整（dark/light 双族 copy 在场）",
      bm.count("ame450_darkFamily = [ame450_d copy];") == 1
      and bm.count("ame450_lightFamily = [ame450_l copy];") == 1)

# ============ X 全仓 block 型 for-in 循环变量清单执法 ============
# 扫描 Natives/**/*.m（external 除外）中形如 for (…^… in …) 的块指针循环变量。
# 允许清单（入册制，新增合法面必须在此登记）：
#   IconLoader.m : 1 —— 枚举 NSArray<void(^)(UIImage * _Nullable)> *callbacks
#   （请求方真 block 集合，completeRequestWithCacheKey 分发面）
ALLOW_BLOCK_LOOP = {"IconLoader.m": 1}

pat = re.compile(r"for\s*\(([^{]*\^[^{]*)in\b")
found = {}
n_scanned = 0
for dirpath, dirnames, filenames in os.walk(NAT):
    rel = os.path.relpath(dirpath, NAT)
    if rel.split(os.sep)[0] in ("external",) or rel.startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith(".m"):
            continue
        n_scanned += 1
        txt = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        hits = len(pat.findall(txt))
        if hits:
            found[fn] = found.get(fn, 0) + hits
check("X1 block 型 for-in 清单 = 允许清单（零未入册同类雷）",
      found == ALLOW_BLOCK_LOOP,
      f"got {found}")
check("X2 扫描非空转（.m 文件覆盖面 > 50）", n_scanned > 50, f"scanned {n_scanned}")

# ============ O dispatch_once 第二实参字面量执法（nil-block 类雷） ============
# dispatch_once(&tok, ^{…}) 合法；dispatch_once(&tok, blkVar) 形式 = block 实参
# 可为 nil → _dispatch_once_callout blr NULL → PC=0（Task453 崩溃同族机理面）。
# 判据：逗号后首个非空白字符必须 '^'（字面量块恒 ^{ 起步；变量传参首字符为
# 字母/下划线。不用 [^)] 闭合匹配——字面量体内含嵌套括号会破匹配，Task453 首版自斥判例）。
bad_once = []
for dirpath, dirnames, filenames in os.walk(NAT):
    rel = os.path.relpath(dirpath, NAT)
    if rel.split(os.sep)[0] in ("external",) or rel.startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith(".m"):
            continue
        for i, line in enumerate(open(os.path.join(dirpath, fn), encoding="utf-8"), 1):
            m = re.search(r"dispatch_once\s*\(\s*&\s*\w+\s*,\s*(\S)", line)
            if m and m.group(1) != "^":
                bad_once.append(f"{fn}:{i}: {line.strip()[:80]}")
check("O1 dispatch_once 第二实参全字面量 ^{ 起步（零变量传参）",
      len(bad_once) == 0, "; ".join(bad_once[:4]))

# ============ S 判例留档 + 敏感性自证 ============
check("S1 根因判例注释留档（UUID 实锤 + 机理）",
      "★Task453 打开即闪退根因修复" in bm and "0f1c98c1" in bm
      and "CODESIGNING" in bm)
_check_bad = re.search(r"dispatch_once\s*\(\s*&\s*\w+\s*,\s*(\S)",
                       "dispatch_once(&t, blk);")
_check_lit = re.search(r"dispatch_once\s*\(\s*&\s*\w+\s*,\s*(\S)",
                       "dispatch_once(&t, ^{ x; });")
check("S2 O 门谓词敏感性（坏形态命中 / 字面量形态零命中）",
      _check_bad is not None and _check_bad.group(1) != "^"
      and _check_lit is not None and _check_lit.group(1) == "^")
check("S3 X 门谓词敏感性（合成 block 循环变量可命中）",
      pat.search("for (void(^cb)(UIImage *) in callbacks) {") is not None)

print()
if fails:
    print(f"Task453 selfcheck: {len(fails)} FAIL -> {fails}")
    sys.exit(1)
print("Task453 selfcheck: ALL PASS")
