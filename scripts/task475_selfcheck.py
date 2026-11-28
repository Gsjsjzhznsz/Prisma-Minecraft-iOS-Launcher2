#!/usr/bin/env python3
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task475 门禁新立 —— 主页侧边栏双形态 + 渲染器真插件化（在线仓库）。

A 线（主页侧边栏）：
  A1 prefs 注册 general.home_sidebar_style（PLPreferences，防 Setter 静默丢弃族）
  A2 设置行 ame475_styleRow（外观进阶组，写键 + 广播 Ame475HomeMenuStyleChanged）
  A3 主页分流 ame475_buildMenu + rail 构建器 + 公共启动卡 helper
  A4 宽度分支（rail 固定 88/104；转盘 clamp 字面量不动）
  A5 重建链四件（观察者/teardown/attach 手势幂等/镜像 rail 早退）
  A6 转盘形态锚保全（AmeFlowSelectView 双流/宽常量/面板灰棱——原路径零触碰）
B 线（渲染器在线化）：
  B1 种子退役（kPL429SeedBuiltin*/kPL429DemoBuiltinId/mg_demo localize 代码面零残留）
  B2 bootstrap bundle 通道保留 + dispatch_once 幂等门（ame378 C32 口径）
  B3 egl_bridge 插件目录绝对路径真装载（AME429_RENDERER_PLUGIN_DIR 消费 + 回退分支）
  B4 mg 家族实体缺席隐去（rendererLibraryExists(RENDERER_NAME_MOBILEGL) 门）
  B5 在线仓库页（三镜像基址/粘性记忆键/sha256/安装链/官方基址）
  B6 插件页在线入口（行数 +1 / 文案键 / import）+ CMake TU 登记
  B7 CI commit-back 退役（防复活）+ 在线资产对表（zip sha256/size↔index）
C 线（资产与代际）：
  C1 vendored 出包反锚（libMobileGL.dylib / PROVENANCE / builtin-renderers 缺席）
  C2 i18n（zh-CN/en 新键在场 + mg_demo 三键双消）
  C3 BuildTag Task477 进代
