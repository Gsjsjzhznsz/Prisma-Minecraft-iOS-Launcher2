#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task483 门禁 —— 单根终局（命中 instances 的代码全部删除）+ FML 致命错可见化。

病历（装机 147a119 latestlog 2026-11-28 21:22 全文 694 行）：
  ① Task482-A flatten 打出 'Application Support/private/var/mobile/...' 废路
     （绝对符号链接目标被二次拼接）→ target-not-instances 跳过 = 拆链从未执行；
  ② Task226 每次 pre-init 把 lasm 链接重指 instances/default = 「程序自动重建
     instances」本体；Task479/481 把版本根发布到 instances/default = 「删
     instances 即丢数据」本体；
  ③ FML 12.0.8 FatalErrorReporting 把完整错误链只喂给桌面 Swing 模态弹窗
     （FatalErrorReporting.java:155 showErrorUsingSwing → JOptionPane）——iOS
     无显示面弹窗永不返回 = 「无法启动」挂死表象；原始 Error（Entrypoint
     catch(Exception) 不接 Error → 日志零 "Failed to start FML" 行）文本不可见。

A 线（main.m Task483 单根迁移七锚）：
  A1 迁移块 + marker + 完成锚日志行
  A2 instances 目录不再预建（dirsToCreate 无 instances 段）
  A3 Task316 调用 / Task226 re-point 行退役反锚
  A4 注册表绝对路径重写器（/instances/ 前缀 → lasm + .ame483 备份）
  A5 空壳直删 + 异常残余归档 instances_retired-
  A6 PCL 可见层布局保形（init_setupPCLLayout 在场）
  A7 一层整合包注册表遍重写
B 线（启动/功能链去 instances 十门）：
  B1 JavaLauncher flatten/Task331 退役反锚（Task473/ame287/481/482-B 保形）
  B2 ModService 版本轴形态守卫（versions 组件判据，instances 判据零在场）
  B3 ZL2VersionIndex 兜底扫描根 = POJAV_GAME_DIR
  B4 ZL2SettingPages options 全集扫描根 = POJAV_GAME_DIR
  B5 ModpackImportService 工作区根 = POJAV_GAME_DIR
  B6 AmePluginBridge profile 兜底 = lasm 字面段
  B7 AiFileTools / AiLogReader 兜底 = lasm 字面段
  B8 LauncherPrefGameDirViewController 单根化（真实根只读 + 零链接手术）
  B9 AiInstanceCreator 恒拒绝 + AiInstancesTool 单条目
  B10 i18n 四表键在（ame483.gamedir.single_root_hint + ai.instance.single_root_rejected）
C 线（FML 致命错可见化五门）：
  C1 补丁资源在场（JavaApp/libs/ame_patches/.../FatalErrorReporting.class.patch）
  C2 PatchSVC 表项 + fml_loader 12.0.8 版本守卫 + ENGAGED/SKIP 锚点
  C3 Makefile patchsvc.jar 打包步骤（cp libs/ame_patches → classes）
  C4 补丁源码在 patches_src（非 src 编译 glob）+ [FML-FATAL] 锚 + exit(1)
  C5 BuildTag 进代 Task483 · 2026-11-28 + FileLayoutService 迁移链删除反锚
