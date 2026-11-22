#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task467 自检门 —— 双线轮：
A 线（启动链 srg 保环）：装机 ffb71a0 latestlog 实锤——JIT/dyld 链修复后 FML
  首次真达模组加载即死于 "Failed to find required file .../client-26.3-1-srg.jar"
  → FML 视角 minecraft/neoforge 双未安装 → 28 条模组依赖全 [MISSING] →
  ModLoadingException 致命错误屏 exit(1)。根因：SRG/PATCHED/EXTRA 三类
  processor 本地产物（官方 maven 从不发布）在 Modrinth 版本 json 写入路径
  天然缺失，而一号门 ame158 与 Task428 完整性服务对无 downloads URL 条目
  双双跳过/不修 = 结构性盲区。修法：ame158 门 BOOL 化 + ame467 三层保环
  （Tier A 搁浅回收 / Tier B processor 自愈+ame173 重启链 / Tier C 指引弹窗）。
B 线（欢迎UI恢复）：用户指令「把欢迎UI重新恢复」——Task436 A3 断链判例翻转
  （Task463 折叠翻转型家法）：WelcomeViewController.h/.m 自 Task439 批次一
  删除态回注（5231bf0c7^ 逐字节）+ SceneDelegate 0.8s 呈现位回填 +
  PLPreferences welcome_completed 哨兵键回注 + AiPluginDocsTool 文档面回册。
惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
"""
import glob
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

def exists(rel):
    return os.path.exists(os.path.join(REPO, rel))

jl = read('Natives/JavaLauncher.m')
sd = read('Natives/SceneDelegate.m')
cm = read('Natives/CMakeLists.txt')
plp = read('Natives/PLPreferences.m')
docs = read('Natives/AI/AiPluginDocsTool.m')
tag_h = read('Natives/BuildTag.h')

# ── R 线：欢迎UI恢复面 ─────────────────────────────────────────
check('R1 WelcomeViewController.h 回注且含便捷入口声明',
      exists('Natives/WelcomeViewController.h')
      and 'presentIfNeededFromViewController:' in read('Natives/WelcomeViewController.h'),
      '头文件缺失或入口声明丢失')
wvm = read('Natives/WelcomeViewController.m')
check('R2 WelcomeViewController.m 回注（2249 行体量 + CoachMarks 依赖在位）',
      exists('Natives/WelcomeViewController.m')
      and wvm.count('\n') > 2000
      and '#import "Ame223CoachMarksView.h"' in wvm,
      '正文缺失或依赖面残缺')
check('R3 CMakeLists 注册 WelcomeViewController.m（Task467 注释锚在场）',
      '\n  WelcomeViewController.m' in cm and 'Task467（欢迎UI恢复轮）' in cm,
      'CMake 注册缺失')
check('R4 SceneDelegate import + 0.8s 呈现位回填',
      '#import "WelcomeViewController.h"' in sd
      and '[WelcomeViewController presentIfNeededFromViewController:rootVC];' in sd
      and '0.8 * NSEC_PER_SEC' in sd,
      'SceneDelegate 呈现链残缺')
check('R5 PLPreferences welcome_completed 哨兵键回注（默认 @NO）',
      '@"welcome_completed": @NO,' in plp and 'Task467（欢迎UI恢复轮）' in plp,
      '哨兵键未回注')
check('R6 AiPluginDocsTool 文档面回册（general.welcome_completed 行 + Task467 注记）',
      'general.welcome_completed（默认 @NO）' in docs and '★Task467 回注 welcome_completed' in docs,
      '文档面漂移')
check('R7 欢迎 present 点全仓唯一（SceneDelegate 0.8s 位）',
      sum(open(f, encoding='utf-8').read().count(
          '[WelcomeViewController presentIfNeededFromViewController')
          for f in glob.glob(os.path.join(REPO, 'Natives', '**', '*.m'), recursive=True)
          if os.path.basename(f) != 'WelcomeViewController.m') == 1,
      'present 点漂移（应恰 1 处）')

# ── R 线：启动链 srg 保环面 ────────────────────────────────────
check('R8 ame158 门 BOOL 化（空表/无环境早退双 return YES + 签名 static BOOL）',
      'static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget) {' in jl
      and jl.count('if (ame158_libs.count == 0) return YES;') == 1
      and 'if (!ame158_gameDir || !*ame158_gameDir) return YES;' in jl,
      '门签名/早退形态漂移')
check('R9 ame467 六件 statics 齐备（relPath/isNeoForge/missingCollect/stranded/heal/dialog）',
      all(s in jl for s in (
          'static NSString *ame467_mavenNameToRelPath(',
          'static BOOL ame467_isNeoForgeTarget(',
          'static NSArray<NSDictionary *> *ame467_missingProcessorArtifacts(',
          'static NSUInteger ame467_strandedRecovery(',
          'static BOOL ame467_runProcessorHeal(',
          'static void ame467_presentMissingArtifactDialog(',
          'static BOOL ame467_processorArtifactRescue(')),
      '保环 statics 缺件')
check('R10 classifier 三类收窄 + 无 URL 收集语义（srg/client/extra 恰一组）',
      jl.count('![ame467_classifier isEqualToString:@"srg"]') == 1
      and jl.count('![ame467_classifier isEqualToString:@"client"]') == 1
      and jl.count('![ame467_classifier isEqualToString:@"extra"]') == 1
      and 'ame467_seg.count != 4' in jl,
      'classifier 收窄面漂移')
check('R11 Tier B processor 自愈四件（jvmUsed 防御 + installer URL 同源 + 工具链预下载 + 产物验证）',
      'if ([ForgeProcessorExecutor jvmUsedThisProcess]) {' in jl
      and 'https://maven.neoforged.net/releases/net/neoforged/neoforge/%@/neoforge-%@-installer.jar' in jl
      and 'toolchain libraries fetched=' in jl
      and 'post-heal verification FAILED:' in jl,
      'Tier B 链残缺')
check('R12 Tier B 成功收束复用 ame173 重启链（进程内 JVM 单次约束）',
      'ame173_showJvmUsedRestartDialog(PLProfiles.current.selectedProfileName ?: @"")' in jl
      and 'return NO;   // 进程内 headless JVM 已创建——本进程不得再进游戏 JVM' in jl,
      '重启收束链漂移')
check('R13 Tier C 指引弹窗双 i18n 键在位',
      'i18n_str_ame467_srg_missing_title' in jl and 'i18n_str_ame467_srg_missing' in jl,
      'Tier C 弹窗键缺失')
check('R14 调用点中断语义（!gate → return 1，不进 JIT 等待）',
      'if (!ame158_repairMissingLibraries(launchTarget)) {' in jl
      and jl.find('if (!ame158_repairMissingLibraries(launchTarget)) {') < jl.find('ame158_repairMissingLibraries(launchTarget);') if 'ame158_repairMissingLibraries(launchTarget);' in jl else True,
      '调用点仍为旧 void 调用')
check('R15 原版/Fabric 零触碰（保环主入口 NeoForge 早退）',
      'if (!ame467_isNeoForgeTarget(launchTarget)) return YES;   // 原版/Fabric 零触碰' in jl,
      '早退面漂移')
check('R16 UZKArchive/Executor 双导入在位',
      '#import "external/UnzipKit/UZKArchive.h"' in jl
      and '#import "installer/ForgeProcessorExecutor.h"' in jl,
      '导入缺失')

# ── i18n / 代际 / 电池 ─────────────────────────────────────────
tables = glob.glob(os.path.join(REPO, 'Natives', 'resources', '*.lproj', 'Localizable.strings'))
check('R17 i18n 双键 54 表同步',
      len(tables) == 54
      and all('i18n_str_ame467_srg_missing_title' in open(t, encoding='utf-8').read()
              and 'i18n_str_ame467_srg_missing' in open(t, encoding='utf-8').read()
              for t in tables),
      f'表数 {len(tables)} 或键覆盖不全')
check('R18 verify219 J 锚 4350 重锚',
      'len(keys) == 4350' in read('scripts/verify_task219.py'),
      'J 锚未重锚')
check('S1 BuildTag 代际锚 Task469 · 2026-11-23',
      'ame415_buildTag = @"Task469 · 2026-11-23"' in tag_h,
      'BuildTag 未重锚')
check('S2 电池登记 task467（声明即实跑）',
      'task467' in read('scripts/task432_gate_battery.sh'),
      '电池未登记')

# ── X 线：锁定面零污染 ────────────────────────────────────────
check('X1 Task439 批次一退役六件保持退役（仅 Welcome 翻转）',
      all(not exists(p) for p in (
          'Natives/AccountLoginViewController.m',
          'Natives/AssetVersionViewController.m',
          'Natives/ModVersionViewController.m',
          'Natives/ProfileSettingsViewController.m',
          'Natives/ShaderVersionViewController.m',
          'Natives/installer/FabricInstallViewController.m')),
      '退役面被误恢复')
check('X2 Task465 v1.0 启动链形态零触碰（拦截截面仍退役 + 恢复面五锚在场）',
      'ame437_selfVerifyJit26Channel' not in jl
      and 'ame451_preflightJit26Channel' not in jl
      and 'i18n_str_ame457_dyldhook' not in jl
      and 'ame304_requestAndAwaitJITIfNeeded(@"Launch")' in jl
      and 'ame301_createRegionWithWatchdog()' in jl
      and 'Task342 probe region' in jl,
      'dyld 链面被本轮触碰')
check('X3 Task466 metallum 条件排除保持恰 1 处',
      'if (!ame466_metallumAgentMounted && [libFile isEqualToString:@"metallum_agent.jar"]) continue;' in jl,
      'Task466 条件面被本轮破坏')
check('X4 JavaLauncher.m 花括号平衡',
      jl.count('{') == jl.count('}'),
      f'括号不平衡 {{={jl.count("{")} }}={jl.count("}")}')

# ── selftest：反向探针 ──────────────────────────────────────────
if '--selftest' in sys.argv:
    print('== task467 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-R9: 保环主入口被摘（rescue 链断 = 回归盲区）→ R9 探针必翻红
    inj = jl.replace('static BOOL ame467_processorArtifactRescue(', 'static BOOL ame467_disabledRescue(')
    probe = all(s in inj for s in (
        'static NSString *ame467_mavenNameToRelPath(',
        'static BOOL ame467_processorArtifactRescue('))
    if not probe:
        print('ok  S-R9 反向：保环主入口改名 -> FAIL（符合预期）')
    else:
        print('S-R9 未翻红（保环探针失效）'); bad += 1
    # S-R4: SceneDelegate 呈现位被摘（Task436 断链复刻）→ R4 探针必翻红
    inj_sd = sd.replace('[WelcomeViewController presentIfNeededFromViewController:rootVC];', '')
    probe2 = '[WelcomeViewController presentIfNeededFromViewController:rootVC];' in inj_sd
    if not probe2:
        print('ok  S-R4 反向：呈现位摘除 -> FAIL（符合预期）')
    else:
        print('S-R4 未翻红（呈现位探针失效）'); bad += 1
    print(f'selftest: {"FAIL " + str(bad) + " probes failed to trigger" if bad else "2/2 反向探针全翻红"}')
    sys.exit(1 if bad else 0)

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
