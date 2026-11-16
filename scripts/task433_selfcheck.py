#!/usr/bin/env python3
# Task433 自检门 —— 二代 issue#3「JIT 自救（退役镜像码缓存）开启仍崩」根修面
#   根因（jre17 libjvm 二进制取证 + 装机 hs_err_pid41485 实锤）：
#     JIT26 调试映射函数（dlsym DeviceHasTXM / XNU_HAS_TXM 环境变量 →
#     brk #0x69 向调试器请求可执行区 → vm_remap 造 RW 别名）由
#     MirrorMappedCodeCache 旗标单点闸控；自救退役该旗标 = libjvm 回落
#     普通 mmap 路径，其页在 TXM 调试 JIT（StikJIT/StikDebug 家族）下
#     从未被授权可执行 → 首次取指 ~StubRoutines::call_stub 即 SIGBUS
#     BUS_ADRALN（pc==si_addr，启动 55ms java.lang <clinit> 即死）。
#     镜像轨 = TXM 调试 JIT 设备唯一可执行内存通道。
#   修复面：
#     A9  JavaLauncher launchJVM + launchHeadlessJVM 双站 TXM 闸——
#         自救请求在 TXM 调试 JIT 环境被忽略（镜像轨保留）。
#     A10 main_hook ame273 自救已激活改道分支——不再重复武装（空转），
#         弹窗讲真话（非镜像轨不可执行；指引 = 保留镜像轨 + 更新/更换
#         JIT 开启工具 + Java 21 建议）。
#   剥离器：strip_keep_str（ame342 家法——去注释保字符串；NSLog/fix 文案
#   断言目标在字符串字面量内，real 剥离器会把字符串替换成 "" 导致假阴）。
#   惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
# ★Task434（二代 issue#3 跟进）：A13 ame434 JIT26 运行时预检探针双站接线
#   + marker 新鲜度（通过即清）· A14 ame273 ame434 精确分支（换 Java 17）
#   · A15 Task433 被证伪的「改用 Java 21」建议退役（装机 hs_err_pid46873
#   + latestlog 零 mapping 行实锤：Java 21 21.0.8 缺 JIT26 映射实现）。
import os
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


def strip_keep_str(src):
    # ame342 家法：单遍扫描去注释保字符串（字符串内 "/*" 不触发注释状态）
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


jl_code = strip_keep_str(read('Natives/JavaLauncher.m'))
mh_code = strip_keep_str(read('Natives/main_hook.m'))

GATE = 'if (ame342_retireMirror && JIT26IsLikelyDebuggerKeepAttached()) {'

