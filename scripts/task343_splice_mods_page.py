#!/usr/bin/env python3
# task343_splice_mods_page.py -- ZL2VersionModsPage 全量重写拼接（Task343 线B）
# 1) 摘除旧段落（#pragma mark - ② 模组管理 → ③ 存档管理 之前）
# 2) 注入新段落（ModService/ModUpdateService 全量接线版）
# 3) 顶部 imports 补充
import io, os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

MAIN = "Natives/ZL2VersionPages.m"
NEW = "scripts/task343_mods_page_new.swiftx"

with io.open(MAIN, encoding="utf-8", newline="") as f:
    lines = f.readlines()
with io.open(NEW, encoding="utf-8", newline="") as f:
    new_section = f.read()

start = end = None
for i, ln in enumerate(lines):
    if start is None and "pragma mark - ② 模组管理" in ln:
        start = i
    elif start is not None and "pragma mark - ③ 存档管理" in ln:
        end = i
        break
assert start is not None and end is not None, "section markers not found"
# 旧段落必须含实现与 @end 收尾
old_body = "".join(lines[start:end])
assert "@implementation ZL2VersionModsPage" in old_body
assert old_body.count("@end") >= 1
print(f"old section: lines {start+1}..{end} ({end-start} lines)")

replacement = new_section
if not replacement.endswith("\n"):
    replacement += "\n"
replacement += "\n"
new_lines = lines[:start] + [replacement] + lines[end:]

# imports 补充（幂等：已有则跳过；行级插入到 ModpackExportService.h 之后）
body_lines = new_lines
already = any("ModUpdateService.h" in ln for ln in body_lines)
if not already:
    inject = [
        '#import "ModService.h"                 // ★ Task343：模组页数据层（scan/toggle/delete/metadata/隔离口径）\n',
        '#import "ModUpdateService.h"          // ★ Task343：检查更新全流程（双源限流）\n',
        '#import "PLDownloadClient.h"          // ★ Task343：更新下载（镜像候选 + SHA1 校验）\n',
        '#import "PLMirrorCenter.h"\n',
        '#import "ZL2DownloadViewController.h" // ★ Task343：空态「去下载」模组轨直达\n',
        '#import <CommonCrypto/CommonDigest.h> // ★ Task343：流式 SHA1（Modrinth 反查依赖）\n',
    ]
    out2, done = [], False
    for ln in body_lines:
        out2.append(ln)
        if not done and ln.startswith('#import "ModpackExportService.h"'):
            out2.extend(inject)
            done = True
    assert done, "import anchor line not found"
    body_lines = out2
    print("imports injected")
else:
    print("imports already present")

with io.open(MAIN, "w", encoding="utf-8", newline="") as f:
    f.write("".join(body_lines))

# 终检
with io.open(MAIN, encoding="utf-8", newline="") as f:
    final = f.read()
for sym in ("ZL2V13ModUpdateTask", "ameV13_checkForUpdates", "ameV13_performUpdatesWithResults",
            "ameV13_batchDelete", "ameV13_profileLoaderForDisplay", "ZL2V13ModSHA1ForFile"):
    assert sym in final, f"missing {sym}"
assert final.count("@implementation ZL2VersionModsPage") == 1
print(f"spliced: {len(lines)} -> {final.count(chr(10))} lines")
