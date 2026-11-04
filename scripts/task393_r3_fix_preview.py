#!/usr/bin/env python3
"""task393_r3_fix_preview.py -- AmeFluentPreviewMain.m 预览 TU 定点修复器（历史留档）

判读复盘（hex 字节级终局口径）：
  L388  函数尾多一个 `}` —— 真雷（块平衡字节级 Mismatch@L388 实锤，
        r4/2ab8701f 已摘除；本脚本为同修的定点替换器存档）
  L361/L379 两处「ome 手误」—— **显示层吞字节假雷**：本沙箱终端输出层
        会吞 `[h` 字节序列，`[home` 显示为 `ome`（rg/sed/od/python repr
        与 git show diff 全部受害）；真实字节 5b 68 6f 6d 65 = `[home`
        完好，无需修复。教训：疑点判读一律 bytes.hex()，显示层不作数。
本脚本对已修复文件重跑会报「匹配 0 次」并安全退出（不写不伤）。
"""
import os, sys

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "Natives/Preview/AmeFluentPreviewMain.m")
src = open(P, encoding="utf-8").read()

FIXES = [
    # (旧字节串, 新字节串, 说明)
    ('NSString *accounts = ome stringByAppendingPathComponent:@"accounts"];',
     'NSString *accounts = [home stringByAppendingPathComponent:@"accounts"];',
     "L361 accounts 路径：补 [ + ome→home"),
    ('NSString *dir = [ome stringByAppendingPathComponent:@"versions"]\n                         stringByAppendingPathComponent:vid];',
     'NSString *dir = [[home stringByAppendingPathComponent:@"versions"]\n                         stringByAppendingPathComponent:vid];',
     "L379 versions 路径：补内层 [ + ome→home"),
    ('                atomically:YES encoding:NSUTF8StringEncoding error:nil];\n    }\n}\n}\n\n// 顶栏页名',
     '                atomically:YES encoding:NSUTF8StringEncoding error:nil];\n    }\n}\n\n// 顶栏页名',
     "L388 函数尾多余 } 摘除"),
]

for old, new, desc in FIXES:
    n = src.count(old)
    if n != 1:
        print(f"FAIL: [{desc}] 匹配 {n} 次（期望 1），中止不写")
        sys.exit(1)
    src = src.replace(old, new)

open(P, "w", encoding="utf-8").write(src)

# 块平衡复核（剥字符串/注释后 {()}[] 配平）
def strip_sc(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3; i += 1
            elif c == "/" and nxt == "*": mode = 4; i += 1
            elif c in "([{)]}": out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

pairs = {")": "(", "]": "[", "}": "{"}
stack, bad = [], None
for ch in strip_sc(src):
    if ch in "([{":
        stack.append(ch)
    elif ch in ")]}":
        if not stack or stack.pop() != pairs[ch]:
            bad = ch; break
print("块平衡:", "OK" if bad is None and not stack else f"BAD({bad}, stack={stack[-3:]})")
print("三处修复完成")
for ln in (361, 379, 388):
    print(f"  L{ln}: {src.splitlines()[ln-1].strip()[:76]}")
