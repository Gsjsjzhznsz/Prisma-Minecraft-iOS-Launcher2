#!/usr/bin/env python3
"""Task465 —— 游戏启动链恢复到仓库第一个预发行版（v1.0 tag = f3d31003，2026-10-31
「Prisma 2 Beta 发布」，全仓唯一/首个 prerelease）。

病历链（用户装机 latestlog 实证，Commit a21e8ca = Task464 构建）：
  Ame451 preflight PASSED（x16=1 分配通道健康）→ DyldLVBypass init →
  Task457 op4 canary verdict=0 → ame457 优雅拦截 → JVM 拒绝发射。
同机 A/B：一代（Prisma-Minecraft-iOS-Launcher，v7.0 = Task 333 时代）同设备
  同调试器正常起游戏。Task464 的「canary 条件收紧对齐一代」预判（设备
  FORCE_MIRRORED=0）被 Task464 构建装机日志证伪：canary 实跑 = 双 flags 真。

定谳（本轮判例，入册 worklog Task465）：
  ① UniversalJIT26.js commands 表仅 x16=0/1/2，op4 处理器由
     UniversalJIT26Extension.js（op2 推送 eval 注册）提供——脚本自 2026-03
     上游同步后三代零改动（两仓 commit 哈希同源），协议不因代际而异；
  ② v1.0/一代形态：op4 裸调 + 无拦截——调试器侧未知命令优雅跳过
     （主循环 P20=pc+4 先行）或扩展处理器应答，钩子 best-effort 落位，
     启动直达（一代同设备可用 = 该形态实证）；
  ③ Task437/451/457/464 四层（自证探针/64MB 预检/op4 canary+三重防线/
     条件收紧）为 v2 代新增启动拦截面，任何一层不通过即拒绝发射——
     在脚本协议不主动应答 op4 的现实下必杀所有标准脚本会话。

本轮外科：启动链四文件恢复 v1.0 形态（dyld_bypass_validation.m 整文件；
utils.h/utils.m/JavaLauncher.m 剥离 437/451/457/464 四层），PLPreferences
逃生阀注册与 54 语种两弹窗键随面退役；Task433/434 TXM 镜像轨闸、
Task304/301/342/267/302（≤368 = v1.0 原生内容）与 Task463 折叠面零触碰。

判例 N+19（大写 C 函数 N+18 同族延伸）：门禁断言目标含「★」注释行时，
git show 历史版本回填 vs 行号切除混用会让注释与代码错位——切除必须以
唯一文本锚定起止行，禁用裸行号。
"""
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
os.chdir(ROOT)

fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok:
        fails.append(name)


def rd(rel):
    with open(rel, encoding='utf-8') as f:
        return f.read()


def wr(rel, text):
    with open(rel, 'w', encoding='utf-8') as f:
        f.write(text)


def balance_ok(src):
    """括号平衡粗检（字符串/注释内的括号会有偏差，只比相对变化）。"""
    return src.count('{') - src.count('}')  # 仅记录用


def cut_block(text, start_marker, end_marker, keep_end=True):
    """按唯一文本锚切除 [start_marker 行, end_marker 行)；keep_end=False 时含 end_marker 行。"""
    si = text.index(start_marker)
    ei = text.index(end_marker, si)
    if not keep_end:
        ei += len(end_marker)
    return text[:si] + text[ei:], text[si:ei]


print('== Task465 启动链恢复：dyld_bypass_validation.m 整文件回填 v1.0 ==')
blob = subprocess.run(
    ['git', 'show', 'v1.0:Natives/dyld_bypass_validation.m'],
    capture_output=True, text=True, check=True).stdout
check('R0a v1.0 blob 健全（void init + 裸 op4 在场）',
      'void init_bypassDyldLibValidation() {' in blob
      and 'JIT26PrepareRegionForPatching(patchAddr, sizeof(patch));' in blob
      and 'JIT26PrepareRegion(map, len);' in blob)
check('R0b v1.0 blob 无 457/464 面（Safe/canary/Task457 零引入）',
      'ame457' not in blob and 'Safe' not in blob and 'canary' not in blob
      and 'Task457' not in blob and 'Task464' not in blob)