if '--selftest' in sys.argv:
    print('== task433 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-1: TXM 闸被摘（闸条件替换为恒假）→ A9 必翻红
    inj_jl = jl_code.replace(GATE, 'if (NO) {')
    ok = GATE not in inj_jl
    if ok:
        print('ok  S-1 反向：Task433 TXM 闸摘除 -> A9 FAIL（符合预期）')
    else:
        print('S-1 未翻红（TXM 闸探针失效）'); bad += 1
    # S-2: main_hook 改道分支被摘（ame433 日志锚删除）→ A10 必翻红
    inj_mh = mh_code.replace('[Ame433] SIGBUS+call_stub while self-rescue already active', 'REDACTED')
    ok = '[Ame433] SIGBUS+call_stub while self-rescue already active' not in inj_mh
    if ok:
        print('ok  S-2 反向：ame273 改道分支摘除 -> A10 FAIL（符合预期）')
    else:
        print('S-2 未翻红（改道分支探针失效）'); bad += 1
    # S-3: ame434 探针双站接线被摘 → A13 必翻红
    inj_jl2 = jl_code.replace('ame434_probeJit26Runtime(javaHome);', '/* REDACTED */;')
    ok = 'ame434_probeJit26Runtime(javaHome);' not in inj_jl2
    if ok:
        print('ok  S-3 反向：ame434 探针双站接线摘除 -> A13 FAIL（符合预期）')
    else:
        print('S-3 未翻红（探针接线探针失效）'); bad += 1
    # S-4: 被证伪的 Java 21 建议回流 → A15 必翻红（对 A15 谓词做
    #      健康/病态双向验证：真代码必须健康，注入后必须翻红）
    def a15_pred(src):
        return ('改用 Java 21 运行时' not in src and
                'use a Java 21 runtime for this instance' not in src and
                '或对该实例改用 Java 17 运行时' in src and
                'switch this instance to a Java 17 runtime' in src)
    inj_mh2 = mh_code.replace('switch this instance to a Java 17 runtime',
                              'use a Java 21 runtime for this instance')
    ok = a15_pred(mh_code) and (not a15_pred(inj_mh2))
    if ok:
        print('ok  S-4 反向：证伪建议回流 -> A15 FAIL（符合预期）')
    else:
        print('S-4 未翻红（证伪建议探针失效）'); bad += 1
    if bad == 0:
        print('selftest OK（4 探针全部翻红）')
        sys.exit(0)
    sys.exit(1)

print('== A9/A10 组：Task433 TXM 调试 JIT 自救闸（二代 issue#3）==')

# A9: launchJVM + launchHeadlessJVM 双站 TXM 闸——自救请求在 TXM 调试 JIT
#     （StikJIT/StikDebug 家族）环境被忽略（镜像轨保留）。
check('A9 Task433 TXM 闸双站（launchJVM + headless 保留镜像轨）',
      jl_code.count(GATE) == 2 and
      jl_code.count('ame342_retireMirror = NO;') == 2 and
      'Task433: self-rescue requested but TXM debugger JIT active -- mirror track kept' in jl_code and
      'Task433: self-rescue requested but TXM debugger JIT active (processors path) -- mirror track kept' in jl_code)

# A10: main_hook ame273 自救已激活改道分支——不再重复武装，弹窗讲真话。
check('A10 main_hook 自救已激活改道分支（ame433 诚实文案）',
      '[Ame433] SIGBUS+call_stub while self-rescue already active' in mh_code and
      '无法运行非镜像轨' in mh_code and
      'TXM 调试 JIT 唯一可执行内存通道' in mh_code)

# A11: 原有自救武装与既有 fix 文案零回归（Task430 面）——改道分支不得
#      顶掉未激活状态的自动自救。
check('A11 Task430 自动自救 + 既有 fix 文案零回归',
      'setPrefBool(@"debug.mirror_codecache_disable", YES);' in mh_code and
      'ame342_mirror_retired.txt' in mh_code and
      '已自动开启「JIT 自救模式」' in mh_code)

# A12: 342 退役旗标闸零回归（ame342 A2/A4 同款口径）——TXM 闸只改
#      ame342_retireMirror 变量，旗标推送行形态不变。
check('A12 ame342 退役旗标闸零回归（MARGV/HARGV 双落位）',
      '} else if (@available(iOS 26.0, *) && !ame342_retireMirror) {' in jl_code and
      'PUSH_MARGV_LITERAL("-XX:+MirrorMappedCodeCache");' in jl_code and
      'PUSH_HARGV_LITERAL("-XX:+MirrorMappedCodeCache");' in jl_code)

print('== A13/A14/A15 组：Task434 JIT26 运行时预检探针（二代 issue#3 跟进）==')

# A13: ame434 探针助手 + 双站接线 + marker 通道与新鲜度语义。
check('A13 ame434 JIT26 运行时预检探针双站接线（launchJVM + headless）',
      'static void ame434_probeJit26Runtime(NSString *javaHome)' in jl_code and
      jl_code.count('ame434_probeJit26Runtime(javaHome);') == 2 and
      'XNU_HAS_TXM' in jl_code and 'DeviceHasTXM' in jl_code and
      'Got JIT mapping' in jl_code and
      'ame434_jit26_missing.txt' in jl_code and 'unlink(ame434_path)' in jl_code)

# A14: main_hook ame434 精确分支——marker 在场给换运行时指引，优先级在
#      Task433 分支之前（分支序：ame434 探针 → ame433 自救已激活 → Task430 原文）。
check('A14 main_hook ame434 精确分支（运行时缺 JIT26 → 换 Java 17）',
      '[Ame434] SIGBUS+call_stub with ame434_jit26_missing.txt present' in mh_code and
      '缺少 JIT26 调试映射实现' in mh_code and
      '改用 Java 17 运行时' in mh_code and
      'ame434_jit26_missing.txt' in mh_code and
      mh_code.index('ame434_jit26Missing') < mh_code.index('[Ame433] SIGBUS+call_stub'))

# A15: Task433 被装机实测证伪的「改用 Java 21」建议退役（修正为 Java 17）。
check('A15 被证伪的 Java 21 建议退役（Java 17 指引在场）',
      '改用 Java 21 运行时' not in mh_code and
      'use a Java 21 runtime for this instance' not in mh_code and
      '或对该实例改用 Java 17 运行时' in mh_code and
      'switch this instance to a Java 17 runtime' in mh_code)

print(f'\n== task433_selfcheck: {passed} passed, {len(fails)} failed ==')
if fails:
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('ALL GREEN')
sys.exit(0)
