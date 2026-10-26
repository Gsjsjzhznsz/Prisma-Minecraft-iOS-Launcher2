#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task331 自检门：四线修复锚点 + 结构完整性断言。
线A=插件桥 JSExport 化 + 门面 storageSetValue 修正 + 双普查日志 + manifest 1.1.0；
线B=SurfaceVC 触点时刻自愈 v3（小窗首触即时武装 + 帧指纹权威闸）；
线C=ZL2M3Switch 拨动行程语义修复（按压按钮病灶）；
线D=JavaLauncher .minecraft 跟随现役实例（ZL2 版本隔离可见层收口）。
"""
import json
import os
import re
import sys

ROOT = "/home/z/my-project/repo-prisma2/Natives"
checks = []
failed = []


def check(name, path, pattern, count=1, rx=False):
    checks.append(name)
    try:
        src = open(path, encoding="utf-8").read()
    except OSError as e:
        failed.append(f"{name}: cannot read {path}: {e}")
        return
    hits = len(re.findall(pattern, src)) if rx else src.count(pattern)
    if hits < count:
        failed.append(f"{name}: expect >= {count} hit(s), got {hits} -- pattern={pattern[:70]}")


def absent(name, path, pattern, rx=False):
    checks.append(name)
    try:
        src = open(path, encoding="utf-8").read()
    except OSError as e:
        failed.append(f"{name}: cannot read {path}: {e}")
        return
    hits = len(re.findall(pattern, src)) if rx else src.count(pattern)
    if hits != 0:
        failed.append(f"{name}: expect 0 hit(s), got {hits} -- pattern={pattern[:70]}")


def balanced(path):
    checks.append(f"bracket-balance: {os.path.basename(path)}")
    src = open(path, encoding="utf-8").read()
    for op, cl in [("{", "}"), ("(", ")"), ("[", "]")]:
        if src.count(op) != src.count(cl):
            failed.append(f"bracket-balance: {os.path.basename(path)} {op}{cl} "
                          f"{src.count(op)} != {src.count(cl)}")


# ── 线A1：桥面 JSExport 化 ──────────────────────────────────────────
H = f"{ROOT}/AmePluginBridge.h"
check("A1 protocol declared", H, "@protocol AmePluginBridgeJSExport <JSExport>")
check("A1 interface adopts protocol", H,
      "@interface AmePluginBridge : NSObject <AmePluginBridgeJSExport>")
# 关键多段 selector 的 JSExport 声明（JS 名整形 = 去冒号拼接、首段后首字母大写）
for sel, jsname in [
    ("storageSet:(NSString *)key value:(id)value;", "storageSetValue"),
    ("writeGameFile:(NSString *)relPath content:(NSString *)content append:(BOOL)append;", "writeGameFileContentAppend"),
    ("fetch:(NSString *)urlString options:(NSDictionary *)opts callback:(JSValue *)cb;", "fetchOptionsCallback"),
    ("dialog:(NSDictionary *)spec callback:(JSValue *)cb;", "dialogCallback"),
    ("on:(NSString *)event handler:(JSValue *)cb;", "onHandler"),
    ("addLauncherRow:(NSDictionary *)spec handler:(JSValue *)cb;", "addLauncherRowHandler"),
    ("setPref:(NSString *)key value:(id)value;", "setPrefValue"),
]:
    check(f"A1 export {jsname}", H, sel)

# 空值限定镜像（NS_ASSUME_NONNULL 区：拒绝返 nil 的方法协议侧必须 nullable，
# 否则类采纳时 nullability conflict 编译报错）
for nullable_sel in [
    "- (nullable id)getPref:(NSString *)key;",
    "- (nullable NSDictionary *)getRenderer;",
    "- (nullable NSArray *)getProfiles;",
    "- (nullable id)storageGet:(NSString *)key;",
    "- (nullable NSArray<NSDictionary *> *)listGameFiles:(NSString *)relPath;",
    "- (nullable NSString *)readGameFile:(NSString *)relPath;",
]:
    check(f"A1 nullability mirror {nullable_sel.split('(')[1].split(':')[0]}", H, nullable_sel)

# 协议内每个 selector 在 .m 有实现（取 selector 首段与完整参数脊）
M = f"{ROOT}/AmePluginBridge.m"
proto = re.search(r"@protocol AmePluginBridgeJSExport.*?@end", open(H, encoding="utf-8").read(), re.S)
checks.append("A1 protocol block extractable")
if not proto:
    failed.append("A1: protocol block not found")
else:
    sels = re.findall(r"^- \([^)]+\)\s*(.+?);",
                      proto.group(0), re.M)
    bridge_src = open(M, encoding="utf-8").read()
    checks.append(f"A1 exported selector count = {len(sels)}")
    if len(sels) < 24:
        failed.append(f"A1: expected >= 24 exported selectors, got {len(sels)}")
    for s in sels:
        spine = re.sub(r"\s+", " ", s).strip()
        first = spine.split(":")[0]
        # 实现判定：selector 脊（压缩空白后）出现于实现文件
        if spine not in re.sub(r"\s+", " ", bridge_src):
            failed.append(f"A1: selector not implemented in bridge: {spine}")

# ── 线A2：门面名实修正 ──────────────────────────────────────────────
R = f"{ROOT}/AmePluginRuntime.m"
check("A2 facade calls storageSetValue", R, 'raw.storageSetValue(String(k),v)')
absent("A2 old raw.storageSet( two-arg call gone", R, r"raw\.storageSet\(String\(k\),v\)", rx=True)
# ★ Task332 演进指针：load census 升级为 facade/raw 双面（Task332 行替代 Task331 行）
check("A2 load census line (Task332 dual-face re-anchor)", R, "Task332 load census")
check("A2 builtin census line", R, "Task331 builtin census")
check("A2 bundle-missing ERROR line", R, "Task331 ERROR: bundle builtin-plugins missing main.js")

# ── 线A3：内置件 manifest 1.1.0 ─────────────────────────────────────
# ★ Task333 重锚：四件演示件迁 plugin-repo/src（bundle 只留 plugin-survey）；
#   theme-sunset 1.2.0（+ui.dialog 根治权限拒绝刷屏）
PLUG = f"{ROOT}/../plugin-repo/src"
for pid, ver, perms in [("launch-counter", "1.1.0", 4), ("modrinth-hot", "1.1.0", 3),
                        ("renderer-quickswitch", "1.1.0", 5), ("theme-sunset", "1.2.0", 4)]:
    p = f"{PLUG}/{pid}/manifest.json"
    checks.append(f"A3 manifest {pid}")
    try:
        d = json.load(open(p, encoding="utf-8"))
    except Exception as e:
        failed.append(f"A3: {pid} manifest unreadable: {e}")
        continue
    if d.get("version") != ver:
        failed.append(f"A3: {pid} version={d.get('version')} expect {ver}")
    if d.get("id") != pid:
        failed.append(f"A3: {pid} id mismatch")
    if len(d.get("permissions", [])) != perms:
        failed.append(f"A3: {pid} permissions count changed")
    if d.get("entry") != "main.js":
        failed.append(f"A3: {pid} entry changed")
    checks.append(f"A3 bundle main.js present: {pid}")
    if not os.path.isfile(f"{PLUG}/{pid}/main.js"):
        failed.append(f"A3: {pid} bundle main.js missing")

# ── 线B：触点时刻自愈 v3 ────────────────────────────────────────────
S = f"{ROOT}/SurfaceViewController.m"
check("B fingerprint ivar declared", S, "CGRect ame331_lastFactorFrame;")
check("B fingerprint written at rescale tail", S, "ame331_lastFactorFrame = self.touchView.frame;", count=3)
check("B touch-time engage branch", S, "Task331: touch-time scale-mode engage")
check("B fingerprint authority gate", S,
      "CGRectEqualToRect(self.touchView.frame, ame331_lastFactorFrame)")
check("B settle-aware split", S, "Task331: touch-time mailbox refresh on drifted frame")
absent("B old settle-guard hard return gone", S, r"if \(ame327_settleTimer\.isValid\) return;", rx=True)

# ── 线C：M3 开关拨动行程 ────────────────────────────────────────────
K = f"{ROOT}/ZL2M3Kit.m"
check("C true travel geometry", K, "CGFloat lead = checked ? 24.0 : 4.0;")
absent("C old centered-zero-travel gone", K, r"CGFloat lead = checked \? 14\.0 : 18\.0;", rx=True)

# ── 线D：.minecraft 跟随现役实例 ────────────────────────────────────
J = f"{ROOT}/JavaLauncher.m"
check("D active-instance re-point", J,
      "Task331: .minecraft re-pointed to active instance")
check("D create-if-missing branch", J,
      "Task331: .minecraft created -> active instance")
check("D instances/<id> axis guard", J,
      'stringByAppendingPathComponent:@"instances"]')
check("D Task319 real-dir discipline kept", J,
      "// 真实目录/文件：绝不覆盖用户数据（Task319 纪律原样）")

# ── 结构完整性 ──────────────────────────────────────────────────────
# （JavaLauncher.m 存量注释内 ASCII 括号差 -4（HEAD 同值），不入平衡门；
#   与家法 ame330 清单口径一致，仅查本轮触碰且历史上平衡的文件）
for p in [H, M, R, S, K]:
    balanced(p)
checks.append("bracket-balance: JavaLauncher.m (baseline -4 conserved)")
_jl = open(J, encoding="utf-8").read()
if _jl.count("(") - _jl.count(")") != -4:
    failed.append("bracket-balance: JavaLauncher.m delta changed (expect -4 baseline)")

# i18n 纪律：本轮零新增 localize 键（普查/锚点全为英文 NSLog）
for p in [R, S, K, J]:
    src = open(p, encoding="utf-8").read()
    keys = re.findall(r'localize\(@"([^"]+)"', src)
    for k in keys:
        if "ame331" in k:
            failed.append(f"i18n: unexpected new ame331 localize key {k} in {os.path.basename(p)}")
checks.append("i18n: zero new ame331 keys")

print(f"ame331_selfcheck: {len(checks)} assertions, {len(failed)} failed")
for f in failed:
    print(f"  FAIL {f}")
sys.exit(1 if failed else 0)