dyld_path = 'Natives/dyld_bypass_validation.m'
dyld_before = rd(dyld_path)
brk_before = dyld_before.count('{') - dyld_before.count('}')
wr(dyld_path, blob)
dyld_after = rd(dyld_path)
brk_after = dyld_after.count('{') - dyld_after.count('}')
check('R0c dyld 回填后括号平衡不漂移', brk_before == brk_after,
      f'{brk_before} -> {brk_after}')

print('== utils.h：Safe 声明面退役 + init 签名回退 void ==')
uh_path = 'Natives/utils.h'
uh = rd(uh_path)
uh, _ = cut_block(
    uh,
    '// ★ Task457：brk #0xf00d 超调用安全护栏（Task91 信号网 + Task301 有界看门狗）。',
    'BOOL JIT26PrepareRegionForPatchingSafe(void *addr, size_t len);\n',
    keep_end=False)
uh = uh.replace(
    '// ★ Task457：返回 BOOL（dyld_mmap + dyld_fcntl 两钩是否全部落位）；调用方\n'
    '// （JavaLauncher 两处）对 FALSE 弹 ame457 诊断窗并优雅退出，不再带残缺钩子\n'
    '// 继续发射 JVM。\n'
    'BOOL init_bypassDyldLibValidation(void);',
    'void init_bypassDyldLibValidation();')
check('R1a utils.h Safe 声明归零',
      'JIT26PrepareRegionSafe' not in uh and 'JIT26PrepareRegionForPatchingSafe' not in uh)
check('R1b utils.h init 签名回退 void（v1.0 形态）',
      'void init_bypassDyldLibValidation();' in uh and
      'BOOL init_bypassDyldLibValidation' not in uh)
wr(uh_path, uh)

print('== utils.m：Task457 信号网 + Safe 包装块退役 ==')
um_path = 'Natives/utils.m'
um = rd(um_path)
um, _ = cut_block(
    um,
    '// ============================================================================\n'
    '// ★ Task457：brk #0xf00d 超调用安全护栏（op1/op4 通用）。',
    'BOOL JIT26PrepareRegionForPatchingSafe(void *addr, size_t size) {\n'
    '    return ame457_brkWithNet(^{ JIT26PrepareRegionForPatching(addr, size); });\n'
    '}\n\n',
    keep_end=False)
check('R2a utils.m ame457 信号网归零',
      'ame457_brkWithNet' not in um and 'ame457_trapEnv' not in um and
      'JIT26PrepareRegionSafe' not in um)
check('R2b utils.m 裸超调用四件套保留（v1.0 协议面）',
      all(f'mov x16, #{n} ' in um for n in (1, 2, 3, 4)) and
      'void JIT26PrepareRegionForPatching(void *addr, size_t size) {' in um)
wr(um_path, um)

print('== JavaLauncher.m：Task437/451 家族 + 调用点 + Task457 中止面退役 ==')
jl_path = 'Natives/JavaLauncher.m'
jl = rd(jl_path)
jl_bal_before = jl.count('{') - jl.count('}')

# (b) ame437 + ame451 静态家族整块（339~657 区，[437 注释头, init_loadMobileGluesConfig) ）
jl, cut_a = cut_block(
    jl,
    '// ★Task437（二代 issue#3 第五层）：JIT26 通道自证探针——「映射假阳性」检出。',
    'void init_loadMobileGluesConfig() {')

# (c) launchJVM 调用点：Task437 接线 + Task451 预检块（[437 接线注释, requiresTXMWorkaround 闭括号) ）
jl, cut_b = cut_block(
    jl,
    '        // ★Task437：通道自证接线——对 Task342 探针页做端到端真调用（映射',
    '    }\n\n    if (jit26AlwaysAttached) {')

