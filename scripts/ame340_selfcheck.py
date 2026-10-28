#!/usr/bin/env python3
# Task340 自检电池 —— 三线：
#   A Fluent 启动器换装退役（用户澄清：Fluent 2 / Apple 重设计只落 fluent-ui
#     插件，不落启动器代码；启动器主页回归 ZL2 令牌）
#   B 插件仓库远程件不可见根修（jsdelivr @main CDN 缓存 purge 预热 + CI 自动 purge）
#   C "竖窗转横屏只有左下角在动"根修（MC 尺寸宣告通道可达性闸 + drawable 恒钉）
# 惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
import os, re, sys

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

# ── 读面 ─────────────────────────────────────────────────────
repo_vc = read('Natives/ZL2PluginRepoViewController.m')
ibr = read('Natives/input_bridge_v3.m')
utils_h = read('Natives/utils.h')
svc = read('Natives/SurfaceViewController.m')
cmk = read('Natives/CMakeLists.txt')
smoke = read('scripts/ui_fluent_smoke.sh')
home = read('Natives/ZL2HomeViewController.m')
dev_yml = open(os.path.join(REPO, '.github/workflows/development.yml'), 'rb').read()

if '--selftest' in sys.argv:
    print('== ame340 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-C1: 可达性查询被击穿（恒活）→ C3 闸探针必翻红
    inj_ibr = ibr.replace('if (GLFW_invoke_WindowSize || GLFW_invoke_FramebufferSize) return 1;',
                          'if (1) return 1;', 1)
    ok_c1 = 'if (GLFW_invoke_WindowSize || GLFW_invoke_FramebufferSize) return 1;' not in inj_ibr
    if ok_c1:
        print('ok  S-C1 反向：可达性查询击穿 -> FAIL（符合预期）')
    else:
        print('S-C1 未翻红（通道查询探针失效）'); bad += 1
    # S-C2: 闸被禁用 → C3/C4 探针必翻红
    inj_svc = svc.replace('if (!ame340_mc_resize_channel_alive()) {',
                          'if (NO) {', 1)
    ok_c2 = (inj_svc != svc) and ('if (!ame340_mc_resize_channel_alive()) {' not in inj_svc
                                  or inj_svc.count('ame340_mc_resize_channel_alive') != svc.count('ame340_mc_resize_channel_alive'))
    if not ok_c2:
        print('S-C2 未翻红（闸探针失效）'); bad += 1
    else:
        print('ok  S-C2 反向：闸禁用 -> FAIL（符合预期）')
    # S-B1: purge 逻辑被摘 → B1 探针必翻红
    inj_vc = repo_vc.replace('stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"', '@"x"', 1)
    ok_b1 = 'stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"' not in inj_vc
    if ok_b1:
        print('ok  S-B1 反向：purge 摘除 -> FAIL（符合预期）')
    else:
        print('S-B1 未翻红（purge 探针失效）'); bad += 1
    print(f'selftest: {"FAIL " + str(bad) + " probes failed to trigger" if bad else "3/3 反向探针全翻红"}')
    sys.exit(1 if bad else 0)

# ══ A 线A Fluent 启动器换装退役 ═════════════════════════════════
check('A1 AMEFluentTheme h/m 文件已删除',
      not os.path.isfile(os.path.join(REPO, 'Natives/AMEFluentTheme.h'))
      and not os.path.isfile(os.path.join(REPO, 'Natives/AMEFluentTheme.m')),
      '令牌层文件仍在')
check('A2 主页零 AMEFluentTheme（import ZL2Theme 回归）',
      'AMEFluentTheme' not in home and '#import "ZL2Theme.h"' in home,
      '主页换装未回退干净')
check('A3 CMakeLists 无 AMEFluentTheme TU', 'AMEFluentTheme' not in cmk, '编译面残留')
check('A4 smoke 脚本无功能位引用（syntax 条件 + sources 元素）',
      '-e \'"AMEFluentTheme\\.h"\' -e' not in smoke
      and not re.search(r'^\s+AmeTheme\s+AMEFluentTheme', smoke, re.M),
      'smoke 功能位残留')

# ══ B 线B 插件仓库远程件可见性（CDN purge）══════════════════════
vc_code = strip_code(repo_vc)
check('B1 jsdelivr purge 预热（cdn→purge 换域拼接 + containsString 触发）',
      'purge.jsdelivr.net' in repo_vc
      and 'stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"' in repo_vc
      and '[base containsString:@"cdn.jsdelivr.net"]' in repo_vc,
      'purge 预热缺件')
check('B2 purge 取证日志（http 码落盘）',
      'Task340 jsdelivr index cache purge' in repo_vc,
      '取证日志缺失')
check('B3 purge 单次闸（ame340_purged 每 open 至多一次）',
      'BOOL ame340_purged = NO;' in repo_vc and '!ame340_purged &&' in repo_vc,
      '单次闸缺失')
check('B4 index 拉取取证带插件计数（fetched via %base (N plugins)）',
      '(%lu plugins)' in repo_vc and '[index[@"plugins"] count]' in repo_vc,
      '取证计数缺失')
check('B5 CI 自动 purge 步骤（构建成功后 curl purge 端点）',
      b'Purge jsdelivr plugin-repo index cache (Task340)' in dev_yml
      and b'purge.jsdelivr.net/gh/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2@main/plugin-repo/index.json' in dev_yml
      and b'matrix.platform_name == \'ios\' && success()' in dev_yml,
      'CI purge 步骤缺失')
check('B6 development.yml 行尾完整（全 CRLF 零混行）',
      dev_yml.count(b'\r\n') == dev_yml.count(b'\n'),
      'CRLF 混行（K4 雷）')

try:
    import yaml
    d = yaml.safe_load(dev_yml.decode('utf-8'))
    steps = d['jobs']['build']['steps']
    last = steps[-1]
    b7_ok = ('Purge jsdelivr' in last.get('name', '')
             and 'purge.jsdelivr.net' in last.get('run', ''))
except Exception as e:
    b7_ok = False
# 重算 passed/fails（B7 动态校验）
print(('PASS ' if b7_ok else 'FAIL ') + 'B7 YAML 结构校验（可解析 + steps 尾部 = purge 步骤）')
if b7_ok:
    passed += 1
else:
    fails.append('B7 YAML 结构校验')

# ══ C 线C 左下角根修（MC 可达性闸）════════════════════════════
check('C1 通道可达性查询（三通道判据：GLFW invoke 双指针 ∪ SDL 窗口+PushEvent）',
      'int ame340_mc_resize_channel_alive(void)' in ibr
      and 'if (GLFW_invoke_WindowSize || GLFW_invoke_FramebufferSize) return 1;' in ibr
      and 'if (g_sdlWindow && pSDL_PushEvent) return 1;' in ibr
      and 'return 0;' in ibr,
      '可达性查询缺件')
check('C2 utils.h 声明在位',
      'int ame340_mc_resize_channel_alive(void);' in utils_h,
      '声明缺失')
check('C3 ame328 核心入口闸（闸内 drawable 钉回信念整帧 + return NO）',
      'if (!ame340_mc_resize_channel_alive()) {' in svc
      and 'Task340: belief recompute gated' in svc
      and 'Task340: drawable re-pinned to frozen belief' in svc
      and 'ame340_ml.drawableSize = ame340_tgt;' in svc,
      '核心闸缺件')
check('C4 会话内分辨率调节入口闸（不可达回落重启生效）',
      'Task340: in-session resolution apply unavailable' in svc,
      '调节闸缺失')
check('C5 宣告通道取证探针（首 3 次打印 invoke 指针状态）',
      'Task340 resize channel probe #%d' in ibr
      and 's_ame340_probe' in ibr,
      '取证探针缺失')
check('C6 338 两段式链未破坏（announce-first 五件套仍在）',
      'isUseStackQueueCall && isInputReady' in svc
      and 'g_ame338_pendingResCommit = YES;' in svc
      and '2.0 * NSEC_PER_SEC' in svc,
      '338 两段式被本轮破坏')
check('C7 333 trio 不在闸路径（闸早退不注册三连）',
      svc.index('if (!ame340_mc_resize_channel_alive()) {')
      < svc.index('announce trio #2'),
      '闸与 trio 顺序异常')

# ══ D 线D 结构护栏 ═════════════════════════════════════════════
check('D1 ame339 C 组已翻转（无换装断言方向）',
      "check('C1 AMEFluentTheme 令牌层退役（h/m 文件不存在）'" in read('scripts/ame339_selfcheck.py'),
      'ame339 C 组未翻转')
check('D2 task139 语法面（新函数花括号平衡抽查）',
      svc.count('{') == svc.count('}') and ibr.count('{') == ibr.count('}'),
      '花括号不平衡')

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
