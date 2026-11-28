#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task479 门禁 —— f03e3c9 双装机日志定谳修复双面门。

用户报告「问题依旧」（latestlog.old.txt + latestlog.txt，构建 f03e3c9）：
  A) NeoForge 会话仍闪退 'data parameter is nil'：Task478 三守卫后崩点下移
     —— Task428 preLaunchCheck 的 resolveContext（586 行）先于 orderly 日志
     （595 行）执行，其中版本 JSON 263 / inheritsFrom 父辈 276 / assets 索引
     461 三处裸调 JSONObjectWithData。根机制 = ame287 把 POJAV_GAME_DIR 换到
     $POJAV_HOME/.ame287_forge_root（符号链接 → 隔离 gameDir），ame353 祖先
     链探测不解符号链接 → miss → 版本根回退 alias → 双层嵌套路径必缺 → nil
     抛（崩前零 Task428 日志 = 时序实锚）。Fabric 会话无 alias、祖先链自隔离
     目录上溯命中共享根 → 全程无雷（双日志差分定性）。
  B) Fabric 会话进游戏后崩 renderpearl GlDevice.createBuffer（crash report
     实锚 Graphics Device = GL4ES wrapper）：Task217 auto 链 libMobileGL
     'dylib missing from bundle'——Task475 出包后 renderer-repo 插件为可选
     下载、用户未装 → 现代 MC（1.17+ MobileGL 基线，Task144）开箱即崩。

A 线（裸调清雷 + 根自纠）：
  A1 helper 三件套在位且先于消费点（候选根序列/定位/数据出口）
  A2 PLGameIntegrityService 裸调清零
  A3 三守卫位（版本 JSON / 父辈 / assets 索引）
  A4 根自纠块 + relocated 装机日志锚
  A5 ForgeProcessorExecutor 同族一卫 + 裸调清零
B 线（vendored MobileGL 回植）：
  B1 vendored dylib 16447088B（Witch fork 8df5508）在场 + PROVENANCE 在场
  B2 task435 S4b 翻转为在场锚（builtin-renderers 出包锚保留）
C 线（代际 + 通道）：
  C1 BuildTag Task482 · 2026-11-28 进代
  C2 renderer-repo 在线插件通道保留（index.json + 插件包在场）
--selftest：负样本 ×2（剥根自纠消费点 / 剥 dylib——判定函数必须咬人）
用法: python3 scripts/task479_selfcheck.py [--selftest]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BARE = re.compile(r'JSONObjectWithData:\s*\[NSData\s+dataWithContentsOfFile')


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def strip_code(src):
    return re.sub(r'//[^"\n]*', '', src)


def run_checks(svc, fpe, tag, audit435, dylib_size, prov_exists, repo_ok):
    fails = []
    svc_code = strip_code(svc)
    fpe_code = strip_code(fpe)

    def check(name, ok, detail=''):
        if not ok:
            fails.append(f"{name}: {detail}")

    # ── A 线 ──
    c1 = svc_code.find('static NSArray<NSString *> *Ame428VersionRootCandidates(NSString *hint, NSString *vid) {')
    c2 = svc_code.find('static NSString *Ame428LocateVersionRoot(NSString *hint, NSString *vid) {')
    c3 = svc_code.find('static NSData *Ame428VersionJSONData(NSString *root, NSString *vid) {')
    u1 = svc_code.find('Ame428LocateVersionRoot(versionRoot, versionId)')
    check('A1 helper 三件套在位且先于消费点', -1 < c1 < c2 < c3 < u1,
          f'c1={c1} c2={c2} c3={c3} u1={u1}')
    check('A2 PLGameIntegrityService 裸调清零', not BARE.search(svc_code))
    check('A3a 版本 JSON 守卫（ame479_vd）', 'ame479_vd.length > 0' in svc_code)
    check('A3b 父辈守卫（ame479_pd）', 'ame479_pd.length > 0' in svc_code)
    check('A3c 索引守卫（ame479_ixd）', 'ame479_ixd.length > 0' in svc_code)
    check('A4 根自纠块 + relocated 装机锚',
          'Task479: version root relocated' in svc
          and u1 != -1)
    check('A5 ForgeProcExec 守卫 + 裸调清零',
          'ame479_ed.length > 0' in fpe_code and not BARE.search(fpe_code))

    # ── B 线 ──
    check('B1 vendored dylib 16447088B 在场', dylib_size == 16447088, f'size={dylib_size}')
    check('B1b PROVENANCE 在场', prov_exists)
    check('B2 task435 在场翻转（builtin-renderers 出包锚保留）',
          'Task479 回植' in audit435
          and 'libMobileGL.dylib 已出包' not in audit435
          and 'builtin-renderers' in audit435)

    # ── C 线 ──
    check('C1 BuildTag Task479 进代',
          'Task482 · 2026-11-28' in tag and 'Task478 · 2026-11-26' not in tag)
    check('C2 renderer-repo 插件通道保留', repo_ok)
    return fails


def main():
    selftest = '--selftest' in sys.argv
    svc = rd('Natives/PLGameIntegrityService.m')
    fpe = rd('Natives/installer/ForgeProcessorExecutor.m')
    tag = rd('Natives/BuildTag.h')
    audit435 = rd('scripts/task435_renderer_hook_audit.py')
    dy = ROOT / 'Natives/resources/Frameworks/libMobileGL.dylib'
    pv = ROOT / 'Natives/resources/Frameworks/libMobileGL.PROVENANCE.md'
    dylib_size = dy.stat().st_size if dy.exists() else -1
    prov_exists = pv.exists()
    repo_ok = (ROOT / 'renderer-repo/index.json').exists() \
        and (ROOT / 'renderer-repo/plugins/mobileglues-dev-1.0.0.zip').exists()

    if selftest:
        f1 = run_checks(svc.replace('Ame428LocateVersionRoot(versionRoot, versionId)',
                                    'AME479_STRIPPED(versionRoot, versionId)'),
                        fpe, tag, audit435, dylib_size, prov_exists, repo_ok)
        f2 = run_checks(svc, fpe, tag, audit435, -1, prov_exists, repo_ok)
        joined = ('|'.join(f1) + '|' + '|'.join(f2))
        ok = f1 and f2 and 'A1' in joined and 'B1' in joined
        print('selftest 负样本 ×2:', 'PASS（门咬人）' if ok else f'FAIL {f1} {f2}')
        sys.exit(0 if ok else 1)

    fails = run_checks(svc, fpe, tag, audit435, dylib_size, prov_exists, repo_ok)
    for f in fails:
        print('FAIL', f)
    print(f"task479_selfcheck: {'ALL GREEN' if not fails else str(len(fails)) + ' FAIL'} (11 checks)")
    sys.exit(0 if not fails else 1)


if __name__ == '__main__':
    main()
