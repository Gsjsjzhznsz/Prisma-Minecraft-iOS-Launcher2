#!/usr/bin/env python3
# Task322 selfcheck：四问题根修防回退门
# ①game/ 分居层退役不复活（写入点禁 versions/%@/game；识别/重指匹配白名单）
# ②plugins 旧位符号链接退役不复活（禁 createSymbolicLinkAtPath:legacyPlugins）
# ③JIT 深链 bundle-id 单一口径（stikjit 等深链禁内联 NSBundle.mainBundle.bundleIdentifier）
# ④main.m flatten 链在场（init_flattenIsolatedGameDirs 定义 + main() 调用）
import re
import sys
import glob
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")
fails = []

def read(rel):
    with open(os.path.join(NAT, rel), "r", encoding="utf-8", errors="replace") as f:
        return f.read()

# ---------- ① game/ 分居层退役：写入点禁令 ----------
WRITE_PAT = re.compile(r'gameDir"\]\s*=\s*\[NSString\s+stringWithFormat:@"versions/%@/game"')
ALLOW_WRITE = set()  # 写入点零豁免：任何 gameDir 赋值到 /game 都是回退
# 识别/迁移方向匹配的白名单（字符串比较/嗅探兜底/重指判定/legacy 源）
ALLOW_FILES = {
    "ModService.m",              # sniff 兜底 + F2 推断兜底 + Task322 重指匹配
    "ProfileSettingsViewController.m",  # 三态识别兜底 + legacyRelative 迁移源
    "main.m",                    # flatten 日志字面量
}
for path in sorted(glob.glob(os.path.join(NAT, "*.m"))):
    rel = os.path.basename(path)
    text = read(rel)
    for m in WRITE_PAT.finditer(text):
        if rel in ALLOW_FILES and rel != "ModService.m":
            continue  # ProfileSettings legacy 源/main.m 日志白名单
        if rel == "ModService.m":
            # 仅放行三处识别/匹配上下文（嗅探数组兜底、F2 推断兜底、重指判定）
            ctx = text[max(0, m.start()-120):m.end()+120]
            if ("ame271_rel" in ctx or "ame322_gd" in ctx or
                    text[max(0, m.start()-60):m.start()].rstrip().endswith("in @[")):
                continue
        fails.append("%s: gameDir write to versions/%%@/game (game-subdir retired) @char %d" % (rel, m.start()))

# ---------- ② plugins 旧位符号链接退役不复活 ----------
mainm = read("main.m")
if "createSymbolicLinkAtPath:legacyPluginsLink" in mainm or "createSymbolicLinkAtPath:legacyPlugins " in mainm:
    fails.append("main.m: legacy root plugins symlink creation resurrected")
if "Task322: legacy root plugins symlink retired" not in mainm:
    fails.append("main.m: plugins symlink retirement anchor missing")
if "moved into Prisma2/plugins (legacy symlink left in place)" in mainm:
    fails.append("main.m: plugins migration leaves legacy symlink again")

# ---------- ③ 深链 bundle-id 单一口径 ----------
DEEP_PAT = re.compile(r'(stikjit://|apple-magnifier://enable-jit\?bundle-id|stosdebug://enableJIT\?bundleId|launch_app/)')
BUNDLE_PAT = re.compile(r'NSBundle\.mainBundle\.bundleIdentifier')
for path in sorted(glob.glob(os.path.join(NAT, "*.m"))):
    rel = os.path.basename(path)
    if rel in ("utils.m",):
        continue
    text = read(rel)
    for line_no, line in enumerate(text.splitlines(), 1):
        if DEEP_PAT.search(line) and BUNDLE_PAT.search(line):
            fails.append("%s:%d: inline NSBundle bundleIdentifier in deep-link line (use ame322_stikjitBundleId)" % (rel, line_no))

utils_h = read("utils.h")
if "ame322_stikjitBundleId" not in utils_h:
    fails.append("utils.h: ame322_stikjitBundleId declaration missing")

# ---------- ④ main.m flatten 链在场 ----------
if "void init_flattenIsolatedGameDirs() {" not in mainm:
    fails.append("main.m: init_flattenIsolatedGameDirs definition missing")
if "init_flattenIsolatedGameDirs(); // Task322" not in mainm:
    fails.append("main.m: init_flattenIsolatedGameDirs call site missing")

if fails:
    print("ame322_selfcheck: %d FAILURE(S)" % len(fails))
    for f in fails:
        print("  FAIL " + f)
    sys.exit(1)
print("ame322_selfcheck: ALL PASS (game-retire / plugins-link-retire / deeplink-bundleid / flatten-chain)")
