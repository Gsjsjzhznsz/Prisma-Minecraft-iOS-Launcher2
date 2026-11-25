#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task477 门禁新立 —— 导航合并退役 + 主页三代形态 + 渲染器卸载三面。

用户钦定（2026-11-25）：「保留二代侧边栏，删除其他2代。那三代的位置放我们
第一个预发行版本的侧边栏！设置里面的转盘侧边栏保留。」

A 线（导航合并退役）：
  A1 壳层一代/二代零残留（ame411_ 簇 + 抽屉 pane 禁符表，剥注释代码面）
  A2 bare 唯一骨架 + 347 令牌链保留（插件 API 面零触碰）
  A3 预览镜像同步退役（capsule/nav 镜像零残留）
B 线（主页三代形态 = v1.0「Prisma 2 Beta」单卡移植）：
  B1 三态分发器（ame477_styleIndex + beta 降级防线 + 形态旗）
  B2 三代忠实锚（surfaceBright 单卡 + v1.0 代常量逐位 + 八枚标签 ivar 回册）
  B3 刷新链分流（account/version 双入口 beta 早退 + v1.0 刷新器在位）
  B4 设置页三选项（0=rail 默认/1=转盘/2=三代 + clamp 0..2）
  B5 宽度分支（beta 走转盘 clamp + rail 88/104 字面量保留）
C 线（渲染器卸载三面 + 徽标）：
  C1 卸载钮（渲染器仓库页已装行 style4 + 插件仓库渲染器区 installed→卸载）
  C2 卸载链（ZL2M3Dialog destructive 确认 + uninstallRendererPlugin ×2 面）
  C3 徽标（badge_plugin/badge_builtin + rendererChoiceOverrides 影子调用）
  C4 i18n（zh-CN/en 四键在场）
D 线（代际）：
  D1 BuildTag Task477 进代
