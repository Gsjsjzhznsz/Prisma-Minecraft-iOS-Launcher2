#!/usr/bin/env python3
# ame375_ship.py -- Task375 fluent-ui v2.4.0 三方对拍重打包
# 沿用 ame348_ship 管线口径：src/manifest/index/zip 四方一致（version + sha256 + size）。
# v2.4.0 = 两态开关（开=NavigationView 全维度换装+色板跟随系统明暗，关=恢复默认）。
import hashlib
import io
import json
import os
import zipfile

src_dir = "plugin-repo/src/fluent-ui"
man_path = os.path.join(src_dir, "manifest.json")
man = json.load(open(man_path, encoding="utf-8"))
man["version"] = "2.4.0"
man["description"] = ("Fluent 2 两态开关：开=NavigationView 全维度换装（结构/排版/形状/字阶/色板），"
                      "色板跟随系统明暗；关=恢复默认主题")
if "settings.read" not in man["permissions"]:
    man["permissions"] = sorted(set(man["permissions"] + ["settings.read"]))
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
fe["version"] = "2.4.0"
fe["summary"] = "Fluent 2 两态开关：开=全维度换装+色板跟随系统明暗，关=恢复默认主题"
fe["size"] = len(zdata)
fe["sha256"] = zsha
idx["updated"] = "2026-11-01"
with io.open(idx_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(idx, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("index.json: fluent-ui -> 2.4.0 (sha/size synced)")

# 三方对拍自证
man2 = json.load(open(man_path, encoding="utf-8"))
idx2 = json.load(open(idx_path, encoding="utf-8"))
fe2 = next(p for p in idx2["plugins"] if p["id"] == "fluent-ui")
zd2 = open(zpath, "rb").read()
assert man2["version"] == fe2["version"] == "2.4.0"
assert fe2["sha256"] == hashlib.sha256(zd2).hexdigest()
assert fe2["size"] == len(zd2)
assert "settings.read" in man2["permissions"]
print("ame375_ship: OK")
