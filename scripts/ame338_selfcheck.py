#!/usr/bin/env python3
"""Task338 门禁电池 —— 四线收口断言（用户四问：非SDL 分辨率慢+黑块 /
Fluent UI 插件 / 旧页无入口功能补入口 + 主页整洁 / 继续退役旧UI）。

线A 非SDL（LWJGL2 栈队列会话）分辨率两段式应用根修：
  病灶：Task328 旧即时路径【先改 drawableSize/contentsScale 后通告】，
  MC 信念经栈队列异步追赶（加载屏停泵期以秒计），窗口内 GL 渲染器按旧
  帧缓冲呈现到新 drawable，未覆盖区域 = 未初始化内存上屏 = 黑块。
  A1 ame328 全屏分支 announce-first 段（栈队列条件 + 强制通道 + 挂起旗标
     + 2s 看门狗 + 提前 return YES）
  A2 宣告尺寸公式与 updateSavedResolution 口径同源（physical × res / fsr
     + 奇偶修正）
  A3 非栈队列（GLFW 直调/SDL）旧即时路径原样保留（全链重算 + 强制宣告）
  A4 泵尾消费者（input_bridge_v3：consume 旗标 + dispatch main + commit 调用）
  A5 commit 方法（主线程串行化 + updateSavedResolution + 幂等重宣告）
     + SurfaceViewController.h 跨文件 selector 声明（Task256 盲区第六例纪律）
  A6 旗标供给闭环（utils.h extern + input_bridge_v3 定义 volatile BOOL）
线B fluent-ui 内置插件（依 Fluent 2 / Apple 材质令牌）：
  B1 manifest 契约（id==dir/entry/minApi）
  B2 权限声明 ⊆ 注册表（ui.rows/ui.dialog/ui.theme/storage）
  B3 main.js 结构（ame 守卫/行注册/setThemeToken/__theme 持久化）
  B4 三板 + 恢复默认（setThemeToken({}) 清除语义）
  B5 ame318 电池语义演进（expect_ids +2 / keyset 21）
  B6 i18n 四表两键齐
线C 旧页功能迁移第一实体（清理垃圾 + 查找/恢复版本 → 新 UI 版本页）：
  C1 版本页页头第三钮（magnifyingglass + 扫描版本 + ame338_showScanSheet）
  C2 新 UI 零旧 VC 依赖（ZL2VersionsViewController 不 import
     CleanupViewController/VersionManagerViewController —— 自包含移植，
     Preview/smoke 链接面零新增符号 = 第十一例免疫）
  C3 versions 扫描移植（ame338_scanInstalledVersions：GAME_DIR 优先/HOME
     兜底 + referenced/jsonOK/sizeBytes 四元组）
  C4 日志垃圾路径移植（launcherLogPaths 前缀集 + mcLogPaths 三目录）
  C5 无引用版本恢复（saveProfile + gameDir=versions/<id> + ReloadProfileList）
  C6 ZL2CleanupPage（@interface 前置于消费点 + scanner 注入 + ame_action
     weak 页面引用 + 确认删除 + 空态）
  C7 vm.scan/cleanup.* 复用既有 i18n 键（不新增重复键）
线D 结构完整性：
  D1 括号平衡（HEAD 对照 ×5 文件）
  D2 Preview TU 面（ZL2VersionsViewController 保持 + smoke 零新增依赖）
  D3 跨 TU 符号供给（ame338_commitPendingResolutionGeometry 三点：
     .h 声明/.m 实现/input_bridge 调用；g_ame338 旗标两点）
  D4 ame318 电池已含 fluent-ui 断言（防断言漂移）

--selftest 反向验证模式（Task337 首立纪律）：内存注入病灶变体，断言
  必须翻红（A1/A4/C2 三探针），不触碰仓内文件。
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

failures = []
passed = 0

SELFTEST_MUTATIONS = {
    # 探针: (文件, 旧, 新, 必翻红断言名前缀)
    'A1': ('Natives/SurfaceViewController.m',
           'g_ame338_pendingResCommit = YES;', 'g_ame338_pendingResCommit = NO;'),
    'A4': ('Natives/input_bridge_v3.m',
           'if (g_ame338_pendingResCommit) {', 'if (NO && g_ame338_pendingResCommit) {'),
    'C2': ('Natives/ZL2VersionsViewController.m',
           '#import "PLProfiles.h"', '#import "PLProfiles.h"\n#import "CleanupViewController.h"'),
}

selftest_expect = set()

def check(name, cond, detail=''):
    global passed
    probe = next((p for p in selftest_expect if name.startswith(p)), None)
    if probe is not None:
        # 反向验证探针：期望 FAIL
        if cond:
            failures.append('SELFTEST-' + name)
            print(f'  FAIL(反向) {name} -- 预期翻红但保持绿')
        else:
            passed += 1
            print(f'  ok(反向红) {name}')
        return
    if cond:
        passed += 1
        print(f'  ok  {name}')
    else:
        failures.append(name)
        print(f'  FAIL {name} {detail}')

def read(rel):
    with open(os.path.join(ROOT, rel), errors='ignore') as f:
        return f.read()

def _strip_code(text):
    """真代码剥离（符号引用检查用）：剥块注释/字符串字面量/行注释，保留标识符。
    （ame337 r1 判例：task139.strip_strings_comments 是括号平衡剥器只保留括号
    字符，误用于符号检查 = 恒空恒过假阳性。）"""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)          # 块注释
    text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)          # 字符串字面量
    lines = []
    for ln in text.split('\n'):                                 # 行注释
        i = ln.find('//')
        lines.append(ln[:i] if i >= 0 else ln)
    return '\n'.join(lines)

def _strip_strings_comments(text):
    sys.path.insert(0, os.path.join(ROOT, 'scripts'))
    import task139_syntax_gate as _t139
    return _t139.strip_strings_comments(text)

def _deltas(src):
    return (src.count('{') - src.count('}'),
            src.count('(') - src.count(')'),
            src.count('[') - src.count(']'))

if '--selftest' in sys.argv:
    for probe, (rel, old, new) in SELFTEST_MUTATIONS.items():
        src = read(rel)
        assert old in src, f'selftest anchor missing in {rel}: {old}'
        globals()['_mut_' + probe] = True
    selftest_expect = {'A1 announce-first', 'A4 pump-tail consumer', 'C2 零旧 VC import'}
    _orig_read = read
    def read(rel):  # noqa: F811
        src = _orig_read(rel)
        for probe, (mrel, old, new) in SELFTEST_MUTATIONS.items():
            if mrel == rel and probe in ('A1', 'A4', 'C2'):
                src = src.replace(old, new)
        return src

# ── 读面 ─────────────────────────────────────────────────────
svc = read('Natives/SurfaceViewController.m')
svch = read('Natives/SurfaceViewController.h')
ib3 = read('Natives/input_bridge_v3.m')
utilsh = read('Natives/utils.h')
zvv = read('Natives/ZL2VersionsViewController.m')
manifest = read('plugin-repo/src/fluent-ui/manifest.json')   # ★Task339：外置回远程仓库（bundle 路径退役）
mainjs = read('plugin-repo/src/fluent-ui/main.js')
s318 = read('scripts/ame318_selfcheck.py')
smoke = read('scripts/ui_fluent_smoke.sh')

# ── A 线A 两段式分辨率 ────────────────────────────────────────
m338 = re.search(r'Task338（非SDL 调节分辨率"不迅速 \+ 黑块"根修）.*?\n\}', svc, re.S)
a1 = m338.group(0) if m338 else ''
check('A1 announce-first', bool(a1)
      and 'isUseStackQueueCall && isInputReady' in a1
      and 'CallbackBridge_nativeSendScreenSizeForced(ame338_w, ame338_h)' in a1
      and 'g_ame338_pendingResCommit = YES;' in a1
      and '2.0 * NSEC_PER_SEC' in a1
      and 'watchdog commit' in a1
      and 'return YES;' in a1,
      'announce-first 段五件套缺失')

check('A2 宣告尺寸公式同源（physical×res/fsr + 奇偶修正）',
      'roundf((float)physicalWidth * ame328_res / ame338_fsr)' in a1
      and '(ame338_w % 2) != 0' in a1 and '(ame338_h % 2) != 0' in a1,
      '公式或奇偶修正缺失')

check('A3 非栈队列旧即时路径保留（全链重算+强制宣告）',
      '[self updateSavedResolution];' in a1
      and 'CallbackBridge_nativeSendScreenSizeForced(windowWidth, windowHeight);' in a1
      and 'ame248_geoResyncPending = YES;' in a1,
      '旧路径缺失（误删 SDL/GLFW 直调即时应用）')

m4 = re.search(r'Task338（非SDL 分辨率两段式应用·第二段触发器）.*?\n    \}', ib3, re.S)
a4 = m4.group(0) if m4 else ''
check('A4 pump-tail consumer', bool(a4)
      and 'if (g_ame338_pendingResCommit) {' in a4
      and 'g_ame338_pendingResCommit = NO;' in a4
      and 'dispatch_async(dispatch_get_main_queue' in a4
      and 'ame338_commitPendingResolutionGeometry' in a4,
      '泵尾消费者缺失')

m5 = re.search(r'- \(void\)ame338_commitPendingResolutionGeometry \{.*?\n\}', svc, re.S)
a5 = m5.group(0) if m5 else ''
check('A5 commit 方法三件套（主线程钳制+全链重算+幂等重宣告）',
      bool(a5)
      and 'isMainThread' in a5
      and 'dispatch_async(dispatch_get_main_queue' in a5
      and '[self updateSavedResolution];' in a5
      and 'CallbackBridge_nativeSendScreenSizeForced(windowWidth, windowHeight);' in a5,
      'commit 三件套缺失')
check('A5b SurfaceViewController.h 跨文件 selector 声明',
      '- (void)ame338_commitPendingResolutionGeometry;' in svch,
      '.h 声明缺失（Task256 盲区第六例模式）')

check('A6 旗标供给闭环（utils.h extern + input_bridge volatile 定义）',
      'extern volatile BOOL g_ame338_pendingResCommit;' in utilsh
      and re.search(r'volatile BOOL g_ame338_pendingResCommit = NO;', ib3) is not None,
      'extern 或定义缺失')

# ── B 线B fluent-ui 插件 ─────────────────────────────────────
import json as _json
try:
    m = _json.loads(manifest)
except Exception as e:
    m = {}
    check('B1 manifest 解析', False, str(e))
if m:
    check('B1 manifest 契约', m.get('id') == 'fluent-ui'
          and m.get('entry') == 'main.js' and m.get('minApi') == 1
          and bool(m.get('name')) and bool(m.get('version')),
          'manifest 字段缺失')
perm_src = read('Natives/AmePluginPermissions.m')
registry = set(re.findall(r'initWithId:@"([a-z0-9._]+)"', perm_src))
check('B2 权限声明 ⊆ 注册表', bool(m) and set(m.get('permissions') or []) <= registry
      and {'ui.rows', 'ui.dialog', 'ui.theme', 'storage'} <= set(m.get('permissions') or []),
      f'permissions={m.get("permissions")} registry_gap={sorted(set(m.get("permissions") or []) - registry)}')

js_code = _strip_code(mainjs)
check('B3 main.js 结构四件套', 'typeof ame' in mainjs
      and 'addLauncherRow' in js_code
      and 'setThemeToken' in js_code
      and "'__theme'" in mainjs and len(mainjs) > 2000,
      '结构缺失或脚本过短')

check('B4 三板 + 恢复默认语义（Task341 v2：桥面统一空表重放=清除，色+形状双清）',
      "key: 'fluent-light'" in mainjs and "key: 'fluent-dark'" in mainjs
      and "key: 'fluent-apple'" in mainjs
      and 'ame.setThemeToken({})' in js_code
      and 'ame.setThemeShape({})' in js_code,
      '三板或缺恢复默认')

check('B5 ame318 电池语义演进', "{'plugin-survey'}" in s318
      and 'len(base) == 21' in s318,
      'ame318 断言未随插件外置演进（Task339）')

i18n_ok = True
i18n_detail = ''
for lang in ('en', 'zh-Hans', 'zh-CN', 'zh-Hant'):
    txt = read(f'Natives/resources/{lang}.lproj/Localizable.strings')
    if 'ame318.builtin.fluent-ui.name' not in txt or 'ame318.builtin.fluent-ui.desc' not in txt:
        i18n_ok = False
        i18n_detail += lang + ' '
check('B6 i18n 四表两键齐', i18n_ok, 'missing: ' + i18n_detail)

# ── C 线C 旧页功能迁移 ────────────────────────────────────────
zvv_code = _strip_code(zvv)
check('C1 版本页页头第三钮', 'ame338_showScanSheet' in zvv_code
      and 'magnifyingglass' in zvv
      and 'accessibility:@"扫描版本"' in zvv,
      '扫描钮缺失')

check('C2 零旧 VC import（自包含移植纪律）',
      '#import "CleanupViewController.h"' not in zvv
      and '#import "VersionManagerViewController.h"' not in zvv
      and 'CleanupViewController' not in zvv_code
      and 'VersionManagerViewController' not in zvv_code,
      '新 UI 仍依赖旧 VC 头/类')

check('C3 versions 扫描移植四元组',
      '+ (NSArray<NSDictionary *> *)ame338_scanInstalledVersions' in zvv
      and '@"referenced"' in zvv and '@"jsonOK"' in zvv
      and '@"sizeBytes"' in zvv
      and 'getenv("POJAV_GAME_DIR") ? getenv("POJAV_GAME_DIR") : getenv("POJAV_HOME")' in zvv,
      '扫描器移植缺失或口径漂移')

check('C4 日志垃圾路径移植',
      '+ (NSMutableArray<NSString *> *)ame338_launcherLogPaths' in zvv
      and '+ (NSMutableArray<NSString *> *)ame338_mcLogPaths' in zvv
      and '@"latestlog.old"' in zvv and '@"latestlog.crash"' in zvv
      and 'crash-reports' in zvv and 'hs_err_pid' in zvv,
      '路径移植缺失')

check('C5 无引用版本恢复链', '[PLProfiles.current saveProfile:profile withName:vid]' in zvv
      and 'versions/%@' in zvv
      and 'postNotificationName:@"ReloadProfileList"' in zvv,
      '恢复链缺失')

check('C6a ZL2CleanupPage 前置声明先于消费',
      zvv.find('@interface ZL2CleanupPage') < zvv.find('- (void)ame338_showCleanup {'),
      '@interface 后置 = undeclared identifier 编译雷')
check('C6b ZL2CleanupPage 结构四件套',
      '@property(nonatomic, copy) NSArray<NSDictionary *> *(^ame338_versionScanner)(void);' in zvv
      and 'ame338_confirmRow' in zvv_code
      and 'weakPage' in zvv
      and '没有可清理的垃圾' in zvv,
      '页面结构缺失')

vm_keys = ('vm.scan.title', 'vm.scan.restore', 'vm.scan.cleanup', 'vm.scan.no_orphan')
check('C7 复用既有 i18n 键（零重复键面）',
      all(f'localize(@"{k}"' in zvv for k in vm_keys),
      'vm.scan 键未复用')

# ── D 结构完整性 ────────────────────────────────────────────
for rel in ('Natives/SurfaceViewController.m',
            'Natives/SurfaceViewController.h',
            'Natives/input_bridge_v3.m',
            'Natives/utils.h',
            'Natives/ZL2VersionsViewController.m'):
    cur = _deltas(_strip_strings_comments(read(rel)))
    try:
        head_src = subprocess.run(['git', 'show', f'HEAD:{rel}'],
                                  cwd=ROOT, capture_output=True, text=True).stdout
        head = _deltas(_strip_strings_comments(head_src))
        check(f'D1 括号平衡(HEAD对照) {os.path.basename(rel)}', cur == head,
              f'cur={cur} head={head}')
    except Exception as e:
        check(f'D1 括号平衡(HEAD对照) {os.path.basename(rel)}', False, str(e))

check('D2 Preview TU 面（ZL2VersionsViewController 保持 + 零新增旧依赖）',
      'ZL2VersionsViewController' in smoke
      and 'CleanupViewController' not in smoke
      and 'VersionManagerViewController' not in smoke,
      'TU 清单漂移')

check('D3 跨 TU 符号供给（commit 方法三点 + 旗标两点）',
      '- (void)ame338_commitPendingResolutionGeometry;' in svch
      and '- (void)ame338_commitPendingResolutionGeometry {' in svc
      and '[vc ame338_commitPendingResolutionGeometry];' in ib3
      and 'extern volatile BOOL g_ame338_pendingResCommit;' in utilsh
      and 'volatile BOOL g_ame338_pendingResCommit = NO;' in ib3,
      '符号供给断链')

check('D4 ame318 断言含 fluent-ui（防断言漂移）',
      'fluent-ui' in s318,
      'ame318 断言未含新插件')

print()
if failures:
    print(f'FAIL {len(failures)}/{passed + len(failures)}: ' + ', '.join(failures))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