--selftest：负样本探针 ×2（剥三代构建器 / 剥卸载 handler ——判定函数必须咬人）
用法: python3 scripts/task477_selfcheck.py [--selftest]
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
    home = rd('Natives/ZL2HomeViewController.m')
    home_code = strip_code(home)
    setpg = rd('Natives/ZL2SettingPages.m')
    rrepo = rd('Natives/ZL2RendererRepoViewController.m')
    plrepo = rd('Natives/ZL2PluginRepoViewController.m')
    theme = rd('Natives/ZL2Theme.m')
    tag = rd('Natives/BuildTag.h')
    zhcn = rd('Natives/resources/zh-CN.lproj/Localizable.strings')
    en = rd('Natives/resources/en.lproj/Localizable.strings')

    fails = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + ((' -- ' + detail) if detail and not ok else ''))
        if not ok:
            fails.append(name)
        return ok

    if '--selftest' in sys.argv:
        p1 = lambda s: 'ame477_buildBetaMenu' in s
        p2 = lambda s: 'uninstallRendererPlugin:ame477_pid' in s
        ok = True
        ok &= check('S1 selftest 剥三代构建器必红', not p1(home_code.replace('ame477_buildBetaMenu', '')) and p1(home_code))
        ok &= check('S2 selftest 剥卸载链必红', not p2(rrepo.replace('uninstallRendererPlugin:ame477_pid', '')) and p2(rrepo))
        if not ok:
            print('SELFTEST FAIL')
            return 1
        print('SELFTEST ALL PASS 2/2')
        return 0

    # ── A 线 ──
    banned_shell = ['ame411_', 'paneWrap', 'paneToggleButton', 'ame379_paneHeader',
                    'ame389_slideIndicator', 'navItems', 'hamburgerButton',
                    'navBackButton', 'dimOverlay', 'ame376_applyPaneGeometry',
                    'ame347_applyWidthClass', 'ame_setDrawerOpen',
                    'ame_buildNavigationViewShell', 'ZL2ShellNavItem',
                    'ZL2ShellSwitcherButton', 'ZL2ShellIconButton',
                    'ame376_paneCollapsed', 'ame347_drawerOpen']
    check('A1 壳层一代/二代零残留（禁符表 18 族，剥注释代码面）',
          all(b not in shell_code for b in banned_shell),
          str([b for b in banned_shell if b in shell_code]))
    check('A2 bare 唯一骨架 + 令牌链保留',
          '[self ame_buildBareShell];' in shell_code
          and 'bare shell enforced' in shell_code
          and 'self.ame347_navMode = [[ZL2Theme ame347_shellLayout]' in shell_code
          and '+ (NSString *)ame347_shellLayout {' in theme)
    check('A3 预览镜像同步退役',
          all(b not in preview_code for b in (
              'ame414_buildCapsule', 'ame414_buildNavPane', 'capsuleCluster',
              'paneItems', 'ame414_navShell', 'ame416_paneExpanded')))

    # ── B 线 ──
    check('B1 三态分发器 + 降级防线 + 形态旗',
          '+ (NSInteger)ame477_styleIndex {' in home
          and '[self ame477_buildBetaMenu];' in home_code
          and 'beta classic EXCEPTION signature' in home
          and 'self.ame477_betaMode = ([ZL2HomeViewController ame477_styleIndex] == 2);' in home
          and 'self.ame477_betaMode = NO;' in home)
    check('B2 三代忠实锚（v1.0 单卡逐字回植）',
          '_actionMenu.backgroundColor = [ZL2Theme surfaceBright];' in home_code
          and 'static const CGFloat ame477_MenuEdgePadding   = 10;' in home
          and 'static const CGFloat ame477_VersionCardHeight = 68;' in home
          and '@property (nonatomic, strong) UIView *accountAvatarBg;' in home
          and '@property (nonatomic, strong) UILabel *versionLoaderLabel;' in home
          and 'ame477_spacer' in home_code
          and '"zl2_home_account_card"' in home_code
          and '"zl2_home_version_card"' in home_code)
    check('B3 刷新链分流 + v1.0 刷新器在位',
          'if (self.ame477_betaMode) { [self ame477_refreshBetaAccountCard]; return; }' in home_code
          and 'if (self.ame477_betaMode) { [self ame477_refreshBetaVersionCard]; return; }' in home_code
          and '- (void)ame477_refreshBetaAccountCard {' in home
          and '- (void)ame477_refreshBetaVersionCard {' in home
          and 'ame185_fetchAvatarForAuthData:ame477_authData' in home_code
          and 'detectLoaderFromVersionId:ame477_versionId' in home_code)
    check('B4 设置页三选项 + clamp 0..2',
          'ame477.setpg.home_sidebar.beta' in setpg
          and 'optionKeys:@[@"0", @"1", @"2"]' in setpg
          and 'if (ame475_style < 0 || ame475_style > 2) ame475_style = 0;' in setpg
          and 'if (index < 0 || index > 2) return;' in setpg)
    check('B5 宽度分支（beta 走转盘 clamp + rail 88/104 保留）',
          'if (self.ame475_railMode && !self.ame477_betaMode) {' in home_code
          and 'ame475_railWidth = 88.0' in home_code
          and 'ame475_railWidth = 104.0' in home_code
          and 'multiplier:ZL2HomeMenuWidthRatio];' in home_code)

    # ── C 线 ──
    check('C1 卸载钮双面（渲染器仓库页已装行 style4 + 插件仓库渲染器区）',
          'ame475_applyActionStyle:4' in rrepo
          and 'ame431_applyActionStyle:4' in plrepo
          and 'ame477.repo.uninstall' in rrepo
          and 'ame477.repo.uninstall' in plrepo)
    check('C2 卸载链（destructive 确认 + uninstallRendererPlugin 双面）',
          'uninstallRendererPlugin:ame477_pid' in rrepo
          and 'uninstallRendererPlugin:ame477_pid' in plrepo
          and 'ame429.list.delete_confirm' in rrepo
          and 'ame429.list.delete_ok' in plrepo
          and 'destructive:YES' in rrepo)
    check('C3 徽标（插件/内置 + 影子调用）',
          'ame477.setpg.renderer.badge_plugin' in setpg
          and 'ame477.setpg.renderer.badge_builtin' in setpg
          and 'rendererChoiceOverrides' in setpg
          and 'ame477_badged' in setpg)
    check('C4 i18n 四键双表',
          all(k in zhcn for k in ('ame477.setpg.home_sidebar.beta',
                                  'ame477.setpg.renderer.badge_plugin',
                                  'ame477.setpg.renderer.badge_builtin',
                                  'ame477.repo.uninstall'))
          and all(k in en for k in ('ame477.setpg.home_sidebar.beta',
                                    'ame477.setpg.renderer.badge_plugin',
                                    'ame477.setpg.renderer.badge_builtin',
                                    'ame477.repo.uninstall')))

    # ── D 线 ──
    check('D1 BuildTag Task477 进代', 'ame415_buildTag = @"Task477 · ' in tag)

    if fails:
        print(f'[FAIL] task477_selfcheck {len(fails)} 项:')
        for f in fails:
            print('  -', f)
        return 1
    print('[PASS] task477_selfcheck: A/B/C/D 全绿（导航合并退役 + 三代 v1.0 移植 + 卸载三面 + 徽标 + 代际）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
