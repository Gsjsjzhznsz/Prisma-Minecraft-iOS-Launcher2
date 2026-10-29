#!/usr/bin/env python3
# ame348_ship.py -- Task348 交付脚本：① ame348.import.spine_absent 写入 54 表
# （zh 系全译，其余英文兜底，与 ame347 键同风格）；② fluent-ui v2.3.0 三方
# 对拍重打包（manifest version / zip main.js+manifest.json / index.json
# sha256+size+updated）。
import os, io, json, hashlib, zipfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

ZH_KEY = "备份包内没有启动器设置数据（导出该备份的旧版本未包含设置，非导入故障）——已保留当前设置，文件与实例已恢复"
ZH_HANT_KEY = "備份包內沒有啟動器設定資料（匯出該備份的舊版本未包含設定，非匯入故障）——已保留目前設定，檔案與實例已恢復"
EN_KEY = "No launcher settings data in this backup (the older version that exported it did not include settings -- not an import failure) -- current settings kept, files and instances restored"

# zh 系全译表（其余 51 表英文兜底）
ZH_DIRS = {"zh-Hans", "zh-Hans-CN", "zh-Hant", "zh-Hant-HK", "zh-CN", "zh-TW", "zh-HK", "zh"}

tables = sorted(d for d in os.listdir("Natives/resources") if d.endswith(".lproj"))
print(f"i18n: {len(tables)} tables")
missing_before = 0
patched = 0
for d in tables:
    p = os.path.join("Natives/resources", d, "Localizable.strings")
    with io.open(p, encoding="utf-8") as f:
        text = f.read()
    if "ame348.import.spine_absent" in text:
        continue
    lang = d[:-len(".lproj")]
    if lang in ZH_DIRS:
        val = ZH_HANT_KEY if "Hant" in lang or lang in ("zh-TW", "zh-HK", "zh-Hant-HK") else ZH_KEY
    else:
        val = EN_KEY
    anchor = '"ame347.import.spine_kept"'
    idx = text.find(anchor)
    if idx < 0:
        missing_before += 1
        print(f"  WARN {d}: ame347.import.spine_kept anchor not found, appending at EOF")
        line = f'"ame348.import.spine_absent" = "{val}";\n'
        with io.open(p, "w", encoding="utf-8", newline="") as f:
            f.write(text + ("\n" if not text.endswith("\n") else "") + line)
    else:
        eol = text.find("\n", idx)
        line = f'"ame348.import.spine_absent" = "{val}";\n'
        text = text[:eol + 1] + line + text[eol + 1:]
        with io.open(p, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    patched += 1
print(f"i18n: patched={patched} anchor-miss={missing_before}")

# 验证 54 表全落位
bad = [d for d in tables
       if "ame348.import.spine_absent" not in io.open(
           os.path.join("Natives/resources", d, "Localizable.strings"), encoding="utf-8").read()]
assert not bad, f"missing tables: {bad}"
print("i18n: all tables verified")

# ── fluent-ui v2.3.0 三方对拍重打包 ─────────────────────────────
src_dir = "plugin-repo/src/fluent-ui"
man_path = os.path.join(src_dir, "manifest.json")
man = json.load(open(man_path, encoding="utf-8"))
man["version"] = "2.3.0"
man["description"] = "Fluent 2 完整设计语言：NavigationView 左侧导航窗格结构 + 排版/形状/字阶/色板全维度令牌，装载即自动生效"
with io.open(man_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(man, f, ensure_ascii=False, indent=2)
    f.write("\n")

zpath = "plugin-repo/plugins/fluent-ui.zip"
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src_dir, "main.js"), "main.js")
    z.write(os.path.join(src_dir, "manifest.json"), "manifest.json")
zdata = open(zpath, "rb").read()
zsha = hashlib.sha256(zdata).hexdigest()
znames = sorted(zipfile.ZipFile(zpath).namelist())
assert znames == ["main.js", "manifest.json"], znames
print(f"zip: repacked {len(zdata)}B sha256={zsha[:16]}...")

idx_path = "plugin-repo/index.json"
idx = json.load(open(idx_path, encoding="utf-8"))
fe = next(p for p in idx["plugins"] if p["id"] == "fluent-ui")
fe["version"] = "2.3.0"
fe["summary"] = "Fluent 2 完整设计语言：NavigationView 左侧导航窗格结构 + 排版/形状/字阶/色板全维度令牌，装载即自动生效"
fe["size"] = len(zdata)
fe["sha256"] = zsha
idx["updated"] = "2026-10-30"
with io.open(idx_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(idx, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("index.json: fluent-ui -> 2.3.0 (sha/size synced)")
print("ame348_ship: OK")
