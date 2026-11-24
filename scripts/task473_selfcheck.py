#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task473 门：ZL2（ZalithLauncher2 上游 b6310dd）版本隔离系统移植执法。
断言面：
  A1 新模块在场（ZL2GamePath.h/.m + 单入口 API 全族）
  A2 消费方全路由（mods/saves/资源包/光影/备份/导出/详情页七面 resolver 体 = ZL2GamePath 调用）
  A3 启动链单入口（JavaLauncher Task473 块 + gameDirForProfile + 日志锚）
  A4 整合包强制隔离（ModpackImportService applyIsolationForModPackVersion）
  A5 详情页三态行接线（refreshIsolationRow 三态实值 + applyOverride 落盘）
  A6 设置页全局档组（ame473 组 + versionIsolation 注册默认 NO）
  A7 绕过执法（五服务 resolver 内禁现 POJAV_GAME_DIR 直拼返回——除 ResourcePack 回退）
  A8 退役符号零残留（注释豁免）
  A9 三态持久化格式（configPath prisma/version.config + ENABLE/DISABLE/FOLLOW_GLOBAL 字符串键）
  A10 Task463 折叠面零污染（fold ≥ 41）
  A11 BuildTag Task474 · 2026-11-24
  A12 括号平衡
selftest：负样本注入（启动链回退共享根直拼 / 整合包强制隔离摘除）必须翻红。
"""
import subprocess, sys, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []

def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')

def strip_comments(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', '', text, flags=re.S))

def check(name, cond, msg=""):
    if cond:
        print(f"[PASS] {name}")
    else:
        FAILS.append(name)
        print(f"[FAIL] {name} {msg}")

def brace_ok(text):
    """task240 同款字符状态机扫描器（strip_strings_comments 语义）。"""
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    d = 0
    for ch in "".join(out):
        if ch == '{': d += 1
        elif ch == '}': d -= 1
    return d == 0

# A1 新模块
try:
    h, m = read('Natives/ZL2GamePath.h'), read('Natives/ZL2GamePath.m')
    api = ['gameDirForVersion:', 'gameDirForProfile:', 'isIsolationForVersion:',
           'isolationTypeForVersion:', 'applyIsolationForModPackVersion:',
           'ZL2IsolationFollowGlobal', 'ZL2IsolationEnable', 'ZL2IsolationDisable']
    check("A1 新模块+单入口API全族", all(k in m for k in api) and 'versionPathForVersion' in h)
except FileNotFoundError:
    check("A1 新模块+单入口API全族", False, "ZL2GamePath.h/.m 缺失")
    m = h = ''

# A2 消费方七面全路由
routes = {
    'Natives/ModService.m': 'resolveAbsoluteGameDirForProfile',
    'Natives/WorldService.m': 'gameDirForProfile',
    'Natives/ShaderService.m': 'resolveAbsoluteGameDirForProfile',
    'Natives/ResourcePackService.m': 'existingResourcePacksFolderForProfile',
    'Natives/PLWorldBackupService.m': 'ame429_s1_gameDirForProfileName',
    'Natives/ModpackExportViewController.m': 'ame428_gameDirForSelectedProfile',
    'Natives/ZL2VersionDetailViewController.m': 'ameV13_resolvedGameDirForProfileName',
}
routed_all = True
for rel, sig in routes.items():
    code = strip_comments(read(rel))
    ok = '[ZL2GamePath gameDirForProfile:' in code
    if not ok:
        routed_all = False
        print(f"  - 未路由: {rel} ({sig})")
check("A2 消费方七面全路由", routed_all)

# A3 启动链
jl = read('Natives/JavaLauncher.m')
check("A3 启动链单入口+日志锚",
      '[ZL2GamePath gameDirForProfile:nil]' in jl
      and '[JavaLauncher] Task473: gameDir = %@ (isolation=%d vid=%@)' in jl
      and 'Task472: gameDir' not in jl)

# A4 整合包强制隔离
mp = strip_comments(read('Natives/ModpackImportService.m'))
check("A4 整合包导入强制隔离", '[ZL2GamePath applyIsolationForModPackVersion:versionId]' in mp)

# A5 详情页三态行
vp = strip_comments(read('Natives/ZL2VersionPages.m'))
check("A5 详情页三态行接线",
      '[ZL2GamePath isolationTypeForVersion:ame428_vid]' in vp
      and '[ZL2GamePath ame473_setIsolationType:(ZL2IsolationType)newOv forVersion:vid]' in vp)

# A6 全局档组+注册
sp = read('Natives/ZL2SettingPages.m')
pp = read('Natives/PLPreferences.m')
check("A6 全局档组+versionIsolation注册",
      'ame473_isoGroup' in sp and 'setPrefBool(@"versionIsolation", on)' in sp
      and '"versionIsolation": @NO' in pp)

# A7 绕过执法：resolver 体内禁 env 直拼（ResourcePack 回退豁免；ModService ame327/328/330 共享轴房务豁免）
bypass = []
for rel, sig in routes.items():
    code = strip_comments(read(rel))
    mbody = re.search(re.escape(sig) + r'.*?\n\}', code, re.S)
    if mbody and 'getenv("POJAV_GAME_DIR")' in mbody.group(0) and rel != 'Natives/ResourcePackService.m':
        bypass.append(rel)
check("A7 绕过执法（resolver 体零 env 直拼）", not bypass, str(bypass))

# A8 退役符号零残留（注释豁免，Natives 全域）
banned = ['ame428_effectiveIsolationForVid', 'ame428_effectiveCore', 'ame428_overrideForVid',
          'ame428_writeOverride', 'ame428_globalDefault', 'ame225_sniffedIsolationGameDirForProfile',
          'ame219_isolationStateForProfile', 'general.isolation_default']
res = {}
for f in list(ROOT.glob('Natives/**/*.m')) + list(ROOT.glob('Natives/**/*.h')):
    code = strip_comments(f.read_text(encoding='utf-8', errors='ignore'))
    for b in banned:
        if b in code:
            res.setdefault(b, []).append(str(f.relative_to(ROOT)))
check("A8 退役符号零残留", not res, str(res))

# A9 三态持久化格式
zm = strip_comments(m)
check("A9 三态持久化格式",
      'prisma' in zm and 'version.config' in zm
      and '@"ENABLE"' in zm and '@"DISABLE"' in zm and '@"FOLLOW_GLOBAL"' in zm
      and '"isolationType"' in zm)

# A10 折叠面（宽松 ≥41——Task472 重锚 41，Task473 +1 组 = 42 仍绿）
fold_sp = read('Natives/ZL2SettingPages.m')
fold = fold_sp.count('ame_addGroup:')
check("A10 Task463 折叠面零污染（≥41）", fold >= 41, f"实测 {fold}")

# A11 BuildTag
tag = read('Natives/BuildTag.h')
check("A11 BuildTag Task474 · 2026-11-24", 'ame415_buildTag = @"Task474 · 2026-11-24"' in tag)

# A12 括号
FILES = ['Natives/ZL2GamePath.h', 'Natives/ZL2GamePath.m', 'Natives/ModService.m',
         'Natives/WorldService.m', 'Natives/ResourcePackService.m', 'Natives/ShaderService.m',
         'Natives/PLWorldBackupService.m', 'Natives/ModpackExportViewController.m',
         'Natives/ZL2VersionDetailViewController.m', 'Natives/ZL2VersionPages.m',
         'Natives/ZL2SettingPages.m', 'Natives/PLPreferences.m', 'Natives/JavaLauncher.m']
bads = [f for f in FILES if not brace_ok(read(f))]
check("A12 括号平衡", not bads, str(bads))

print()
if FAILS:
    print(f"task473_selfcheck: {len(FAILS)} FAIL -> {FAILS}")
    sys.exit(1)
print("task473_selfcheck ALL GREEN（A1-A12）")

# ============ selftest：负样本注入必红 ============
if '--selftest' in sys.argv:
    import tempfile, shutil
    print("── task473 selftest ──")
    orig_jl = read('Natives/JavaLauncher.m')
    orig_mp = read('Natives/ModpackImportService.m')
    tmp = ROOT / 'Natives'
    try:
        # 负样本1：启动链回退共享根直拼（gameDirForProfile 摘除）
        bad1 = orig_jl.replace('[ZL2GamePath gameDirForProfile:nil]', '@(getenv("POJAV_GAME_DIR"))', 1)
        (tmp / 'JavaLauncher.m').write_text(bad1, encoding='utf-8')
        r1 = subprocess.run([sys.executable, str(Path(__file__).resolve())],
                            capture_output=True, text=True, cwd=str(ROOT))
        red1 = 'A3' in r1.stdout and 'FAIL' in r1.stdout
        # 负样本2：整合包强制隔离摘除
        bad2 = orig_mp.replace('[ZL2GamePath applyIsolationForModPackVersion:versionId];', '', 1)
        (tmp / 'ModpackImportService.m').write_text(bad2, encoding='utf-8')
        (tmp / 'JavaLauncher.m').write_text(orig_jl, encoding='utf-8')
        r2 = subprocess.run([sys.executable, str(Path(__file__).resolve())],
                            capture_output=True, text=True, cwd=str(ROOT))
        red2 = 'A4' in r2.stdout and 'FAIL' in r2.stdout
        print(f"负样本1 启动链回退直拼 翻红={red1}；负样本2 整合包隔离摘除 翻红={red2}")
        if red1 and red2:
            print("task473_selftest ALL GREEN（门活着）")
        else:
            print("task473_selftest FAIL（门死了）")
            sys.exit(1)
    finally:
        (tmp / 'JavaLauncher.m').write_text(orig_jl, encoding='utf-8')
        (tmp / 'ModpackImportService.m').write_text(orig_mp, encoding='utf-8')
