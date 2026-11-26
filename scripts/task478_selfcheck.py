#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task478 门禁 —— 装机 88d96bc 一启动闪退根修 + MoltenVK 直呈首帧直显。

用户报告（latestlog.txt，构建 88d96bc = Task477-r3-r1 HEAD）：
  A) 一按启动闪退 'data parameter is nil'（Task287 日志行后即崩）：
     ame225 版本 JSON / 索引 JSON 与 ame471 inheritsFrom 父辈 JSON 三处
     裸调 JSONObjectWithData——Task473 版本隔离布局下路径必缺 → nil 抛。
  B) 「出现 mojang 就直接显示，而不是等到主界面加载完成」：MobileGL
     DirectVulkan 会话四路首帧信号全灭（装机日志 actualVulkanPath=0 实锚）
     → 遮罩干等 90s 超时兜底。

A 线（闪退根修三守卫）：
  A1 公共守卫件 ame478_jsonDictFromFile 在位且先于 ame225 定义
  A2 发射路径裸调清零（JSONObjectWithData 不得内联 dataWithContentsOfFile）
  A3 ame225 三层候选（经典 / 隔离 / 通配扫 *.json 探 assets 键）
  A4 ame471 versions 根双口径（ZL2GamePath gameHome 主根优先 + 经典回落）
     且 task471 A5 家族锚（guard<8 + 链合并三件）保全
B 线（首帧直显四锚）：
  B1 egl_bridge 独立出口（s_firstFrameRendered 一次性去重 + 通知发布）
  B2 utils.h 声明在位
  B3 GameSurfaceView nextDrawable 无条件调用（FPS 计数门不挪）
  B4 遮罩消费链保全（观察者注册 + onFirstFrameRendered + Task267 90s 兜底）
--selftest：负样本探针 ×2（剥守卫件 / 剥首帧出口调用——判定函数必须咬人）
用法: python3 scripts/task478_selfcheck.py [--selftest]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def strip_code(src):
    return re.sub(r'//[^"\n]*', '', src)


def run_checks(jl, eb, uh, gv, svc, tag=None):
    fails = []
    jl_code = strip_code(jl)

    def check(name, ok, detail=''):
        if not ok:
            fails.append(f"{name}: {detail}")

    # ── A 线 ──
    helper_idx = jl_code.find('static NSDictionary *ame478_jsonDictFromFile(NSString *path) {')
    check('A1 守卫件在位且先于 ame225',
          helper_idx != -1
          and helper_idx < jl_code.find('static int ame225_healMissingAssets(NSString *versionId) {'))

    bare = re.findall(r'JSONObjectWithData:\s*\[NSData dataWithContentsOfFile:', jl)
    check('A2 发射路径裸调清零', len(bare) == 0, f'残留 {len(bare)} 处')

    check('A3 ame225 三层候选',
          '[NSString stringWithFormat:@"versions/%@/%@", versionId, ame478_vidJson]' in jl_code
          and 'stringByAppendingPathExtension:@"json"' in jl_code
          and 'contentsOfDirectoryAtPath:ame478_dir' in jl_code
          and 'ame478_cand[@"assets"]' in jl_code)

    check('A4 ame471 根双口径 + 家族锚保全',
          '[ZL2GamePath gameHome], gameDir,' in jl_code
          and 'ame471_parent = ame478_jsonDictFromFile(ame471_parentPath);' in jl_code
          and 'ame471_guard++ < 8' in jl_code
          and 'ame471_versionChainFrom' in jl_code
          and 'ame471_mergedLibraries' in jl_code
          and 'ame471_collectMissing' in jl_code)

    # ── B 线 ──
    check('B1 egl_bridge 独立出口',
          'void pojavNotifyFirstFrameIfPending() {' in eb
          and 's_firstFrameRendered = YES;' in eb
          and 'postNotificationName:@"PojavFirstFrameRendered"' in eb.split(
              'void pojavNotifyFirstFrameIfPending() {', 1)[-1].split('}', 1)[0])

    check('B2 utils.h 声明在位', 'void pojavNotifyFirstFrameIfPending();' in uh)

    gv_after_if = gv.split('if (pojavIsActualVulkanPath()) {', 1)[-1]
    check('B3 nextDrawable 无条件调用 + FPS 门不挪',
          gv_after_if.count('pojavNotifyFirstFrameIfPending();') == 1
          and 'pojavIncrementFpsCounter();' in gv_after_if.split('pojavNotifyFirstFrameIfPending();', 1)[0])

    check('D1 BuildTag Task478 进代', tag is None or 'ame415_buildTag = @"Task480 · ' in tag)

    check('B4 遮罩消费链保全',
          'name:@"PojavFirstFrameRendered"' in svc
          and 'onFirstFrameRendered' in svc
          and 'launch overlay auto-dismissed after' in svc)

    return fails


def main():
    selftest = '--selftest' in sys.argv
    jl = rd('Natives/JavaLauncher.m')
    eb = rd('Natives/egl_bridge.m')
    uh = rd('Natives/utils.h')
    gv = rd('Natives/GameSurfaceView.m')
    svc = rd('Natives/SurfaceViewController.m')

    if not selftest:
        tag = rd('Natives/BuildTag.h')
        fails = run_checks(jl, eb, uh, gv, svc, tag=tag)
        if fails:
            print(f'[FAIL] task478_selfcheck {len(fails)} 项:')
            for f in fails:
                print('  -', f)
            return 1
        print('[PASS] task478_selfcheck: A/B 全绿（发射路径 JSON 三守卫 + MoltenVK 直呈首帧直显四锚）')
        return 0

    # ── selftest：负样本必须咬人 ──
    # 探针1：剥守卫件（helper 整段移除 + 调用点还原裸调形态）→ A1/A2/A3 必须红
    jl_mut = jl.replace('ame478_jsonDictFromFile(', 'ame478JsonDictFromFileStripped(')
    jl_mut = re.sub(r'\n?// ★Task478（装机 88d96bc 一启动闪退根修公共件）.*?\n\}\n\n',
                    '\n', jl_mut, count=1, flags=re.S)
    f1 = run_checks(jl_mut, eb, uh, gv, svc)
    p1 = any(f.startswith(('A1', 'A2', 'A3')) for f in f1)
    # 探针2：剥首帧出口调用 → B3 必须红
    gv_mut = gv.replace('    pojavNotifyFirstFrameIfPending();\n', '')
    f2 = run_checks(jl, eb, uh, gv_mut, svc)
    p2 = any(f.startswith('B3') for f in f2)

    if p1 and p2:
        print('[PASS] task478_selfcheck --selftest: 负样本双探针全咬人（剥守卫件 A 族红 / 剥首帧调用 B3 红）')
        return 0
    print(f'[FAIL] task478_selfcheck --selftest: 探针1({"咬人" if p1 else "漏判"}) 探针2({"咬人" if p2 else "漏判"})')
    return 1


if __name__ == '__main__':
    sys.exit(main())
