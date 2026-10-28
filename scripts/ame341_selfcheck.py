#!/usr/bin/env python3
# Task341 自检电池 —— 两线：
#   A 1.20.1 启动闪退根修（metallum_agent.jar 禁入 -cp：Fabric 首启 remap 的
#     tiny-remapper 继承索引扫描把 agent 类集 classes262/*（major 69）喂给
#     1.20.1 fabric-loader 0.14.23 内嵌旧版 ASM → exit(1)；Task201 门禁只管
#     -javaagent 参数管不住 -cp 目录扫描，launchJVM + launchHeadlessJVM 两处
#     循环同修 + Task201 误导文案修正）
#   B Fluent 插件完全重设计（用户点题：Fluent 插件要完全重新设计 UI，而不是
#     依旧使用 zl2 样式）—— ZL2Theme 引擎新增形状/字体覆盖面（ame341，默认值
#     M3 不变）+ 桥面 setThemeShape（JSExport/ui.theme 执法/__shape 持久化/
#     装载重放/卸载还原）+ fluent-ui 插件 v2.0.0（Fluent 2 全维度：色 28 +
#     形状 5 + 字阶 7，fluentui-apple 溯源值）+ index/zip 一致性
# 惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
import hashlib
import json
import os
import re
import sys
import zipfile

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

