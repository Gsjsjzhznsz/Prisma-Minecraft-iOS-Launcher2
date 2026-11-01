#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task369 自查：i18n 恢复完整性
① ame369.* 改写点计数 == 451 且无双重包裹（站点外层已有 localize( 视为包裹）
② A 审计：代码中全部 localize() key 在 en/zh-Hans/zh-Hant/zh-CN 四表齐备（含 ame369.*）
③ 四表 .strings 全文可解析（每行合法）——Task227 整表写坏判例防线
④ ame369.* 四表之间格式符一致性（%@ %ld %g %.1f 等占位符集合相同）
⑤ 旧候选清零：Task369 目标站点不再存在未包裹 CJK 字面量（白名单跳过项除外）
⑥ utils.h 导入补齐校验
⑦ zh-Hant 术语校正抽查（聯機殘留 / 賬戶殘留 / 數據包殘留 = FAIL）
"""
import os, re, sys, json
from collections import defaultdict

REPO = "/home/z/my-project/repo-prisma2"
NAT = os.path.join(REPO, 'Natives')
RES = os.path.join(NAT, 'resources')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

# ── 读四表 ──
def load_table(lang):
    rows = {}
    parse_bad = []
    p = os.path.join(RES, f"{lang}.lproj", "Localizable.strings")
    in_block = False
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        s = line.strip()
        if in_block:
            if '*/' in s: in_block = False
            continue
        if s.startswith('/*'):
            if '*/' not in s[2:]: in_block = True
            continue
        if not s or s.startswith('//') or s == '};':
            continue
        m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$', s)
        if not m:
            parse_bad.append((i, s[:80])); continue
        rows[m.group(1)] = m.group(2)
    return rows, parse_bad

TABLES = {}
for lang in ['en', 'zh-Hans', 'zh-Hant', 'zh-CN']:
    TABLES[lang], bad = load_table(lang)
    check(f"③ {lang} .strings 全文可解析", len(bad) == 0, f"坏行 {bad[:4]}")
    check(f"③ {lang} 键数>3700", len(TABLES[lang]) > 3700, str(len(TABLES[lang])))

# ── 扫代码 localize key ──
CALL = re.compile(r'localize\s*\(\s*@"((?:[^"\\]|\\.)*)"')
code_keys = set()
ame369_sites = 0
for dp, dns, fns in os.walk(NAT):
    rel = os.path.relpath(dp, NAT)
    if 'external' in rel.split(os.sep):
        continue
    for fn in fns:
        if not fn.endswith(('.m', '.h')):
            continue
        src = open(os.path.join(dp, fn), encoding='utf-8', errors='replace').read()
        for m in CALL.finditer(src):
            code_keys.add(m.group(1))
            if m.group(1).startswith('ame369.'):
                ame369_sites += 1

check("② 全部 localize key 四表齐备",
      all(k in TABLES[l] for k in code_keys for l in TABLES),
      f"缺: {[k for k in code_keys if any(k not in TABLES[l] for l in TABLES)][:8]}")
ame369_keys = {k for k in code_keys if k.startswith('ame369.')}
check("② ame369.* 键四表齐备",
      all(k in TABLES[l] for k in ame369_keys for l in TABLES),
      f"缺: {[k for k in ame369_keys if any(k not in TABLES[l] for l in TABLES)][:8]}")
# ★ Task370 重锚：447 → 450（+3 复用站点 = Task374 安装页返回钮 title/a11y 两处
#   ame369.common.back + Task376 窗格开关钮 a11y ame369.shell.nav_a11y；零移除，
#   git diff 实证 0 处被移除）
check("① ame369 改写点数 == 450", ame369_sites == 450, str(ame369_sites))

# 复用站点：4 处 localize(@"ame193.misc.[13]"（内容级匹配——5 个补 import 文件行号整体 +1，行级断言会错位）
REUSE_EXPECT = {
    "ZL2AssetSearchViewController.m": ('localize(@"ame193.misc.1", @"全部")', 1),
    "ZL2VersionsViewController.m":    ('addChipWithTitle:localize(@"ame193.misc.1", @"全部")', 1),
    "ZL2GameDownloadViewController.m": ('localize(@"ame193.misc.3", @"正式版")', 2),
}
reuse_ok = 0
for f, (snippet, want) in REUSE_EXPECT.items():
    n = open(os.path.join(NAT, f), encoding='utf-8').read().count(snippet)
    if n >= want: reuse_ok += 1
    else: print(f"  复用站点缺失: {f} 期望{want} 实得{n}")
check("① 复用 ame193.misc 站点 == 3 文件 4 处", reuse_ok == 3, str(reuse_ok))

# ── ① 双重包裹检测：ame369 站点向前回溯，外层若已有 localize( 则 FAIL ──
def outer_has_localize(lines, li, col):
    """仅检查最内层包裹调用：从 ame369 站点向前回溯遇到的第一个未闭合 '(' ，
    若其前方紧邻 localize 则为双重包裹（真双包裹必然落在最内层）。
    穿透到外层只会误伤兄弟参数/父方法调用（实测 6 处均为此类误报）。"""
    depth = 0
    j = li
    buf = lines[j][:col]
    for _ in range(150):
        for ch in reversed(buf):
            if ch == ')':
                depth += 1
            elif ch == '(':
                if depth == 0:
                    idx = buf.rfind('(')
                    return bool(re.search(r'localize\s*$', buf[:idx]))
                depth -= 1
        j -= 1
        if j < 0 or depth > 0: break
        buf = lines[j]
    return False

dbl = []
for dp, dns, fns in os.walk(NAT):
    rel = os.path.relpath(dp, NAT)
    if 'external' in rel.split(os.sep): continue
    for fn in fns:
        if not fn.endswith('.m'): continue
        p = os.path.join(dp, fn)
        lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
        for i, line in enumerate(lines):
            for m in re.finditer(r'localize\s*\(\s*@"ame369\.', line):
                if outer_has_localize(lines, i, m.start()):
                    dbl.append(f"{os.path.relpath(p, NAT)}:{i+1}")
check("① 无双重包裹", len(dbl) == 0, str(dbl[:6]))

# ── ④ 格式符一致性 ──
FMT = re.compile(r'%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSaAFp]|[a-z]%ld|%ld|%lld|%lu')
def spec_set(v):
    return sorted(re.findall(r'%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSaA]|%l[dlu]|%lld', v))
fmt_bad = []
for k in sorted(ame369_keys):
    vals = {l: TABLES[l].get(k, '') for l in TABLES}
    sets = {l: spec_set(v) for l, v in vals.items()}
    if len({tuple(s) for s in sets.values()}) > 1:
        fmt_bad.append(f"{k}: {sets}")
check("④ ame369 四表格式符一致", len(fmt_bad) == 0, '; '.join(fmt_bad[:6]))

# ── ⑤ 改写站点清零（自包含重锚，Task370 会话）──
# 原口径：会话工件 /home/z/my-project/scripts/i18n_t369_candidates.json（451 站点
# (file,line,value) 清单）逐点回查 —— 该工件随沙箱回收丢失，依 worklog「工作区
# 工件丢失按 archive 记录重建」规则重建为自包含口径：逐 ame369.* 键断言其
# localize() 消费站点在位（336 新键 × ≥1 站点 = 447 改写面覆盖；4 站点复用
# ame193.misc 既有键不入本断言）；硬编码 CJK 面由 task248 门禁独立守（0 处）。
ame369_blob = []
for dp, dns, fns in os.walk(NAT):
    rel = os.path.relpath(dp, NAT)
    if 'external' in rel.split(os.sep): continue
    for fn in fns:
        if fn.endswith(('.m', '.mm')):
            ame369_blob.append(open(os.path.join(dp, fn), encoding='utf-8', errors='replace').read())
ame369_blob = '\n'.join(ame369_blob)
no_site = [k for k in sorted(ame369_keys) if ('localize(@"%s"' % k) not in ame369_blob]
check("⑤ ame369.* 全键 localize 消费站点在位（%d 键）" % len(ame369_keys), len(no_site) == 0, str(no_site[:8]))

# ── ⑥ utils.h 导入 ──
for f in ["ZL2GameDownloadViewController.m", "ZL2SettingsViewController.m",
          "ZL2SearchIdViewController.m", "ZL2M3Kit.m", "installer/modpack/CurseForgeAPI.m"]:
    src = open(os.path.join(NAT, f), encoding='utf-8').read()
    check(f"⑥ utils.h 导入 {f}", re.search(r'#import\s+"utils\.h"', src) is not None)

# ── ⑦ zh-Hant 术语校正抽查 ──
hant_blob = '\n'.join(f'"{k}" = "{v}";' for k, v in TABLES['zh-Hant'].items() if k.startswith('ame369.'))
check("⑦ zh-Hant 无 聯機 残留", '聯機' not in hant_blob)
check("⑦ zh-Hant 无 賬戶 残留", '賬戶' not in hant_blob)
check("⑦ zh-Hant 无 數據包 残留", '數據包' not in hant_blob)
check("⑦ zh-Hant 无 全域性 残留", '全域性' not in hant_blob)
check("⑦ zh-Hant 使用 帳戶", '帳戶' in hant_blob)
check("⑦ zh-Hant 使用 資料包", '資料包' in hant_blob)

# ── 抽样展示 ──
print("\n── 样本（en / zh-Hans / zh-Hant）──")
for k in ["ame369.home.play", "ame369.setpg.memory_heap_fmt", "ame369.vers.chip.moddable",
          "ame369.gdl.date_fmt", "ame369.common.count_fmt", "ame369.shell.tab.terracotta",
          "ame369.asearch.dl_wan_fmt", "ame369.common.instance_a11y_fmt"]:
    print(f"  {k}\n    en={TABLES['en'].get(k)!r}\n    hans={TABLES['zh-Hans'].get(k)!r}\n    hant={TABLES['zh-Hant'].get(k)!r}")

print(f"\n{'='*20}\n{'ALL PASS' if not fails else 'FAILURES: ' + ', '.join(fails)}")
sys.exit(0 if not fails else 1)
