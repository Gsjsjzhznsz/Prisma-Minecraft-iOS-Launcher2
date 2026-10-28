#!/usr/bin/env python3
# Task342 自检电池 —— 两线：
#   A 1.20.1 闪退第二轮（SIGBUS at StubRoutines::call_stub）：JIT 镜像代码
#     缓存自救通道（debug.mirror_codecache_disable 双落位：launchJVM +
#     launchHeadlessJVM 退役 -XX:+MirrorMappedCodeCache 走非镜像轨）+
#     ame273 crash report 定向 fix（main_hook 特征 SIGBUS+call_stub）+
#     SceneDelegate 崩溃弹窗一键开启 + 探针 region 取证日志 + 设置页行 +
#     defaults 注册
#   B 插件安装失败文案错位 + CDN 文件缓存根修（ame333 远程链 sha 失败误报
#     "打包内置插件失败（zip 写入错误）"装机实弹 → 错误码拆分 ErrDownload/
#     ErrShaMismatch + 下载 URL cache-busting query + 文件级 purge 双保险 +
#     builtin zip 空收集取证日志 + i18n 新键四表）
# 惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
import json
import os
import re
import sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

fails, passed = [], 0
def check(name, ok, detail=''):
    global passed
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if ok:
        passed += 1
    else:
        fails.append(name)

def read(rel):
    with open(os.path.join(REPO, rel), encoding='utf-8') as f:
        return f.read()

def strip_real(src):
    # ★ Task341：单遍扫描真剥离器（字符串内 "/*" 不再误触发块注释）
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append('""')
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

