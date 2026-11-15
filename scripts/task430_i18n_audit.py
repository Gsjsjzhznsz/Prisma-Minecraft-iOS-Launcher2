#!/usr/bin/env python3
# Task430 (i18n full audit, task250 口径重锚)
# 1) Four-table presence check for every literal key referenced via localize()/MPLocalized()
#    (含多行调用形态：键与 fallback 可能跨行，按全文正则提取)
# 2) "key shown as value" check: any table row whose VALUE equals its KEY（自然英文词键豁免）
# 3) CJK-in-en check: en 表出现简体专用汉字（语言名原生展示行豁免 ame193.misc.6 / component.touch.done 双语行豁免）
# 4) 54 表覆盖矩阵快照（moderate coverage report, 判读用非门禁）
# Exit code: 0 = pass, 1 = findings (找缺口后修数清零再交付)
import re, os, sys, glob, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Natives"))
RES = os.path.join(ROOT, "resources")
FOUR = ["en", "zh-CN", "zh-Hans", "zh-Hant"]

ROW = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
NATURAL = re.compile(r'^[A-Za-z0-9 _\-+%.,:!?()\[\]/&：#@{}%$\'"“”…·。：；、（）]+$')
cjk = re.compile(r'[\u4e00-\u9fff]')
# 简体专用汉字抽样（日语/繁体不会出现的简化字形）
SIMP_ONLY = re.compile(r'[设这为汉语启动图么们当发见围国报应现实现关证测试块热约级张态录临览点击盘账输环网关连签账户访创错请记识归确认败复制迁暂执行环构导确删隐私钥鉴显终端器存储]')
BILINGUAL_OK = {"ame193.misc.6", "component.touch.done"}  # 语言原生名 / 双语对照行（设计如此）

def load_table(lang):
    table = {}
    with open(os.path.join(RES, lang + ".lproj", "Localizable.strings"), encoding="utf-8") as f:
        for line in f:
            m = ROW.match(line)
            if m:
                table[m.group(1)] = m.group(2)
    return table

tables = {lang: load_table(lang) for lang in FOUR}
print("== four-table sizes:", {k: len(v) for k, v in tables.items()})

# ---------- 1) literal localize keys (full-file regex, 跨行形态天然覆盖) ----------
lit = set()
src_files = [p for p in glob.glob(os.path.join(ROOT, "**", "*.m"), recursive=True)
             if os.sep + "resources" + os.sep not in p and os.sep + "external" + os.sep not in p]
KEYCALL = re.compile(r'(?:localize|MPLocalized)\(\s*@"((?:[^"\\]|\\.)*)"', re.S)
for path in src_files:
    src = open(path, encoding="utf-8", errors="replace").read()
    for m in KEYCALL.finditer(src):
        lit.add(m.group(1))
print(f"== literal localize keys in {len(src_files)} files: {len(lit)}")

missing = collections.defaultdict(list)   # key -> [lang...]
for k in sorted(lit):
    for lang in FOUR:
        if k not in tables[lang]:
            missing[k].append(lang)
if missing:
    print(f"== MISSING IN TABLES: {len(missing)} keys")
    for k, langs in list(missing.items())[:80]:
        print(f"   {k}  missing in: {','.join(langs)}")
else:
    print("== four-table presence: PASS (0 missing)")

# ---------- 2) value==key ----------
# 真病灶口径：ASCII 键名（i18n_str_N / ameNNN.* / 模块键）值却等于键名 = 未翻译裸键泄漏；
# CJK 键 == CJK 值（如 "提示"="提示"）= 键本身即自然语言词，良性豁免。
kv_hits = []
for lang, t in tables.items():
    for k, v in t.items():
        if v == k and not NATURAL.match(k) and k not in BILINGUAL_OK \
           and not cjk.search(k):
            kv_hits.append((lang, k))
print("== value==key anomalies:", len(kv_hits), kv_hits[:10])

# ---------- 3) CJK in en (excluding bilingual-by-design rows) ----------
cjk_en = [k for k, v in tables["en"].items()
          if cjk.search(v) and k not in BILINGUAL_OK]
simp_en = [k for k, v in tables["en"].items()
           if SIMP_ONLY.search(v) and k not in BILINGUAL_OK]
print("== en rows containing any CJK:", len(cjk_en), cjk_en[:8])
print("== en rows containing simplified-only hanzi:", len(simp_en), simp_en[:8])

# ---------- 4) 54-table coverage snapshot ----------
print("== 54-table coverage snapshot (rows / overlap with modern key set):")
modern = set(tables["zh-Hans"].keys())
for lproj in sorted(glob.glob(os.path.join(RES, "*.lproj"))):
    lang = os.path.basename(lproj).replace(".lproj", "")
    path = os.path.join(lproj, "Localizable.strings")
    if not os.path.exists(path):
        print(f"   {lang}: NO STRINGS FILE")
        continue
    keys = set(m.group(1) for m in
               (ROW.match(line) for line in open(path, encoding="utf-8")) if m)
    print(f"   {lang}: {len(keys)} rows, {len(keys & modern)} modern")

fail = bool(missing or kv_hits or simp_en)
print("== RESULT:", "FAIL" if fail else "PASS")
sys.exit(1 if fail else 0)
