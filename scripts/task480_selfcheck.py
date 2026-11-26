#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task480 门禁 —— 第五雷：Task473 隔离布局 × ame287 forge alias 的 JVM 内
Java 层经典布局假设（f9c9205 装机 latestlog = mclo.gs/yslnZnW 实锚）。

病历：
  原生三层守卫（Task478 ame225/ame471/索引 + Task479 resolveContext helper
  三件套 + 根自纠 relocation）全部生效后，崩点下移到 JVM 内 Java 层：
    Tools.getVersionInfo:926 read(DIR_HOME_VERSION/<vid>/<vid>.json)
    DIR_HOME_VERSION = POJAV_GAME_DIR/versions
    = .ame287_forge_root/versions/<vid>/<vid>.json（alias → 隔离版本目录本身）
    → 双层嵌套必缺 → FileNotFoundException → RuntimeException → exit(1)。
  Fabric 会话不触发 ame287（env 保持共享根）→ 同代码一崩一通 = Task479 判例同族。

A 线（JavaApp/Tools.java 几何候选五锚）：
  A1 ame480_versionMetaCandidates 在场 + vid 防注入（/ \\ .. 拒收）
  A2 926 自读换口 ame480_readVersionJson(versionName)（旧拼串退场）
  A3 930 父读换口 ame480_readVersionJson(customVer.inheritsFrom)（旧拼串退场）
  A4 809 客户端 jar 换口 ame480_clientJarPath(info.id)（旧拼串退场）
  A5 473/476 assets 换口 ame480_assetsPath() ×2（旧 Tools.ASSETS_PATH 退场）
  A6 几何候选三口径（经典 env / CWD 直卧 / versions 兄弟 + 共享根回潮）
  A7 全候选落空回落经典读（Task173 报错语义保全）
B 线（原生侧同家法两锚）：
  B1 ame471 roots 几何共享根候选（resolveSymlinks + 上提两级 + addObject）
  B2 BuildTag 代际 = Task480 · 2026-11-27
C 线（隔离语义保形）：
  C1 game_directory 仍 = gameDir（CWD/隔离不回退）+ DIR_GAME_PROFILE 消费在位