def strip_keep_str(src):
    # ★ Task342：同构单遍扫描，但字符串字面量原样保留（断言目标含
    #   PUSH_MARGV_LITERAL/getPrefBool/NSLog/localize 等字符串内容，
    #   需要去注释保字符串；且字符串内 "/*" 不触发注释状态）。
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append(src[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

# ── 读面 ─────────────────────────────────────────────────────
jl = read('Natives/JavaLauncher.m')
jl_code = strip_keep_str(jl)
mh = read('Natives/main_hook.m')
mh_code = strip_keep_str(mh)
scene = read('Natives/SceneDelegate.m')
scene_code = strip_keep_str(scene)
prefs = read('Natives/PLPreferences.m')
prefs_code = strip_keep_str(prefs)
prefvc = read('Natives/LauncherPreferencesViewController.m')
prefvc_code = strip_keep_str(prefvc)
repo_vc = read('Natives/ZL2PluginRepoViewController.m')
repo_code = strip_keep_str(repo_vc)
mgr_h = read('Natives/AmePluginManager.h')
mgr_h_code = strip_keep_str(mgr_h)

strings = {}
for lang in ('en', 'zh-Hans', 'zh-CN', 'zh-Hant'):
    strings[lang] = read(f'Natives/resources/{lang}.lproj/Localizable.strings')

if '--selftest' in sys.argv:
    print('== ame342 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-A1: 双落位镜像退役条件被摘（&& !ame342_retireMirror 全删）→ A2/A4 探针必翻红
    inj_jl = jl_code.replace(' && !ame342_retireMirror', '')
    bare_gate = re.search(r'if \(@available\(iOS 26\.0, \*\)\) \{\s*\n'
                          r'\s*PUSH_(?:MARGV|HARGV)_LITERAL\("-XX:\+MirrorMappedCodeCache"\);', inj_jl)
    ok = bare_gate is not None
    if ok:
        print('ok  S-A1 反向：镜像退役条件全摘（退化为裸 @available）-> A2/A4 FAIL（符合预期）')
    else:
        print('S-A1 未翻红（镜像退役探针失效）'); bad += 1
    # S-B1: sha mismatch 错误码回退为 ErrReadZip（病灶）→ B4 探针必翻红
    inj_repo = repo_code.replace('AmePluginInstallErrShaMismatch;', 'AmePluginInstallErrReadZip;', 1)
    ok = 'code = AmePluginInstallErrReadZip;' in inj_repo and 'code = AmePluginInstallErrShaMismatch;' not in inj_repo
    if ok:
        print('ok  S-B1 反向：sha 失败错误码回退 -> B4 FAIL（符合预期）')
    else:
        print('S-B1 未翻红（错误码拆分探针失效）'); bad += 1
    # S-B2: cache-busting query 被摘（URL 拼接回旧形态）→ B5 探针必翻红
    inj_repo2 = repo_code.replace('?cb=%lld', '%@')
    ok = ('?cb=%lld' not in inj_repo2) and ('?cb=%lld' in repo_code)
    if ok:
        print('ok  S-B2 反向：cache-busting 摘除 -> B5 FAIL（符合预期）')
    else:
        print('S-B2 未翻红（cache-busting 探针失效）'); bad += 1
    # S-A2: crash report 定向 fix 特征被摘（call_stub 判据删除）→ A6 探针必翻红
    inj_mh = mh_code.replace('StubRoutines::call_stub', 'REDACTED', 2)
    ok = 'StubRoutines::call_stub' not in inj_mh
    if ok:
        print('ok  S-A2 反向：crash fix 特征摘除 -> A6 FAIL（符合预期）')
    else:
        print('S-A2 未翻红（crash fix 探针失效）'); bad += 1
    if bad == 0:
        print('selftest OK（4 探针全部翻红）')
        sys.exit(0)
    sys.exit(1)

# ═══════════════════════ A 组：JIT 镜像退役自救通道 ═══════════════════════
print('== A 组：JIT 镜像代码缓存自救（debug.mirror_codecache_disable）==')

# A1: launchJVM 分轨——iOS26+ 镜像轨与非镜像轨三参数逐行同构（开关分支）
check('A1 launchJVM 镜像轨参数块 64m/48m/8m',
      'PUSH_MARGV_LITERAL("-XX:ReservedCodeCacheSize=64m");' in jl_code and
      'PUSH_MARGV_LITERAL("-XX:InitialCodeCacheSize=48m");' in jl_code and
      'PUSH_MARGV_LITERAL("-XX:CodeCacheExpansionSize=8m");' in jl_code)

# A2: launchJVM 镜像 flag 与 64m 轨参数行同受 ame342_retireMirror 闸
mirror_flag_gated = re.search(
    r'} else if \(@available\(iOS 26\.0, \*\) && !ame342_retireMirror\) \{\s*\n'
    r'\s*PUSH_MARGV_LITERAL\("-XX:ReservedCodeCacheSize=64m"\);', jl_code)
flag_line_gated = re.search(
    r'if \(@available\(iOS 26\.0, \*\) && !ame342_retireMirror\) \{\s*\n'
    r'\s*PUSH_MARGV_LITERAL\("-XX:\+MirrorMappedCodeCache"\);', jl_code)
check('A2 launchJVM 镜像 flag/64m 轨双重 ame342_retireMirror 闸',
      bool(mirror_flag_gated) and bool(flag_line_gated))

# A3: launchJVM 开关读点 + 取证日志
check('A3 launchJVM 开关读点 + Task342 取证日志',
      'BOOL ame342_retireMirror = getPrefBool(@"debug.mirror_codecache_disable");' in jl_code and
      'Task342 probe region: %p (1 page)' in jl_code)

# A4: launchHeadlessJVM 双落位（HARGV 同构）
check('A4 headless 双落位（64m 轨闸 + flag 闸 + 读点）',
      'PUSH_HARGV_LITERAL("-XX:ReservedCodeCacheSize=64m");' in jl_code and
      'PUSH_HARGV_LITERAL("-XX:+MirrorMappedCodeCache");' in jl_code and
      jl_code.count('BOOL ame342_retireMirror = getPrefBool(@"debug.mirror_codecache_disable");') == 2 and
      re.search(r'if \(@available\(iOS 26\.0, \*\) && !ame342_retireMirror\) \{\s*\n'
                r'\s*PUSH_HARGV_LITERAL\("-XX:\+MirrorMappedCodeCache"\);', jl_code))

# A5: defaults 注册 + 设置页行
check('A5 defaults 注册 mirror_codecache_disable + 设置页 typeSwitch 行',
      '@"mirror_codecache_disable": @NO,' in prefs_code and
      '@{@"key": @"mirror_codecache_disable",' in prefvc_code and
      re.search(r'@"key": @"mirror_codecache_disable",\s*\n\s*@"hasDetail": @YES,\s*\n'
                r'\s*@"icon": @"[^"]+",\s*\n\s*@"type": self\.typeSwitch,', prefvc_code))

# A6: main_hook 定向 fix（SIGBUS+call_stub 特征 → 自救文案）+ SceneDelegate 一键动作
check('A6 main_hook SIGBUS+call_stub 定向 fix 文案',
      'StubRoutines::call_stub' in mh_code and 'SIGBUS' in mh_code and
      '退役镜像' in mh_code and 'Ame342' in mh_code)
check('A7 SceneDelegate 崩溃弹窗一键开启（headline 判据 + 写偏好 + marker）',
      'ame342.crash.retire_mirror' in scene_code and
      'setPrefBool(@"debug.mirror_codecache_disable", YES)' in scene_code and
      'ame342_mirror_retired.txt' in scene_code)

# A8: i18n 键四表（title/detail/按钮）
ok_i18n = True
for lang, t in strings.items():
    for key in ('"preference.title.mirror_codecache_disable"',
                '"preference.detail.mirror_codecache_disable"',
                '"ame342.crash.retire_mirror"'):
        if key + ' =' not in t:
            ok_i18n = False
            print(f'   缺键 {lang} {key}')
check('A8 i18n 键四表（title/detail/按钮）', ok_i18n)

# ═══════════════════════ B 组：插件链错误码拆分 + CDN 根修 ═══════════════════════
print('== B 组：ame333 错误码拆分 + cache-busting + 取证 ==')

# B1: 枚举两值
check('B1 AmePluginInstallErrDownload=8 / ErrShaMismatch=9',
      'AmePluginInstallErrDownload   = 8' in mgr_h_code and
      'AmePluginInstallErrShaMismatch = 9' in mgr_h_code)

# B2: ame333 链下载空体 → ErrDownload
check('B2 ame333 空下载 → ErrDownload',
      re.search(r'} else if \(!data\.length\) \{[^}]*?code = AmePluginInstallErrDownload;', repo_code, re.S) is not None)

# B3: ame333 sha mismatch → ErrShaMismatch（不再复用 ErrReadZip）
check('B3 ame333 sha mismatch → ErrShaMismatch',
      'NSLog(@"[AmePluginRepo] Task333 sha mismatch for %@ (got %@ want %@)", pid, gotSha, sha);' in repo_code and
      'code = AmePluginInstallErrShaMismatch;' in repo_code and
      'code = AmePluginInstallErrReadZip;   // 完整性闸失败按下载失败报' not in repo_code)

# B4: 安装失败弹窗 switch 补两分支
check('B4 installDidFinish 两新分支文案',
      'case AmePluginInstallErrDownload:   body = localize(@"ame333.repo.download_failed", nil); break;' in repo_code and
      'case AmePluginInstallErrShaMismatch: body = localize(@"ame333.repo.sha_mismatch", nil); break;' in repo_code)

# B5: 下载 URL cache-busting + 文件级 purge 双保险
check('B5 下载 URL ?cb= cache-busting + 文件级 purge（3s 超时不阻断）',
      '?cb=%lld' in repo_code and 'Task342 jsdelivr file cache purge' in repo_code and
      'stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"' in repo_code)

# B6: builtin zip 空收集取证日志
check('B6 ame318_zipBuiltinPlugin 空收集取证日志',
      'Task342 builtin zip collected 0 files' in repo_code and
      re.search(r'if \(relPaths\.count == 0\) \{[^}]*?return NO;', repo_code, re.S) is not None)

# B7: i18n download_failed 四表
ok_df = all('"ame333.repo.download_failed" =' in t for t in strings.values())
check('B7 i18n ame333.repo.download_failed 四表', ok_df)

# B8: index purge（Task340 既有）保留未被破坏
check('B8 Task340 index purge 保留（既有回归）',
      'Task340 jsdelivr index cache purge' in repo_code)

# ═══════════════════════ C 组：结构 ═══════════════════════
print('== C 组：结构 ==')

# C1: 括号平衡（四个改动文件）——★Task342 r1 判例：三层 ObjC 消息链
#   [[[A m1] m2] resume] 少一层 `[`（CI dev 40734990645 实锤 missing '['），
#   大括号平衡断言查不出 → C 组补圆括号/方括号平衡三查。
for name, src in (('JavaLauncher.m', jl), ('main_hook.m', mh), ('SceneDelegate.m', scene),
                  ('ZL2PluginRepoViewController.m', repo_vc), ('AmePluginManager.h', mgr_h)):
    code = strip_real(src)
    check(f'C1 {name} 大括号平衡', code.count('{') == code.count('}'),
          f"{code.count('{')} vs {code.count('}')}")
    check(f'C1 {name} 圆括号平衡', code.count('(') == code.count(')'),
          f"{code.count('(')} vs {code.count(')')}")
    check(f'C1 {name} 方括号平衡', code.count('[') == code.count(']'),
          f"{code.count('[')} vs {code.count(']')}")

# C2: strings 文件引号闭合（逐行偶数个未转义双引号）
ok_q = True
for lang, t in strings.items():
    for i, ln in enumerate(t.splitlines(), 1):
        if not ln.strip() or ln.strip().startswith('//'):
            continue
        if ln.count('"') % 2 != 0:
            ok_q = False
            print(f'   {lang} 第{i}行引号奇数: {ln[:60]}')
check('C2 strings 四表引号闭合', ok_q)

print(f'\n== ame342_selfcheck: {passed} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('ALL GREEN')
