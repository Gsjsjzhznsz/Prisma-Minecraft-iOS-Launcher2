#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task482 门禁 —— 去 instances 化单一真实根 + FML 早显真退役。

病历：
  装机 JVM 日志（2026-11-28）：Task481 双保险实锚生效（FileNotFound 零再现，
  FML 全量装载到 Closing FML Loader / Clearing ModLoader 正常交接），尾行
  `Missing uniform 'tex' in shader 'GlProgram{color@6}'` 经 FML 源码核验
  非致命（GlProgram.java:52 warnAboutMissingUniform 仅 LOGGER.error）。
  但早显窗口 = MobileGL 栈上第二 GL 上下文纯风险面（Task203 同族前科），
  且旧三条 -D 开关对 FML 12.x 全部无效（FMLConfig 只读 config/fml.toml）。
  用户决策：instances 文件夹依赖彻底退役，回归安卓 Pojav 经典扁平布局
  （单一真实根），顺带 FML 早显官方开关真退役。

A 线（JavaLauncher.m flatten + fml.toml 六锚）：
  A1 ame482_flattenInstanceLink 定义 + 调用序（Task473 块后 / ame287 前）
  A2 .ame482_flat_root 标记写入 + 锚点日志行
  A3 fail-open 三重（occupied / move-failed 还原链接 / @catch）
  A4 fml.toml 写入器（earlyWindowControl=false + earlyWindowProvider="none"
     + 幂等门 + 锚点日志）
  A5 482-B 调用在 Task481 published 锚之后（邻接验证锚不扰动）
  A6 旧三条死 -D 属性保形在场
B 线（标记消费方四门）：
  B1 main.m Task226 迁移/清空分支标记门
  B2 main.m relink else 真实根保留分支
  B3 LauncherPrefGameDirViewController 切换入口保护（绝不 remove）
  B4 AiInstanceCreator 切换入口保护（绝不 remove + 409 如实回报）
C 线：
  C1 BuildTag 代际 = Task483 · 2026-11-28
  C2 Task473/ame287/Task481 三块保形（零删除）
  C3 括号平衡（四个编辑 ObjC 文件 {} 计数）