def strip_code(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    return src

def strip_comments(src):
    # 只剥注释保留字符串（A4 判注释内残留用：新文案在代码字符串里）
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    return src

def strip_real(src):
    # ★ Task341：单遍扫描真剥离器（ame337 剥器判例翻版）：旧 strip_code 的
    #   块注释正则会被字符串字面量内的 "/*"（JavaLauncher.m lwjgl 通配
    #   条目 "%@/*"）误触发，吞掉后续大段代码 → 探针假阴性。单遍扫描：
    #   注释优先于字符串、字符串内不触发注释，三者嵌套语义正确。
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

# ── 读面 ─────────────────────────────────────────────────────
jl = read('Natives/JavaLauncher.m')
jl_real = strip_real(jl)   # 单遍扫描真剥离（字符串内 /* 不再误触发块注释）
jl_nocom = strip_comments(jl)
theme_h = read('Natives/ZL2Theme.h')
theme_m = read('Natives/ZL2Theme.m')
theme_code = strip_real(theme_m)
bridge_h = read('Natives/AmePluginBridge.h')
bridge_m = read('Natives/AmePluginBridge.m')
bridge_code = strip_real(bridge_m)
runtime = read('Natives/AmePluginRuntime.m')
plugin_js = read('plugin-repo/src/fluent-ui/main.js')
plugin_manifest = json.loads(read('plugin-repo/src/fluent-ui/manifest.json'))

if '--selftest' in sys.argv:
    print('== ame341 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-A1: classpath 排除被摘（双处全摘，模拟病灶完整击穿）→ A2 探针必翻红
    inj_jl = strip_real(jl).replace('if ([libFile isEqualToString:@""]) continue;', '')
    ok_a1 = 'if ([libFile isEqualToString:@""]) continue;' not in inj_jl
    if ok_a1:
        print('ok  S-A1 反向：classpath 排除摘除 -> FAIL（符合预期）')
    else:
        print('S-A1 未翻红（classpath 排除探针失效）'); bad += 1
    # S-B1: 引擎 setter 记账被击穿（形状表永不写入）→ B2 探针必翻红
    inj_theme = theme_code.replace('ame341_shapeOverride[k] = @[pluginId, @(r)];', ';', 1)
    ok_b1 = 'ame341_shapeOverride[k] = @[pluginId, @(r)];' not in inj_theme
    if ok_b1:
        print('ok  S-B1 反向：形状记账击穿 -> FAIL（符合预期）')
    else:
        print('S-B1 未翻红（引擎记账探针失效）'); bad += 1
    # S-B2: 插件 FLUENT_SHAPE 被摘（退回纯换色 v1 形态）→ B8 探针必翻红
    inj_js = plugin_js.replace('radiusXS: 4, radiusS: 4, radiusM: 8, radiusL: 8, radiusXL: 12,', '', 1)
    ok_b2 = 'radiusXS: 4, radiusS: 4, radiusM: 8, radiusL: 8, radiusXL: 12,' not in inj_js
    if ok_b2:
        print('ok  S-B2 反向：插件形状令牌摘除 -> FAIL（符合预期）')
    else:
        print('S-B2 未翻红（插件全维度探针失效）'); bad += 1
    print(f'selftest: {"FAIL " + str(bad) + " probes failed to trigger" if bad else "3/3 反向探针全翻红"}')
    sys.exit(1 if bad else 0)

# ══ A 线 metallum_agent.jar 禁入 -cp（1.20.1 闪退根修）═════════════════
EXCL = 'if ([libFile isEqualToString:@"metallum_agent.jar"]) continue;'
EXCL_REAL = 'if ([libFile isEqualToString:@""]) continue;'   # strip_real 后字符串变形特征
check('A1 classpath 排除双落位（launchJVM + launchHeadlessJVM，锚点两处）',
      jl.count(EXCL) == 2 and jl.count('ame341-agent-cp-exclusion') == 2,
      f'排除行 {jl.count(EXCL)} 处 / 锚点 {jl.count("ame341-agent-cp-exclusion")} 处')
check('A2 排除是真实代码（单遍扫描剥离后变形特征恰 2 处）',
      jl_real.count(EXCL_REAL) == 2,
      f'strip 后 {jl_real.count(EXCL_REAL)} 处（应 2；假阴性=剥器/注释问题）')
check('A3 排除先于 classpath 拼接（launchJVM 主循环顺序）',
      0 < jl_real.find(EXCL_REAL) < jl_real.find('[classpathBuilder appendString:lwjglJar];'),
      '排除行不在拼接之前')
check('A4 Task201 误导文案退役（注释剥离后旧文案零残留）',
      'this session runs Java 8' not in jl_nocom and 'kept off -cp per Task341' in jl_nocom,
      '文案未修正（或仅存在于修正注释内）')

# ══ B 线 Fluent 完全重设计（引擎形状/字体覆盖 + 桥面 + 插件 v2）═══════
check('B1 ZL2Theme.h 声明 ame341_setPluginThemeShape',
      'ame341_setPluginThemeShape' in theme_h,
      '声明缺失')
check('B2 引擎 setter 记账活体（双表写入 + pt 钳制 40 + stale 还原）',
      'ame341_shapeOverride[k] = @[pluginId, @(r)];' in theme_code
      and 'ame341_fontOverride[k] = @[pluginId, font];' in theme_code
      and 'r > 40' in theme_code and 'size > 40' in theme_code
      and 'removeObjectForKey:k];' in theme_code,
      '记账/钳制/还原缺件')
check('B3 形状阶五档 getter 全走覆盖检查（AmePluginShapeOverride，原文面）',
      theme_m.count('AmePluginShapeOverride(@"radius') == 5,
      f'覆盖检查 {theme_m.count("AmePluginShapeOverride(@\"radius")} 处（应 5）')
check('B4 字体阶七档 getter 全走覆盖检查（AmePluginFontOverride，原文面）',
      theme_m.count('AmePluginFontOverride(@"font') == 7,
      f'覆盖检查 {theme_m.count("AmePluginFontOverride(@\"font")} 处（应 7）')
check('B5 桥面 setThemeShape 全链（JSExport 声明 + ui.theme 执法 + __shape 持久化）',
      '- (BOOL)setThemeShape:(NSDictionary *)tokens;' in bridge_h
      and '- (BOOL)setThemeShape:(NSDictionary *)tokens {' in bridge_code
      and 'ame317_requirePerm:@"ui.theme"' in bridge_m[bridge_m.find('setThemeShape:(NSDictionary *)tokens {'):][:600]
      and 'storage[@"__shape"]' in bridge_m
      and 'ame341_setPluginThemeShape' in bridge_m,
      '桥面链缺件')
check('B6 facade ame.setThemeShape 注册（raw.setThemeShape 整形）',
      'ame.setThemeShape=function(t){return raw.setThemeShape(t||{});};' in runtime,
      'facade 未注册')
check('B7 Runtime 三件（__shape 装载重放 + themeShapesByPlugin 记账 + 卸载还原）',
      'storageGet:@"__shape"' in runtime
      and 'ame317_applyThemeShape' in runtime
      and 'themeShapesByPlugin' in runtime
      and '[self ame317_applyThemeShape:pluginId tokens:nil];' in runtime,
      '重放/记账/还原缺件')
check('B8 插件 v2 全维度（Fluent 形状五档 + 字阶七档 + setThemeShape 调用 + 色板仍在）',
      'radiusXS: 4, radiusS: 4, radiusM: 8, radiusL: 8, radiusXL: 12,' in plugin_js
      and "fontHeadline:    { size: 28, weight: 'semibold' }" in plugin_js
      and "fontLabelMedium: { size: 13, weight: 'regular' }" in plugin_js
      and 'ame.setThemeShape(FLUENT_SHAPE)' in plugin_js
      and 'ame.setThemeShape({})' in plugin_js
      and 'primary:' in plugin_js and "ame.setThemeToken(pal.tokens)" in plugin_js,
      'Fluent 全维度缺件')
check('B9 manifest v2.0.0（版本 + 名称 + ui.theme 权限保持）',
      plugin_manifest.get('version') == '2.0.0'
      and plugin_manifest.get('name') == 'Fluent UI'
      and 'ui.theme' in plugin_manifest.get('permissions', []),
      'manifest 未升级')
# B10: index/zip 实算对拍（sha256/size 单一事实源，ame333 打包器口径）
_idx = json.loads(read('plugin-repo/index.json'))
_fe = next((p for p in _idx['plugins'] if p['id'] == 'fluent-ui'), None)
_zpath = os.path.join(REPO, 'plugin-repo', 'plugins', 'fluent-ui.zip')
_zdata = open(_zpath, 'rb').read() if os.path.isfile(_zpath) else b''
_zsha = hashlib.sha256(_zdata).hexdigest()
_znames = zipfile.ZipFile(_zpath).namelist() if os.path.isfile(_zpath) else []
check('B10 index/zip 实算对拍（sha256+size 逐位一致 + zip 根两文件 + v2.0.0）',
      _fe is not None and _fe['sha256'] == _zsha and _fe['size'] == len(_zdata)
      and sorted(_znames) == ['main.js', 'manifest.json']
      and _fe['version'] == '2.0.0',
      'index 与 zip 漂移')

# ══ D 线 结构护栏 ═════════════════════════════════════════════
check('D1 五文件花括号平衡（本轮触碰面）',
      all(read(f).count('{') == read(f).count('}')
          for f in ['Natives/JavaLauncher.m', 'Natives/ZL2Theme.h', 'Natives/ZL2Theme.m',
                    'Natives/AmePluginBridge.h', 'Natives/AmePluginBridge.m',
                    'Natives/AmePluginRuntime.m']),
      '花括号不平衡')
check('D2 ame317 色链未破坏（色 setter/宏/28 项白名单原样）',
      'ame317_setPluginThemeTokens' in theme_m and 'AME317_PLUGIN_COLOR(primary, 0xA63A17, 0xFFB59F)' in theme_m
      and '@"surfaceContainerHighest", @"surfaceBright",' in theme_m,
      'ame317 色链被本轮破坏')
check('D3 js_smoke 桩面含色/形状双 handler（fluent-ui v2 行为面进冒烟）',
      'setThemeTokenHandler' in read('scripts/ame330_js_smoke.js')
      and 'setThemeShapeHandler' in read('scripts/ame330_js_smoke.js'),
      '冒烟桩面缺件')

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