# (d) launchJVM init 调用点：Task457 中止面 → v1.0 裸调用
jl = jl.replace(
    '    // The TXM hardware breakpoint mechanism (brk #0x69) does not conflict with dlopen hooks.\n'
    '    // ★ Task457：旁路失败 = JIT26 调试器没接住 op4 超调用（装机 .ips 实锤的\n'
    '    //   闪退点：launchMinecraft block 内 JIT26PrepareRegionForPatching+4\n'
    '    //   brk 61453 SIGTRAP 致死）——不带残缺钩子继续发射 JVM（必炸形态），\n'
    '    //   改走 ame457 诊断窗优雅退出（处置阶梯同 ame451 preflight 家族）。\n'
    '    if (!init_bypassDyldLibValidation()) {\n'
    '        NSLog(@"[JavaLauncher] Task457: dyld library-validation bypass incomplete (JIT26 debugger did not serve brk #0xf00d op4) -- aborting launch gracefully");\n'
    '        showDialog(localize(@"Error", nil), localize(@"i18n_str_ame457_dyldhook", nil));\n'
    '        [PLLogOutputView handleExitCode:1];\n'
    '        return 1;\n'
    '    }',
    '    // The TXM hardware breakpoint mechanism (brk #0x69) does not conflict with dlopen hooks.\n'
    '    init_bypassDyldLibValidation();')

# (e) headless init 调用点同型
jl = jl.replace(
    '    // Always activate Library Validation bypass (see launchJVM for rationale).\n'
    '    // ★ Task457：headless 路径同款优雅退出（诊断窗阶梯与 launchJVM 一致）。\n'
    '    if (!init_bypassDyldLibValidation()) {\n'
    '        NSLog(@"[JavaLauncher] Task457: dyld library-validation bypass incomplete (headless) -- aborting gracefully");\n'
    '        showDialog(localize(@"Error", nil), localize(@"i18n_str_ame457_dyldhook", nil));\n'
    '        return -1;\n'
    '    }',
    '    // Always activate Library Validation bypass (see launchJVM for rationale).\n'
    '    init_bypassDyldLibValidation();')

# (a) Task437 三 include 行——条件撤除：先完成家族/调用点切除并扫描残余
#     信号 API 面归零才撤（扫描只认调用形态：带括号的 API 名或类型声明，
#     不认注释文本——判例 N+19：注释含幂会制造假阴）
residual_pre = re.search(r'\bsigsetjmp\s*\(|\bsigaction\s*\(|sys_icache_invalidate\s*\(|\bsigjmp_buf\b', jl)
check('R3z include 撤除前提：家族切除后残余信号 API 调用面归零', residual_pre is None,
      repr(residual_pre.group(0)) if residual_pre else '')
if residual_pre is None:
    jl, _ = cut_block(
        jl,
        '#include <signal.h>   // ★Task437：通道自证探针三信号保护（SIGTRAP/SIGBUS/SIGSEGV）',
        '#include <libkern/OSCacheControl.h>   // ★Task437：sys_icache_invalidate（dyld_bypass 同款先例）\n',
        keep_end=False)

check('R3a Task457 中止面归零（两调用点同型替换成功）',
      jl.count('init_bypassDyldLibValidation();') == 2 and
      'i18n_str_ame457_dyldhook' not in jl and
      'Task457: dyld library-validation bypass incomplete' not in jl)
check('R3b ame437/ame451 家族归零',
      'ame437_selfVerifyJit26Channel' not in jl and
      'ame451_preflightJit26Channel' not in jl and
      'ame437_cannedAck' not in jl and
      'ame451_prepEnv' not in jl)
check('R3c Task437 include 行归零',
      '#include <signal.h>' not in jl and '#include <setjmp.h>' not in jl
      and 'OSCacheControl' not in jl)

# 保留面回归锚（v1.0 原生 + Task433/434 + Task463 折叠）
check('R4a v1.0 原生启动面全数在场（Task304/301/342/267/302/91/173）',
      'ame304_requestAndAwaitJITIfNeeded(@"Launch")' in jl and
      'ame301_createRegionWithWatchdog()' in jl and
      'Task342 probe region' in jl and
      'ame267.jit.legacy_stik' in jl and
      'ame302_clearStaleDebuggerPorts' in jl and
      'Task173: in-process JVM already used' in jl)
check('R4b Task433/434 TXM 镜像轨闸 + 运行时探针双站保留（JVM 可运行命脉）',
      jl.count('if (ame342_retireMirror && JIT26IsLikelyDebuggerKeepAttached()) {') == 2 and
      jl.count('ame434_probeJit26Runtime(javaHome);') == 2)
