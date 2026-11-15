#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ★ Task429 主控合流：六工位 i18n 片段（BC/F/G/H/J/S1，D/E 为空集）合并进四全表。
#   纪律：四表同步追加、键集四表一致、追前查重（与既有 3946 键及彼此零冲突）、
#   追后行数一致 = 3946 + N。片段格式 = task428_i18n_A.json 同构。
import json, re, sys, io

FRAGMENTS = ["BC", "F", "G", "H", "J", "S1"]
TABLES = {
    "en":      "Natives/resources/en.lproj/Localizable.strings",
    "zh-Hans": "Natives/resources/zh-Hans.lproj/Localizable.strings",
    "zh-CN":   "Natives/resources/zh-CN.lproj/Localizable.strings",
    "zh-Hant": "Natives/resources/zh-Hant.lproj/Localizable.strings",
}

def esc(s):
    # .strings 转义：反斜杠与双引号；换行保持 \n 字面量
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def parse_existing_keys(text):
    keys = set()
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M):
        keys.add(m.group(1).replace('\\"', '"').replace('\\\\', '\\'))
    return keys

def main():
    merged = {}   # key -> {locale: value}
    for frag in FRAGMENTS:
        path = f"scripts/task429_i18n_{frag}.json"
        data = json.load(open(path, encoding="utf-8"))
        for k, loc in data.items():
            if k in merged:
                sys.exit(f"FATAL: 跨片段键冲突 {k}")
            missing = [l for l in TABLES if l not in loc]
            if missing:
                sys.exit(f"FATAL: {k} 缺 locale {missing}")
            merged[k] = loc
    if not merged:
        print("空集，无需合并"); return

    results = {}
    for lang, path in TABLES.items():
        text = io.open(path, encoding="utf-8").read()
        existing = parse_existing_keys(text)
        dup = [k for k in merged if k in existing]
        if dup:
            sys.exit(f"FATAL: {path} 既有键冲突 {dup[:5]}")
        block = "\n// ── ★ Task429（PDF v5 P2 批 + v6 修复 + Horizon S1：主控合流，%d 键）──\n" % len(merged)
        for k in sorted(merged):
            block += '"%s" = "%s";\n' % (esc(k), esc(merged[k][lang]))
        text = text.rstrip("\n") + "\n" + block
        io.open(path, "w", encoding="utf-8").write(text)
        results[lang] = (len(existing), len(existing) + len(merged))

    counts = {lang: v[1] for lang, v in results.items()}
    assert len(set(counts.values())) == 1, f"四表行数不一致 {counts}"
    print("合并完成：%d 键 × 4 表；四表终态 %d（3946 → %d）" % (len(merged), counts["en"], counts["en"]))
    for lang, (before, after) in results.items():
        print(f"  {lang}: {before} → {after}")

if __name__ == "__main__":
    main()
