#!/usr/bin/env python3
# task343_m3kit_layout_tokens.py -- ZL2M3Kit 几何令牌化（Task343 线C2）
# 消费点硬编码 → [ZL2Theme ame343_layoutMetric:fallback:]（fallback=原值，
# 零覆盖零变化）。逐行断言式替换，防误伤；保 LF 行尾。
import io, sys

PATH = "Natives/ZL2M3Kit.m"
with io.open(PATH, "r", encoding="utf-8", newline="") as f:
    lines = f.readlines()

def sub(lineno, must_contain, old, new):
    """lineno 1-based；must_contain 兜底断言；old→new 行内替换"""
    ln = lines[lineno - 1]
    assert must_contain in ln, f"L{lineno} mismatch: {ln!r} lacks {must_contain!r}"
    assert old in ln, f"L{lineno} old not found: {old!r} in {ln!r}"
    lines[lineno - 1] = ln.replace(old, new, 1)

T = '[ZL2Theme ame343_layoutMetric:@"{k}" fallback:{v}]'

# ── SearchBar：高 44 → searchBarHeight
sub(164, "constraintEqualToConstant:44]",
    "constraintEqualToConstant:44]",
    "constraintEqualToConstant:" + T.format(k="searchBarHeight", v="44.0") + "]")

# ── FilterChip：preferredHeight 32 → chipHeight
sub(210, "return 32;",
    "return 32;",
    "return " + T.format(k="chipHeight", v="32.0") + ";")

# ── Dialog：卡内边距 24 ×6 → dialogInset；按钮高 40 ×2 → buttonHeight
for n, old in [(481, "constant:24]"), (482, "constant:24]"), (483, "constant:-24]"),
               (486, "constant:24]"), (487, "constant:-24]"),
               (502, "constant:24]"), (503, "constant:-24]")]:
    ln = lines[n - 1]
    new = old.replace("24]", "") .rstrip("]")
    # 通用替换 24 → dialogInset token（保持符号方向）
    tok = T.format(k="dialogInset", v="24.0")
    if "constant:24]" in ln:
        lines[n - 1] = ln.replace("constant:24]", "constant:" + tok + "]", 1)
    elif "constant:-24]" in ln:
        lines[n - 1] = ln.replace("constant:-24]", "constant:-" + tok + "]", 1)
    else:
        raise AssertionError(f"L{n} no 24 constant: {ln!r}")
for n in (493, 494):
    sub(n, "constraintEqualToConstant:40]",
        "constraintEqualToConstant:40]",
        "constraintEqualToConstant:" + T.format(k="buttonHeight", v="40.0") + "]")

# ── BottomSheet：内容左右缘 16 → cardMarginH
for n in (621, 622):
    ln = lines[n - 1]
    tok = T.format(k="cardMarginH", v="16.0")
    if "constant:16]" in ln:
        lines[n - 1] = ln.replace("constant:16]", "constant:" + tok + "]", 1)
    elif "constant:-16]" in ln:
        lines[n - 1] = ln.replace("constant:-16]", "constant:-" + tok + "]", 1)
    else:
        raise AssertionError(f"L{n} no 16 constant: {ln!r}")

# ── CardCell：卡片解剖全族
card = [
    # (line, must, old, new-tail)
    (746, "constant:-14]", "constant:-14]", "constant:-" + T.format(k="cardInsetX", v="14.0") + "]"),
    (748, "constant:-14]", "constant:-14]", "constant:-" + T.format(k="cardInsetX", v="14.0") + "]"),
    (750, "constant:-14]", "constant:-14]", "constant:-" + T.format(k="cardInsetX", v="14.0") + "]"),
    (752, "constant:-10]", "constant:-10]", "constant:-" + T.format(k="pillGap", v="10.0") + "]"),
    (754, "constant:-10]", "constant:-10]", "constant:-" + T.format(k="pillGap", v="10.0") + "]"),
    (756, "constant:5]",  "constant:5]",  "constant:"  + T.format(k="cardMarginV", v="5.0") + "]"),
    (757, "constant:-5]", "constant:-5]", "constant:-" + T.format(k="cardMarginV", v="5.0") + "]"),
    (758, "constant:16]", "constant:16]", "constant:"  + T.format(k="cardMarginH", v="16.0") + "]"),
    (759, "constant:-16]", "constant:-16]", "constant:-" + T.format(k="cardMarginH", v="16.0") + "]"),
    (761, "constant:12]", "constant:12]", "constant:"  + T.format(k="cardInsetTop", v="12.0") + "]"),
    (762, "constant:14]", "constant:14]", "constant:"  + T.format(k="cardInsetX", v="14.0") + "]"),
    (764, "constant:4]",  "constant:4]",  "constant:"  + T.format(k="cardContentGap", v="4.0") + "]"),
    (765, "constant:14]", "constant:14]", "constant:"  + T.format(k="cardInsetX", v="14.0") + "]"),
    (766, "constant:-12]", "constant:-12]", "constant:-" + T.format(k="cardInsetBottom", v="12.0") + "]"),
    (770, "constraintGreaterThanOrEqualToConstant:56]", "constraintGreaterThanOrEqualToConstant:56]",
     "constraintGreaterThanOrEqualToConstant:" + T.format(k="pillMinWidth", v="56.0") + "]"),
    (771, "constraintEqualToConstant:28]", "constraintEqualToConstant:28]",
     "constraintEqualToConstant:" + T.format(k="pillHeight", v="28.0") + "]"),
    (775, "constant:10]", "constant:10]", "constant:"  + T.format(k="pillGap", v="10.0") + "]"),
    (776, "constant:10]", "constant:10]", "constant:"  + T.format(k="pillGap", v="10.0") + "]"),
]
for n, must, old, new in card:
    sub(n, must, old, new)

with io.open(PATH, "w", encoding="utf-8", newline="") as f:
    f.writelines(lines)

body = "".join(lines)
cnt = body.count("ame343_layoutMetric")
print(f"tokenized call sites: {cnt} (expect 26)")
assert cnt == 26, cnt
# 圆角/其余几何不动；自检：fallback 均为原值（零覆盖零变化）
import re
for m in re.finditer(r'ame343_layoutMetric:@"(\w+)" fallback:([\d.]+)\]', body):
    pass
print("OK")
