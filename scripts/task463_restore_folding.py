#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task463 设置折叠恢复轮：外科移植脚本。

判例翻转依据：用户 2026-11-22 明确诉求「设置折叠怎么没有恢复」——推翻 Task461
「非折叠钦定」判例中设置折叠一项（其余锁定面维持退役执法不变）。

移植面（对照 1d9abe692 = Task460 末代折叠形态，逐 hunk 溯源）：
  ① ZL2SettingCards.h：折叠 API 三声明（+14 行纯声明）
  ② ZL2SettingCards.m：折叠态实现（227 行 diff 纯折叠面，锁定面符号零污染已验证）
  ③ ZL2SettingPages.m：
     - helper 注入：ame_addGroup:title:key:defaultCollapsed:（Task449 原始裸形态
       57240655f——不带 450 时代 @try/@catch(ame450_foldEx) 降级块，零锁定面前缀）
     - 折叠调用点顺序配对 1:1 替换（组名重名 group1×10 → 按出现顺序 zip）

剔除面（锁定维持）：ame449_applyWallpaperTransparency 壁纸清扫（X2-3）、
ame450_foldEx 降级块、一切 ame455_/456_/458_/460_ 符号。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASK460 = "1d9abe692"

import subprocess

def git_show(rev, path):
    return subprocess.run(
        ["git", "show", f"{rev}:{path}"], capture_output=True, text=True,
        encoding="utf-8", errors="replace", cwd=ROOT, check=True
    ).stdout

pages_path = ROOT / "Natives/ZL2SettingPages.m"
cards_m_path = ROOT / "Natives/ZL2SettingCards.m"
cards_h_path = ROOT / "Natives/ZL2SettingCards.h"

cur = pages_path.read_text(encoding="utf-8")
t460 = git_show(TASK460, "Natives/ZL2SettingPages.m")

# ---------- ① 从 Task460 提取折叠调用块（带 title/key/defaultCollapsed 四元组） ----------
fold_call_re = re.compile(
    r"\[self ame_addGroup:(\w+)\s*\n"
    r"\s*title:(.+?)\n"
    r"\s*key:@\"([\w]+)\"\s*\n"
    r"\s*defaultCollapsed:(YES|NO)\];",
    re.S,
)
t460_calls = fold_call_re.findall(t460)
print(f"[extract] Task460 折叠调用块: {len(t460_calls)} 处")
assert len(t460_calls) == 38, f"预期 38 处折叠调用，实得 {len(t460_calls)}"

# helper 内部计数防误提（helper 定义行不会匹配上述正则——title: 后跟 key: 参数声明）
assert not any(c[0] in ("group",) and c[2] in ("key",) for c in t460_calls), "误提 helper 定义"

# ---------- ② 当前 HEAD 调用点提取 ----------
cur_call_re = re.compile(r"\[self ame_addGroup:(\w+)\];")
cur_calls = list(cur_call_re.finditer(cur))
print(f"[extract] 当前 HEAD 平铺调用点: {len(cur_calls)} 处")

# 数量对齐：两版本组调用点数应精确相等（基础版 helper 内部为 addArrangedSubview，无嵌套调用）
assert len(cur_calls) == len(t460_calls), (
    f"组调用点数不齐: HEAD {len(cur_calls)} vs Task460 {len(t460_calls)}")
print(f"[align] 组调用点数精确相等: {len(cur_calls)} 处")

# 顺序配对 + 组名一致性检查
t460_names = [c[0] for c in t460_calls]
cur_names = [m.group(1) for m in cur_calls]
mismatch = []
for i, (a, b) in enumerate(zip(cur_names, t460_names)):
    if a != b:
        mismatch.append((i, a, b))
if mismatch:
    print("[MISMATCH] 组名顺序不一致，需人工裁决:")
    for i, a, b in mismatch:
        print(f"  #{i}: HEAD={a}  Task460={b}")
    sys.exit(1)
print("[align] 组名顺序逐位一致 PASS")

# ---------- ③ 顺序替换（从后往前，防偏移） ----------
repl_positions = list(cur_calls)
# 每个替换文本：还原 Task460 原文（保持缩进四行形态）
t460_full_blocks = []
for m in fold_call_re.finditer(t460):
    t460_full_blocks.append(m.group(0))
assert len(t460_full_blocks) == len(t460_calls)

new_text = cur
for pos, block in zip(reversed(repl_positions), reversed(t460_full_blocks)):
    new_text = new_text[:pos.start()] + block + new_text[pos.end():]
print(f"[replace] 折叠调用点替换完成: {len(repl_positions)} 处")