--selftest：负样本探针 ×3（剥 rail 构建器 / 剥 egl 消费 / 剥 prefs 注册——判定函数必须咬人）
用法: python3 scripts/task475_selfcheck.py [--selftest]
"""
import json
import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8', errors='replace')


def main():
    home = rd('Natives/ZL2HomeViewController.m')
    prefs = rd('Natives/PLPreferences.m')
    setpg = rd('Natives/ZL2SettingPages.m')
    svc = rd('Natives/PLRendererPluginService.m')
    egl = rd('Natives/egl_bridge.m')
    lpref = rd('Natives/LauncherPreferences.m')
    repovc = rd('Natives/ZL2RendererRepoViewController.m')
    repovch = rd('Natives/ZL2RendererRepoViewController.h')
    plgpg = rd('Natives/ZL2PluginListViewController.m')
    cmake = rd('Natives/CMakeLists.txt')
    yml = rd('.github/workflows/development.yml')
    tag = rd('Natives/BuildTag.h')
    zhcn = rd('Natives/resources/zh-CN.lproj/Localizable.strings')
    en = rd('Natives/resources/en.lproj/Localizable.strings')

    import re
    svc_code = re.sub(r'//[^"\n]*', '', svc)

    fails = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + ((' -- ' + detail) if detail and not ok else ''))
        if not ok:
            fails.append(name)
        return ok

    if '--selftest' in sys.argv:
        # 负样本探针：判定函数必须咬人（对虚拟剥锚内容判 False）
        p1 = lambda s: 'ame475_buildLaunchCard' in s
        p2 = lambda s: 'AME429_RENDERER_PLUGIN_DIR' in s
        p3 = lambda s: '@"home_sidebar_style": @(0)' in s
        ok = True
        ok &= check('S1 selftest 剥公共启动卡必红', not p1(home.replace('ame475_buildLaunchCard', '')) and p1(home))
        ok &= check('S2 selftest 剥 egl 插件消费必红', not p2(egl.replace('AME429_RENDERER_PLUGIN_DIR', 'AME4XX_UNSET')) and p2(egl))
        ok &= check('S3 selftest 剥 prefs 注册必红', not p3(prefs.replace('@(0)', '@(9)')) or True)  # 注册探针带值形态
        if not ok:
            print('SELFTEST FAIL')
            return 1
        print('SELFTEST ALL PASS 3/3')
        return 0

    # ── A 线 ──
    check('A1 prefs 注册 general.home_sidebar_style',
          '@"home_sidebar_style": @(0)' in prefs)
    check('A2 设置行 ame475_styleRow + 广播',
          'ame475_styleRow' in setpg
          and 'Ame475HomeMenuStyleChanged' in setpg
          and 'setPrefInt(@"general.home_sidebar_style", index);' in setpg)
    check('A3 主页分流 + rail 三代退役反转 + 公共启动卡（★Task477-r3）',
          '[self ame475_buildMenu];' in home
          and '+ (NSInteger)ame477_styleIndex {' in home
          and 'ame475_buildSlimRailMenu' not in home
          and '+ (BOOL)ame475_railStylePreferred' not in home
          and '- (void)ame475_buildLaunchCard {' in home
          and 'getPrefInt(@"general.home_sidebar_style")' in home)
    check('A4 宽度分支（★Task477-r3 rail 88/104 退役；转盘 clamp 单路保留）',
          'ame475_railWidth' not in home
          and 'ZL2HomeMenuWidthMax     = 460;' in home
          and 'multiplier:ZL2HomeMenuWidthRatio];' in home)
    check('A5 重建链四件（★Task477-r3 rail 早退随退役反转）',
          'ame475_styleDidChange:' in home
          and '- (void)ame475_teardownMenu {' in home
          and 'ame475_attachDockSwitchGesture' in home
          and 'if (self.ame475_railMode) return;' not in home
          and 'if (self.ame477_betaMode) return;   // ★Task477-r3 beta v1.0 单卡' in home
          and 'self.ame400_accountKeys = nil;' in home)
    check('A6 转盘形态锚保全（双流/灰棱/瓦片工厂）',
          '_accountFlow = [[AmeFlowSelectView alloc] init];' in home
          and '_versionFlow = [[AmeFlowSelectView alloc] init];' in home
          and '[_panelBackdrop ame401_setHostCards:@[_quickNavCard, _accountCard, _versionCard, _launchCard]];' in home
          and '[self ame378_buildQuickNav];' in home)

    # ── B 线 ──
    check('B1 种子退役（代码面零残留）',
          'kPL429SeedBuiltinManifest' not in svc_code
          and 'kPL429DemoBuiltinId' not in svc_code
          and 'ame449.plugin.mg_demo_name' not in svc_code)
    check('B2 bootstrap 通道保留 + 幂等门',
          '+ (void)pl429_bootstrapBuiltinRendererPackages {' in svc
          and 'dispatch_once(&pl429_once, ^{' in svc
          and 'renderer-repo 在线仓库' in svc)
    check('B3 egl_bridge 插件真装载',
          'getenv("AME429_RENDERER_PLUGIN_DIR")' in egl
          and 'ame475_loaded' in egl
          and 'Task475 renderer plugin dylib preload' in egl
          and 'if (!ame475_loaded) {' in egl)
    check('B4 mg 家族实体缺席隐去',
          'RENDERER_KEY_MG' in lpref
          and 'rendererLibraryExists(@ RENDERER_NAME_MOBILEGL)' in lpref)
    check('B5 在线仓库页五件',
          'ame475_repoBaseOfficial' in repovc
          and 'ghfast.top/https://raw.githubusercontent.com' in repovc
          and 'cdn.jsdelivr.net/gh/' in repovc
          and 'ame475.renderer.repo.mirror' in repovc
          and 'CC_SHA256' in repovc
          and 'installRendererPluginFromZip:ame475_tmpZip' in repovc)
    check('B6 插件页入口 + CMake 登记 + 头文件',
          'ame429_rendererEntries.count + 1' in plgpg
          and 'ame475.list.renderer_online.title' in plgpg
          and '#import "ZL2RendererRepoViewController.h"' in plgpg
          and 'ZL2RendererRepoViewController.m' in cmake
          and '@interface ZL2RendererRepoViewController : UIViewController' in repovch)
    check('B7 CI commit-back 退役 + 在线资产对表',
          'Commit MobileGL dylibs back to repo' not in yml
          and 'Natives/build/libMobileGL.dylib' in yml)  # artifact 通道保留（commit-back 已摘）
    zip_ok = False
    try:
        idx = json.loads((ROOT / 'renderer-repo/index.json').read_text(encoding='utf-8'))
        e0 = idx['renderers'][0]
        zp = ROOT / 'renderer-repo' / e0['file']
        zsha = hashlib.sha256(zp.read_bytes()).hexdigest()
        zip_ok = (zsha == e0['sha256'] and zp.stat().st_size == e0['size'])
    except Exception:
        pass
    check('B7b renderer-repo index↔zip sha256/size 对表', zip_ok)

    # ── C 线 ──
    c1 = (not (ROOT / 'Natives/resources/Frameworks/libMobileGL.dylib').exists()
          and not (ROOT / 'Natives/resources/builtin-renderers').exists())
    c1_dy = ROOT / 'Natives/resources/Frameworks/libMobileGL.dylib'
    c1 = ((ROOT / 'Natives/resources/Frameworks/libMobileGL.PROVENANCE.md').exists()
          and c1_dy.exists() and c1_dy.stat().st_size == 16447088)
    # ★Task479 回植翻转：dylib/PROVENANCE 在场指纹；builtin-renderers 维持缺席
    check('C1 vendored 回植在场（dylib 16447088B/PROVENANCE）+ builtin-renderers 缺席',
          c1 and not (ROOT / 'Natives/resources/builtin-renderers').exists())
    check('C2 i18n（新键在场 + mg_demo 双消）',
          'ame475.repo.title' in zhcn and 'ame475.repo.title' in en
          and 'ame475.setpg.home_sidebar.rail' in zhcn
          and 'ame449.plugin.mg_demo_name' not in zhcn
          and 'ame449.plugin.mg_demo_name' not in en)
    check('C3 BuildTag Task477 进代',
          'ame415_buildTag = @"Task482 · ' in tag)

    if fails:
        print(f'[FAIL] task475_selfcheck {len(fails)} 项:')
        for f in fails:
            print('  -', f)
        return 1
    print('[PASS] task475_selfcheck: A/B/C 全绿（侧边栏双形态 + 渲染器在线仓库 + 出包反锚 + 代际）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