--selftest：负样本探针 ×2（自读换口回退 / ame471 共享根块剥除——判定函数必须咬人）
用法: python3 scripts/task480_selfcheck.py [--selftest]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def run_checks(tools, jl, tag):
    fails = []

    def check(name, ok, detail=''):
        if not ok:
            fails.append(f"{name}: {detail}")

    # ── A 线：Tools.java 几何候选 ──
    check('A1 ame480_versionMetaCandidates 在场 + vid 防注入',
          'private static List<String> ame480_versionMetaCandidates(String vid, String ext) {' in tools
          and 'vid.contains("/")' in tools
          and 'vid.contains("..")' in tools,
          'helper 或防注入三连缺席')

    check('A2 926 自读换口',
          'ame480_readVersionJson(versionName)' in tools
          and 'read(DIR_HOME_VERSION + "/" + versionName' not in tools,
          '自读换口缺席或旧拼串残留')

    check('A3 930 父读换口',
          'ame480_readVersionJson(customVer.inheritsFrom)' in tools
          and 'read(DIR_HOME_VERSION + "/" + customVer.inheritsFrom' not in tools,
          '父读换口缺席或旧拼串残留')

    check('A4 809 客户端 jar 换口',
          'libStr.append(ame480_clientJarPath(info.id));' in tools
          and 'libStr.append(DIR_HOME_VERSION + "/" + info.id' not in tools,
          'jar 换口缺席或旧拼串残留')

    check('A5 473/476 assets 换口 ×2',
          'varArgMap.put("assets_root", ame480_assetsPath());' in tools
          and 'varArgMap.put("game_assets", ame480_assetsPath());' in tools
          and 'varArgMap.put("assets_root", Tools.ASSETS_PATH);' not in tools
          and 'varArgMap.put("game_assets", Tools.ASSETS_PATH);' not in tools,
          'assets 换口缺席或旧拼串残留')

    check('A6 几何候选三口径（经典 env / CWD 直卧 / 兄弟位 + 共享根回潮）',
          'out.add(DIR_HOME_VERSION + "/" + vid + "/" + ame480_file);' in tools
          and 'new File(DIR_GAME_PROFILE, ame480_file).getAbsolutePath()' in tools
          and '"versions".equals(ame480_versionsDir.getName())' in tools
          and 'new File(ame480_shared, "versions/" + vid + "/" + ame480_file).getAbsolutePath()' in tools,
          '几何三口径缺席')

    check('A7 全候选落空回落经典读（Task173 报错语义保全）',
          tools.count('return read(DIR_HOME_VERSION + "/" + vid + "/" + vid + ".json");') == 1,
          f"fallback 出场 {tools.count('return read(DIR_HOME_VERSION + \"/\" + vid + \"/\" + vid + \".json\");')} 次（期望恰 1）")

    # ── B 线：原生侧 ──
    check('B1 ame471 roots 几何共享根候选（标识符交叉核对）',
          'NSMutableArray<NSString *> *ame471_roots = [NSMutableArray arrayWithArray:@[' in jl
          and 'NSString *ame480_real = [gameDir stringByResolvingSymlinksInPath];' in jl
          and '[[ame480_versions lastPathComponent] isEqualToString:@"versions"]' in jl
          and '![ame471_roots containsObject:ame480_shared]' in jl
          and '[ame471_roots addObject:ame480_shared];' in jl
          and 'ame480_roots' not in jl,
          'ame471 共享根候选块缺席或 ame480_roots 幽灵标识符残留（CI r0 实锚：锚串须与声明名交叉核对）')

    check('B2 BuildTag 代际 = Task480 · 2026-11-27',
          'ame415_buildTag = @"Task480 · 2026-11-27"' in tag,
          'BuildTag 未进代')

    # ── C 线：隔离语义保形 ──
    check('C1 game_directory 隔离口径不动 + DIR_GAME_PROFILE 消费在位',
          'varArgMap.put("game_directory", gameDir.getAbsolutePath());' in tools
          and 'new File(DIR_GAME_PROFILE)' in tools,
          'game_directory 或 DIR_GAME_PROFILE 消费缺席')

    return fails


def selftest():
    """负样本探针 ×2：判定函数必须咬人。"""
    tools = rd('JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java')
    jl = rd('Natives/JavaLauncher.m')
    tag = rd('Natives/BuildTag.h')

    # 探针 1：自读换口回退（模拟旧 926 拼串回归）
    probe1 = tools.replace(
        'Tools.GLOBAL_GSON.fromJson(ame480_readVersionJson(versionName)',
        'Tools.GLOBAL_GSON.fromJson(read(DIR_HOME_VERSION + "/" + versionName + "/" + versionName + ".json")')
    f1 = run_checks(probe1, jl, tag)
    if any(f.startswith('A2') for f in f1):
        print('probe1 A2 回退探针 咬人 OK')
    else:
        print('probe1 探针未咬人（A2 判定失效）'); return 1

    # 探针 2：ame471 共享根块剥除（含幽灵标识符注入负样本）
    probe2 = jl.replace('[ame471_roots addObject:ame480_shared];', '/*ame480-probe*/;')
    f2 = run_checks(tools, probe2, tag)
    if any(f.startswith('B1') for f in f2):
        print('probe2 ame471 共享根剥除探针 咬人 OK')
    else:
        print('probe2 探针未咬人（B1 判定失效）'); return 1

    print('task480_selftest ALL PASS（2 探针全咬）')
    return 0


def main():
    if '--selftest' in sys.argv:
        return selftest()

    tools = rd('JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java')
    jl = rd('Natives/JavaLauncher.m')
    tag = rd('Natives/BuildTag.h')
    fails = run_checks(tools, jl, tag)

    if fails:
        print(f'task480_selfcheck RED —— {len(fails)} 项：')
        for f in fails:
            print(f'  [FAIL] {f}')
        return 1
    print('task480_selfcheck ALL GREEN（A1-A7 + B1-B2 + C1，10 锚）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
