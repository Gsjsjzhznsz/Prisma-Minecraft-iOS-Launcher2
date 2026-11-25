#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task379 门禁 —— ★Task477 整门重锚：导航合并退役反转执法。

用户钦定「保留二代侧边栏，删除其他2代」定谳：
  一代 ame347 NavigationView 抽屉 pane + 二代 ame411 右上悬浮簇全量清场，
  bare 唯一骨架；主页 rail 二代（Task475/476 ZL2 图标 rail）= 全局唯一切换器。
  本门由「窗格头行容器在位执法」翻转为「退役零残留 + bare 存量 + 令牌链保留」
  双向执法（Task472 隔离退役反转同款家法）。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8')


def strip_code(src):
    return re.sub(r'//[^"\n]*', '', src)


def main():
    shell = rd('Natives/ZL2ShellViewController.m')
    shell_code = strip_code(shell)
    preview_code = strip_code(rd('Natives/Preview/AmeFluentPreviewMain.m'))
    theme = rd('Natives/ZL2Theme.m')

    fails = []

    def check(name, ok):
        print(('PASS ' if ok else 'FAIL ') + name)
        if not ok:
            fails.append(name)

    # ── A 线：一代抽屉退役零残留（剥注释代码面）──
    check('A1 一代抽屉窗格零残留（paneWrap/paneStack/paneToggle/ame379_paneHeader/ame389_ 指示条族）',
          all(sym not in shell_code for sym in (
              'paneWrap', 'paneTitle', 'paneScroll', 'paneStack', 'paneFooterStack',
              'paneToggleButton', 'ame379_paneHeader', 'ame389_slideIndicator',
              'ame389_indicatorY', 'ame388_toggleLeading', 'dimOverlay',
              'navItems', 'hamburgerButton', 'navBackButton',
              'ame376_applyPaneGeometry', 'ame347_applyDrawerGeometry',
              'ame_setDrawerOpen', 'ame_buildNavigationViewShell',
              'ZL2ShellNavItem')))
    check('A2 二代簇退役零残留（ame411_ 三件 + ZL2ShellSwitcherButton/IconButton 类）',
          all(sym not in shell_code for sym in (
              'ame411_', 'ZL2ShellSwitcherButton', 'ZL2ShellIconButton')))

    # ── B 线：bare 唯一骨架存量 ──
    check('B1 bare 壳唯一骨架（构建器在位 + viewDidLoad 唯一分发 + 令牌退役日志）',
          '[self ame_buildBareShell];' in shell_code
          and 'bare shell enforced' in shell_code
          and 'ame_buildNavigationViewShell' not in shell_code)
    check('B2 令牌链保留（插件 API 面零触碰：ZL2Theme getter + 壳 navMode 读数）',
          '+ (NSString *)ame347_shellLayout {' in theme
          and 'self.ame347_navMode = [[ZL2Theme ame347_shellLayout]' in shell_code)
    check('B3 预览镜像同步退役（capsule/nav 镜像零残留 = 与真壳同truth）',
          all(sym not in preview_code for sym in (
              'ame414_buildCapsule', 'ame414_buildNavPane', 'capsuleCluster',
              'paneItems', 'ame414_navShell', 'ame416_paneExpanded')))
    check('B4 taskPill 刷新链锚表达式保留（(self.topBar ?: self.contentHeader) 契约）',
          '(self.topBar ?: self.contentHeader)' in shell_code)

    if fails:
        print(f'ame379_selfcheck: {len(fails)} FAIL -> ' + '; '.join(fails))
        return 1
    print('ame379_selfcheck: ALL PASS（一代/二代退役零残留 + bare 唯一骨架 + 令牌链保留）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