用法: python3 scripts/task483_selfcheck.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def main():
    fails = []

    def check(name, ok, detail=''):
        if not ok:
            fails.append(f'{name}: {detail}')
        print(f'  {"OK  " if ok else "FAIL"} {name}' + ('' if ok else f' -- {detail}'))
        return ok

    mainm = rd('Natives/main.m')
    jl = rd('Natives/JavaLauncher.m')
    modsvc = rd('Natives/ModService.m')
    zidx = rd('Natives/ZL2VersionIndex.m')
    zpages = rd('Natives/ZL2SettingPages.m')
    impsvc = rd('Natives/ModpackImportService.m')
    bridge = rd('Natives/AmePluginBridge.m')
    ftools = rd('Natives/AI/AiFileTools.m')
    lreader = rd('Natives/AI/AiLogReader.m')
    icreator = rd('Natives/AI/AiInstanceCreator.m')
    itools = rd('Natives/AI/AiInstancesTool.m')
    prefvc = rd('Natives/LauncherPrefGameDirViewController.m')
    flsvc = rd('Natives/FileLayoutService.m')
    flsvc_h = rd('Natives/FileLayoutService.h')
    patchsvc = rd('JavaApp/src/patchsvc/com/congcq/patchsvc/PatchSVC.java')
    makefile = rd('JavaApp/Makefile')
    patch_src = rd('JavaApp/patches_src/net/neoforged/fml/startup/FatalErrorReporting.java')

    print('== A 线：main.m Task483 单根迁移 ==')
    check('A1 迁移块 + marker + 完成锚',
          '[Task483] single-root migration done' in mainm
          and '.ame483_single_root' in mainm
          and 'ame483_rewriteInstancesPrefixInProfiles' in mainm,
          'Task483 迁移块缺席')
    check('A2 instances 目录不再预建',
          'instances/%@' not in mainm
          and 'ame483' in mainm and 'dirsToCreate' in mainm
          and 'multidirPath' not in mainm,
          'main.m 仍有 instances 预建路径')
    check('A3 Task316 调用 / Task226 re-point 退役反锚',
          'ame316_migrateIfNeeded' not in mainm
          and 'Task226 game-dir symlink re-pointed' not in mainm
          and 'migrating into instances/' not in mainm,
          'Task316 调用或 Task226 re-point 残留')
    check('A4 注册表重写器（前缀重写 + 备份）',
          '"/instances/"' in mainm
          and 'NSBackwardsSearch' in mainm
          and '.ame483' in mainm,
          '注册表重写器缺席')
    check('A5 空壳直删 + 残余归档',
          'instances_retired-' in mainm
          and '空壳直删' in mainm,
          '空壳/归档策略缺席')
    check('A6 PCL 可见层布局保形',
          'void init_setupPCLLayout()' in mainm
          and 'Prisma2' in mainm,
          'PCL 布局被误删')
    check('A7 一层整合包注册表遍重写',
          'ame483_packReg' in mainm
          and 'launcher_profiles.json' in mainm,
          '整合包注册表遍缺席')

    print('== B 线：启动/功能链去 instances ==')
    check('B1 JavaLauncher flatten/Task331 退役反锚 + 保形',
          'ame482_flattenInstanceLink' not in jl
          and 'Task331' not in jl
          and 'ame287_configureForgeUriSafeRoot' in jl
          and 'ame481_locateVersionRootForHint' in jl
          and 'ame482_writeFmlEarlyDisplayConfig' in jl,
          'flatten/Task331 残留或保形块被误删')
    check('B2 ModService 形态守卫（versions 组件判据）',
          'ame327_vIdx != NSNotFound && ame327_vIdx > 0' in modsvc
          and 'isEqualToString:@"instances"' not in modsvc,
          'ModService 守卫未换代')
    check('B3 ZL2VersionIndex 扫描根 = POJAV_GAME_DIR',
          'getenv("POJAV_GAME_DIR")' in zidx
          and 'ame_scanInstancesTreeForVersionId' in zidx
          and 'getenv("POJAV_HOME")' not in zidx.split('ame_scanInstancesTreeForVersionId')[1].split('}', 1)[0],
          'ZL2VersionIndex 扫描根未换')
    check('B4 ZL2SettingPages options 扫描根 = POJAV_GAME_DIR',
          'ame229_allInstanceOptionsPaths' in zpages
          and 'getenv("POJAV_GAME_DIR")' in zpages
          and '%s/instances' not in zpages,
          'options 扫描根未换')
    check('B5 ModpackImportService 工作区根 = POJAV_GAME_DIR',
          'getenv("POJAV_GAME_DIR")' in impsvc
          and '@"instances"' not in impsvc,
          '整合包工作区根未换')
    check('B6 AmePluginBridge 兜底 = lasm',
          'Library/Application Support/minecraft' in bridge
          and '"instances/%@"' not in bridge,
          '插件桥兜底未换')
    check('B7 AiFileTools/AiLogReader 兜底 = lasm',
          'Library/Application Support/minecraft' in ftools
          and 'Library/Application Support/minecraft' in lreader
          and '%s/instances/%@' not in ftools
          and '%s/instances/%@' not in lreader,
          'AI 文件/日志工具兜底未换')
    check('B8 PrefVC 单根化（真实根只读 + 零链接手术）',
          'ame483_singleRoot' in prefvc
          and 'createSymbolicLinkAtPath' not in prefvc
          and 'removeItemAtPath:lasmPath' not in prefvc,
          'PrefVC 链接手术残留')
    check('B9 AiInstanceCreator 恒拒绝 + AiInstancesTool 单条目',
          'single_root_rejected' in icreator
          and '"instances/%@"' not in icreator
          and 'currentGameRoot' in itools
          and '@"instances"' not in itools,
          'AI 工具创建路径残留')
    check('B10 i18n 四表键在',
          all('ame483.gamedir.single_root_hint' in rd(f'Natives/resources/{l}.lproj/Localizable.strings')
              and 'ai.instance.single_root_rejected' in rd(f'Natives/resources/{l}.lproj/Localizable.strings')
              for l in ('en', 'zh-Hans', 'zh-CN', 'zh-Hant')),
          'i18n 键缺席')

    print('== C 线：FML 致命错可见化 ==')
    patch_bin = ROOT / 'JavaApp/libs/ame_patches/net/neoforged/fml/startup/FatalErrorReporting.class.patch'
    check('C1 补丁资源在场',
          patch_bin.is_file() and patch_bin.stat().st_size > 4000,
          f'补丁资源缺席或过小: {patch_bin}')
    check('C2 PatchSVC 表项 + 12.0.8 守卫 + 锚点',
          '"net/neoforged/fml/startup/FatalErrorReporting"' in patchsvc
          and 'fancymodloader/loader/12.0.8/loader-12.0.8.jar' in patchsvc
          and 'FML fatal-report patch ENGAGED' in patchsvc
          and 'FML fatal-report patch SKIP' in patchsvc,
          'PatchSVC 守卫/表项缺席')
    check('C3 Makefile 打包步骤',
          'ame_patches/net/neoforged/fml/startup/FatalErrorReporting.class.patch' in makefile
          and 'patchsvc.txt' in makefile,
          'Makefile 打包步骤缺席')
    check('C4 补丁源码 delta 锚（patches_src，非 src glob）',
          not (ROOT / 'JavaApp/src/patchsvc_extra').exists()
          and '[FML-FATAL]' in patch_src
          and 'System.exit(1);' in patch_src
          and 'showErrorUsingSwing(message);' not in patch_src.split('public static void reportFatalError(String message)')[1].split('}')[0],
          '补丁源码 delta 形态不符')
    flsvc_code = '\n'.join(l for l in flsvc.split('\n') if not l.lstrip().startswith('//'))
    flsvc_h_code = '\n'.join(l for l in flsvc_h.split('\n') if not l.lstrip().startswith('//'))
    check('C5 BuildTag 进代 + FileLayoutService 迁移链删除反锚（剥注释后判代码）',
          'Task483 · 2026-11-28' in rd('Natives/BuildTag.h')
          and 'ame316_migrateIfNeeded' not in flsvc_code
          and 'ame316_migrateInner' not in flsvc_code
          and 'fl_absorbIntoSharedCoreDir' not in flsvc_code
          and 'ame316_migrateIfNeeded' not in flsvc_h_code,
          'BuildTag 未进代或 FileLayoutService 迁移链残留')

    # 括号平衡（本轮编辑面全量）
    print('== D 线：括号平衡 ==')
    for name, txt in (('main.m', mainm), ('JavaLauncher.m', jl),
                      ('LauncherPrefGameDirViewController.m', prefvc),
                      ('AI/AiInstanceCreator.m', icreator), ('AI/AiInstancesTool.m', itools),
                      ('FileLayoutService.m', flsvc), ('ZL2SettingPages.m', zpages)):
        bal = txt.count('{') - txt.count('}')
        check(f'D 括号平衡 {name}', bal % 2 == 0, f'花括号差值 {bal}（奇数=必红）')

    print()
    if fails:
        print(f'Task483 selfcheck FAIL ({len(fails)}):')
        for f in fails:
            print('  -', f)
        return 1
    print('Task483 selfcheck ALL GREEN (A1-A7 + B1-B10 + C1-C5 + D)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