# ---------- ④ helper 注入（Task449 裸形态，紧跟基础版定义之后） ----------
base_helper = (
    "- (void)ame_addGroup:(UIView *)group {\n"
    "    [self.groupsStack addArrangedSubview:group];\n"
    "}\n"
)
assert base_helper in new_text, "基础版 helper 锚点缺失"
fold_helper = base_helper + """
// ★Task449：追加并启用折叠组（组头标题走 ame449.setpg.group.* 键；
// 折叠态持久化 general.fold_overrides，用户覆盖压过页面默认）
- (void)ame_addGroup:(UIView *)group
               title:(NSString *)title
                 key:(NSString *)key
     defaultCollapsed:(BOOL)defaultCollapsed {
    if ([group isKindOfClass:[ZL2SettingCardGroup class]] && title.length && key.length) {
        [(ZL2SettingCardGroup *)group ame449_enableCollapsingWithTitle:title
                                                                   key:key
                                                          defaultCollapsed:defaultCollapsed];
    }
    [self ame_addGroup:group];
}
""".rstrip() + "\n"
new_text = new_text.replace(base_helper, fold_helper, 1)
print("[inject] 折叠 helper 注入（449 裸形态）")

# ---------- ⑤ 锁定面零引入断言 ----------
banned = [
    ("ame450_isCardFamilyColor", "X2-2 PC=0 雷"),
    ("ame449_applyWallpaperTransparency", "X2-3 壁纸清扫"),
    ("ame449_sweep", "X2-1 壁纸清扫"),
    ("ame455_", "X3 455 族"),
    ("ame456_", "X4 456 族"),
    ("ame458_", "X5 458 族（ame347_shellLayoutPluginOverridden 前缀族）"),
    ("ame460_", "X4-3 460 族"),
    ("ame459_", "X4-2 459 族"),
]
for sym, label in banned:
    if sym == "ame458_":
        if "ame347_shellLayoutPluginOverridden" in new_text:
            print(f"[BANNED] {label} 引入！"); sys.exit(1)
        continue
    if sym in new_text:
        print(f"[BANNED] {label} 符号 {sym} 引入！"); sys.exit(1)
print("[guard] 锁定面符号零引入 PASS")

# ---------- ⑥ 平衡断言（task240 语义） ----------
for a, b, label in [("{", "}", "花括号"), ("(", ")", "圆括号"), ("[", "]", "方括号")]:
    if new_text.count(a) != new_text.count(b):
        print(f"[BALANCE] {label} 不平衡: {new_text.count(a)} vs {new_text.count(b)}"); sys.exit(1)
print("[balance] SettingPages.m 三括号平衡 PASS")

pages_path.write_text(new_text, encoding="utf-8")
print("[write] ZL2SettingPages.m 落盘")

# ---------- ⑦ ZL2SettingCards.h / .m 移植 ----------
cards_h_cur = cards_h_path.read_text(encoding="utf-8")
cards_h_t460 = git_show(TASK460, "Natives/ZL2SettingCards.h")
# .h：diff 纯 +14 行 API 声明 → 直接整文件替换（head diff 已人工过目）
cards_h_path.write_text(cards_h_t460, encoding="utf-8")
print("[write] ZL2SettingCards.h 落盘（整文件，纯 API 声明增量）")

cards_m_t460 = git_show(TASK460, "Natives/ZL2SettingCards.m")
for sym, label in banned:
    if sym in cards_m_t460:
        print(f"[BANNED] Cards.m 含 {label} {sym}！"); sys.exit(1)
cards_m_path.write_text(cards_m_t460, encoding="utf-8")
print("[write] ZL2SettingCards.m 落盘（整文件，227 行 diff 纯折叠面）")

for a, b, label in [("{", "}", "花括号"), ("(", ")", "圆括号"), ("[", "]", "方括号")]:
    for p in (cards_h_path, cards_m_path):
        t = p.read_text(encoding="utf-8")
        if t.count(a) != t.count(b):
            print(f"[BALANCE] {p.name} {label} 不平衡"); sys.exit(1)
print("[balance] Cards.h/.m 三括号平衡 PASS")

# ---------- ⑧ 终态统计 ----------
final_pages = pages_path.read_text(encoding="utf-8")
print("\n[final] 折叠面终态:")
print(f"  ame449_enableCollapsing 调用: {final_pages.count('ame449_enableCollapsingWithTitle')}（helper 1 + 定义引用）")
print(f"  ame_addGroup:title: 折叠调用: {len(fold_call_re.findall(final_pages))}")
print(f"  平铺调用残留: {len(cur_call_re.findall(final_pages))}（应为 1 = helper 内部）")
print("DONE Task463 外科移植")
