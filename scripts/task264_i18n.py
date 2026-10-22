#!/usr/bin/env python3
# task264_i18n — 7.0-UI-16 新键 54 表补齐（dl.asset.* 六键：主语言实译 +
# zh-Hant 繁体实译 + 其余 EN 兜底；repo 判例 task311_i18n 同款）
import glob, os, sys

KEYS = {
    "dl.asset.filter.name": {
        "zh-Hans": "搜索名称", "zh-Hant": "搜尋名稱", "zh-CN": "搜索名称",
        "en": "Search name",
    },
    "dl.asset.filter.version": {
        "zh-Hans": "游戏版本", "zh-Hant": "遊戲版本", "zh-CN": "游戏版本",
        "en": "Game version",
    },
    "dl.asset.filter.platform": {
        "zh-Hans": "目标平台", "zh-Hant": "目標平台", "zh-CN": "目标平台",
        "en": "Platform",
    },
    "dl.asset.version.any": {
        "zh-Hans": "不限版本", "zh-Hant": "不限版本", "zh-CN": "不限版本",
        "en": "Any version",
    },
    "dl.asset.import": {
        "zh-Hans": "导入整合包", "zh-Hant": "匯入整合包", "zh-CN": "导入整合包",
        "en": "Import modpack",
    },
    "dl.asset.favorites.empty": {
        "zh-Hans": "暂无收藏", "zh-Hant": "暫無收藏", "zh-CN": "暂无收藏",
        "en": "No favorites yet",
    },
    "dl.asset.page": {
        "zh-Hans": "第 %ld 页", "zh-Hant": "第 %ld 頁", "zh-CN": "第 %ld 页",
        "en": "Page %ld",
    },
}

tables = sorted(glob.glob("Natives/resources/*.lproj/Localizable.strings"))
if not tables:
    raise SystemExit("no tables found")
added = 0
for path in tables:
    lang = path.split("/")[-2].replace(".lproj", "")
    with open(path, encoding="utf-8", newline="") as f:
        content = f.read()
    nl = "\r\n" if "\r\n" in content else "\n"
    # 简繁繁陆别名归一（zh-Hant 表可能叫 zh-Hant/zh-TW 语义，按目录名匹配）
    if lang.startswith("zh-Hant") or lang == "zh-TW" or lang == "zh-HK":
        text_lang = "zh-Hant"
    elif lang.startswith("zh"):
        text_lang = "zh-Hans"
    else:
        text_lang = "en"
    dirty = False
    for key, variants in KEYS.items():
        if ('"%s"' % key) in content:
            continue
        content += '%s"%s" = "%s";%s' % (nl, key, variants[text_lang], nl)
        dirty = True
        added += 1
    if dirty:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(content)

print("tables:", len(tables), "keys added:", added)
print("RESULT:", "PASS" if added == len(KEYS) * len(tables) else "PARTIAL/CHECK")