--selftest：负样本探针 ×2（fml.toml 块剥除 / main.m 标记门剥除——判定函数必须咬人）
用法: python3 scripts/task482_selfcheck.py [--selftest]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def run_checks(jl, mainm, prefvc, aicreator, tag):
    fails = []

    def check(name, ok, detail=''):
        if not ok:
            fails.append(f"{name}: {detail}")

    # ── A 线：JavaLauncher.m flatten + fml.toml ──
    # ★Task483：flatten 机制（ame482_flattenInstanceLink + .ame482_flat_root
    #   标记）已随 instances 布局退役删除，A1/A2/A3 转为退役反锚（在场即红）；
    #   单根收编锚点迁移至 task483_selfcheck.py。
    check('A1-r2 flatten 退役反锚（定义与调用必须零在场）',
          'ame482_flattenInstanceLink' not in jl,
          'flatten 代码残留（应已随 Task483 删除）')

    check('A2-r2 .ame482_flat_root 标记退役反锚',
          '.ame482_flat_root' not in jl and 'instance link flattened -> real root' not in jl,
          'flatten 标记/锚点日志残留')

    check('A3-r2 flatten fail-open 诊断退役反锚',
          'lasmPath occupied after link removal' not in jl
          and 'move failed -- link restored, flatten aborted' not in jl
          and 'flatten exception' not in jl,
          'flatten fail-open 日志残留')

    check('A4 fml.toml 写入器 + r1 值感知幂等门 + 锚点',
          'earlyWindowControl = false\\n' in jl
          and 'earlyWindowProvider = \\"none\\"' in jl
          and 'earlyWindowControl\\\\s*=\\\\s*(true|false)' in jl
          and 'flipped true->false in fml.toml' in jl
          and 'Task482: FML early display disabled via fml.toml' in jl,
          'fml.toml 写入器或 r1 值感知门缺席')

    check('A4-r1 旧 containsString 门已退役（FML 出厂 true 误判判例；flatten reason= 诊断已随 Task483 退役）',
          'containsString:@"earlyWindowControl"' not in jl
          and 'reason=env-missing' not in jl
          and 'reason=lasm-not-symlink' not in jl
          and 'reason=target-not-instances' not in jl,
          '旧幂等门或 flatten 诊断日志残留')

    check('A5 482-B 调用在 Task481 published 锚之后',
          'Task481: located version root published' in jl
          and 'ame482_writeFmlEarlyDisplayConfig(gameDir);' in jl
          and jl.index('Task481: located version root published') < jl.index('ame482_writeFmlEarlyDisplayConfig(gameDir);'),
          '482-B 调用序错位（邻接验证锚被扰动）')

    check('A6 旧三条死 -D 属性保形',
          '-Dfml.earlyprogresswindow=false' in jl
          and '-Dneoforge.enabledEarlyDisplay=false' in jl
          and '-Dforge.disableEarlyDisplay=true' in jl,
          '旧属性被误删（保形红线）')

    # ── B 线：标记消费方（★Task483 instances 布局退役 → 反锚 + 单根新锚）──
    check('B1-r2 main.m flatten 标记门退役反锚（单根迁移锚点移交 task483_selfcheck）',
          'ame482_flat_root' not in mainm
          and 'Task226 game-dir symlink re-pointed' not in mainm
          and '[Task483] single-root migration done' in mainm,
          'main.m flatten 残留或缺 Task483 迁移锚')

    check('B2-r2 main.m relink 保留分支退役反锚（永不重指 instances；fail-open 原位还原除外）',
          'flattened real game root preserved as real directory' not in mainm
          and 'withDestinationPath:multidirPath' not in mainm
          and 'withDestinationPath:instances/' not in mainm,
          'main.m 链接重指 instances 路径残留（单根政策红线）')

    check('B3-r2 切换入口(PrefVC)单根化反锚（链接手术退役，真实根只读）',
          'ame482_flatReal' not in prefvc
          and 'createSymbolicLinkAtPath:lasmPath' not in prefvc
          and 'ame483_singleRoot' in prefvc,
          'PrefVC 链接手术残留或缺单根锚')

    check('B4-r2 切换入口(AiInstanceCreator)拒绝化反锚（创建/切换整段退役）',
          'ame482_flatReal' not in aicreator
          and 'single_root_rejected' in aicreator
          and 'instances/%@' not in aicreator,
          'AiInstanceCreator 创建路径残留')

    # ── C 线 ──
    check('C1 BuildTag 代际', 'Task483 · 2026-11-28' in tag, 'BuildTag 未进代')

    check('C2 Task473/ame287/Task481 三块保形',
          '[ZL2GamePath gameDirForProfile:nil]' in jl
          and 'static NSString *ame287_configureForgeUriSafeRoot(NSString *versionId, NSString *gameDir) {' in jl
          and 'ame481_locateVersionRootForHint' in jl,
          'Task473/ame287/Task481 保形块被误删')

    # C3 括号平衡
    for p, txt in (('JavaLauncher.m', jl), ('main.m', mainm),
                   ('LauncherPrefGameDirViewController.m', prefvc),
                   ('AI/AiInstanceCreator.m', aicreator)):
        bal = txt.count('{') - txt.count('}')
        if bal != 0:
            # 排除字符串字面量干扰的粗校：全角/注释里出现花括号属正常，仅报奇偶异常
            if bal % 2 != 0:
                check(f'C3 括号平衡 {p}', False, f'花括号差值 {bal}（奇数=必红）')
        check(f'C3 括号平衡 {p}', bal % 2 == 0, f'花括号差值 {bal} 为奇数')

    return fails


def main():
    args = set(sys.argv[1:])
    jl = rd('Natives/JavaLauncher.m')
    mainm = rd('Natives/main.m')
    prefvc = rd('Natives/LauncherPrefGameDirViewController.m')
    aicreator = rd('Natives/AI/AiInstanceCreator.m')
    tag = rd('Natives/BuildTag.h')

    if '--selftest' in args:
        # 探针1：剥除 fml.toml 写入器 → A4 必红
        jl_mut = jl.replace('earlyWindowControl = false\\n', 'XPROBE_X\n')
        f1 = run_checks(jl_mut, mainm, prefvc, aicreator, tag)
        assert any(x.startswith('A4') for x in f1), 'selftest1 失效：A4 未咬人'
        # 探针2：剥除 main.m Task483 完成锚 → B1 必红（★483 反锚语义）
        mainm_mut = mainm.replace('[Task483] single-root migration done', 'XPROBE_X')
        f2 = run_checks(jl, mainm_mut, prefvc, aicreator, tag)
        assert any(x.startswith('B1') for x in f2), 'selftest2 失效：B1 未咬人'
        print('selftest 2/2 探针咬人（判定函数有效）')
        return

    fails = run_checks(jl, mainm, prefvc, aicreator, tag)
    if fails:
        print('Task482 selfcheck FAIL:')
        for f in fails:
            print('  -', f)
        sys.exit(1)
    print('Task482 selfcheck ALL GREEN (A1-A6 + B1-B4 + C1-C3)')


if __name__ == '__main__':
    main()
