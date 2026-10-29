#!/usr/bin/env python3
# task343_welcome_anchor_cut.py -- 摘除 WelcomeViewController.m 旧壳锚点块
# （锚点1-5：ame233_menuVC/contentVC/rightVC 消费段），保留 ZL2 专用锚点集
# 与收尾空判定。字节级逐行定位，保 LF 行尾。
import io, sys

PATH = "Natives/WelcomeViewController.m"
with io.open(PATH, "r", encoding="utf-8", newline="") as f:
    lines = f.readlines()

start = end = None
for i, ln in enumerate(lines):
    if start is None and "---- 锚点 1：侧边导航" in ln:
        start = i
    if start is not None and "if (items.count == 0) {" in ln and i > start:
        end = i
        break

assert start is not None and end is not None, "marker not found"
# 回溯：start 前的连续空行一并归入删除域（保持段间一个空行节奏）
while start > 0 and lines[start - 1].strip() == "":
    start -= 1

replacement = [
    "    // ---- Task343：旧壳锚点 1-5（ame233_menuVC/contentVC/rightVC 消费段）\n",
    "    //      随旧壳家族物理退役整体摘除——ZL2 专用锚点集（上方锚 A/B/C）\n",
    "      已是唯一锚点源；非 ZL2 根（理论不可达）items 恒空，由收尾空判定\n",
    "      直进关于页（Task225 语义：引导是增强，绝不阻塞）。\n",
]

# 替换 [start, end) 区间（end 行 = if (items.count == 0) 保留）
new_lines = lines[:start] + replacement + lines[end:]
with io.open(PATH, "w", encoding="utf-8", newline="") as f:
    f.writelines(new_lines)

print(f"cut lines {start + 1}..{end} -> {len(replacement)} comment lines; total {len(lines)} -> {len(new_lines)}")
# 自检：文件内不再有旧锚点消费符号（注释行豁免——替换说明文字本身提及符号名）
body = "".join(new_lines)
for sym in ("ame233_menuVC", "ame233_rightVC", "ame233_contentVC", "ame234_launchAnchorView", "ame235_versionAnchorView"):
    for ln in body.split("\n"):
        code_part = ln.split("//", 1)[0]
        assert sym not in code_part, f"residual code ref {sym}: {ln.strip()[:80]}"
print("residual check: ame233/ame234/ame235 anchor symbols all cleared (comments exempted)")