check('R4c 扩展推送 + 分离旗标保留（op2/op3 面，v1.0 原生；headless 为变量形态）',
      jl.count('JIT26SendJITScript(') == 2 and
      jl.count('JIT26SendJITScript([NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"UniversalJIT26Extension" ofType:@"js"]]);') == 1 and
      'JIT26SendJITScript(extensionScript);' in jl and
      'JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached)' in jl)

jl_bal_after = jl.count('{') - jl.count('}')
# 切除块自身括号自证：每块 { 与 } 计数相等（整块切除不破坏平衡）
for tag, blk in (('437/451 家族', cut_a), ('437/451 调用块', cut_b)):
    check(f'R3d 切除块括号自证（{tag}）', blk.count('{') == blk.count('}'),
          f"{blk.count('{')} vs {blk.count('}')}")
check('R3e JavaLauncher 括号平衡不漂移', jl_bal_before == jl_bal_after,
      f'{jl_bal_before} -> {jl_bal_after}')
wr(jl_path, jl)

print('== PLPreferences.m：Task451 逃生阀注册退役 ==')
pp_path = 'Natives/PLPreferences.m'
pp = rd(pp_path)
pp = pp.replace(
    '            // ★Task451：JIT26 授予前预检逃生阀（默认关 = 预检启用；3/3 空壳\n'
    '            //   定罪拒绝发射防 SIGBUS 黑屏，假阳性误拦时的用户侧旁路开关）\n'
    '            @"jit26_preflight_disable": @NO,\n', '')
check('R5a 逃生阀注册归零（毗邻 mirror_codecache 阀零触碰）',
      'jit26_preflight_disable' not in pp and 'mirror_codecache_disable' in pp)
wr(pp_path, pp)

print('== 54 语种两弹窗键退役（ame451/ame457 诊断窗文案） ==')
res_dir = 'Natives/resources'
touched = 0
for name in sorted(os.listdir(res_dir)):
    if not name.endswith('.lproj'):
        continue
    p = os.path.join(res_dir, name, 'Localizable.strings')
    if not os.path.isfile(p):
        continue
    s = rd(p)
    had = ('i18n_str_ame457_dyldhook' in s) or ('i18n_str_ame451_preflight' in s)
    if not had:
        continue
    lines = [ln for ln in s.split('\n')
             if '"i18n_str_ame457_dyldhook"' not in ln
             and '"i18n_str_ame451_preflight"' not in ln]
    wr(p, '\n'.join(lines))
    touched += 1
check('R6a 两键 54 语种全量退役（每表 1 键 → 0）',
      touched == 54, f'touched={touched}')
leftover = subprocess.run(
    ['git', 'grep', '-l', 'i18n_str_ame457_dyldhook', '--', 'Natives/resources'],
    capture_output=True, text=True)
check('R6b resources 残留复查（git grep 零命中）', leftover.stdout.strip() == '')

print('== 全局 banned 锚复核（四层退役面二进制源码级归零） ==')
for rel in ('Natives/JavaLauncher.m', 'Natives/utils.m', 'Natives/utils.h',
            'Natives/dyld_bypass_validation.m', 'Natives/PLPreferences.m'):
    s = rd(rel)
    banned = [b for b in ('ame457_', 'JIT26PrepareRegionSafe',
                          'JIT26PrepareRegionForPatchingSafe',
                          'jit26_preflight_disable') if b in s]
    check(f'R7 {rel} banned 锚归零', not banned, str(banned))
jl = rd(jl_path)
check('R8 JavaLauncher Task457/451/437 字样归零（注释含幂）',
      all(t not in jl for t in ('★Task437', '★Task451', '★ Task457', 'Task457:', 'Task451 preflight')))

print()
if fails:
    print(f'== task465_restore_launchchain: {len(fails)} FAILED ==')
    for f in fails:
        print('  FAIL:', f)
    sys.exit(1)
print('== task465_restore_launchchain: ALL GREEN（启动链已恢复 v1.0 形态） ==')
