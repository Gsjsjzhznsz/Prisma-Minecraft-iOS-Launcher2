#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""★Task476 门禁新立 —— 主页侧边栏 ZL2 图标化（rail 二代）+ 插件仓库并入渲染器区。

用户复诉（2026-11-25）：「为什么侧边栏还是这个样，zl2 不是这样的。」
ZL2 实锚：ZalithLauncher2 MainScreen.kt TopBarRailItem/TextRailItem = 图标常驻、
文字仅选中展开。Task475 rail 瓦片沿用 ame378 带字工厂 = 观感无差 = 复诉根因。

T 线（主页侧边栏 ZL2 图标化）：
  T1 纯图标工厂 + 常量 + 七调用点（rail 方法体内 7 处全换名）
  T2 工厂零文字面（无 UILabel 构建；title 仅入 accessibilityLabel）
  T3 ame369.shell.tab.* 六站点 localize 原位保留（453 改写点锚协同）
  T4 转盘带字瓦片工厂与五调用点原样保留（双形态观感分工）
U 线（插件仓库并入渲染器区）：
  U1 import ×2 + 属性 + init 装配
  U2 回包 renderers[] 同源解析 + numberOfRows 公式
  U3 渲染器区卡构建器（已装态回查 + 跳渲染器仓库页单一安装面）
  U4 静态入口兜底（空目录仍现渲染器仓库行，复用 ame475.repo.title）
V 线（在线仓库面）：
  V1 plugin-repo/index.json renderers[] 实体对表（zip sha256/size）
  V2 renderer-repo 面零回归（B7b 同口径复检）
  V3 plugin-repo/plugins/ 渲染器包实体在场
W 线（代际）：W1 BuildTag Task476 进代
--selftest：负样本探针 ×3（剥工厂 / 剥 renderers 解析 / 翻代际——判定函数必须咬人）
用法: python3 scripts/task476_selfcheck.py [--selftest]
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rd(p):
    return (ROOT / p).read_text(encoding='utf-8', errors='replace')


def main():
    home = rd('Natives/ZL2HomeViewController.m')
    repovc = rd('Natives/ZL2PluginRepoViewController.m')
    tag = rd('Natives/BuildTag.h')

    fails = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + ((' -- ' + detail) if detail and not ok else ''))
        if not ok:
            fails.append(name)
        return ok

    if '--selftest' in sys.argv:
        p1 = lambda s: 'ame476_iconRailTileWithSymbol' in s
        p2 = lambda s: 'index[@"renderers"]' in s
        p3 = lambda s: 'ame415_buildTag = @"Task476 · ' in s
        ok = True
        ok &= check('S1 selftest 剥纯图标工厂必红', not p1(home.replace('ame476_iconRailTileWithSymbol', '')) and p1(home))
        ok &= check('S2 selftest 剥 renderers 解析必红', not p2(repovc.replace('index[@"renderers"]', 'index[@"renderers_x"]')) and p2(repovc))
        ok &= check('S3 selftest 翻旧代际必红', not p3(tag.replace('Task476 · ', 'Task475 · ')) and p3(tag))
        if not ok:
            print('SELFTEST FAIL')
            return 1
        print('SELFTEST ALL PASS 3/3')
        return 0

    # ── T 线 ──
    check('T1 纯图标工厂 + 常量 + 七调用点',
          '- (ZL2HomeTapControl *)ame476_iconRailTileWithSymbol:' in home
          and 'static const CGFloat ZL2HomeRailTileHeight    = 44.0;' in home
          and home.count('ame476_iconRailTileWithSymbol') == 8
          and 'ame476_iconRailTileWithSymbol:@"square.grid.2x2.fill"' in home
          and 'ame476_iconRailTileWithSymbol:@"gearshape.fill"' in home)
    check('T2 工厂零文字面（title 仅入 VoiceOver 标签）',
          'ame476_label' not in home
          and home.count('tile.accessibilityLabel = title;') >= 2
          and '[ame476_icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor]' in home)
    check('T3 六站点 localize 原位保留（ame369 453 锚协同）',
          all(f'localize(@"ame369.shell.tab.{k}"' in home for k in
              ('versions', 'accounts', 'downloads', 'terracotta', 'files', 'settings')))
    check('T4 转盘带字瓦片工厂与五调用点原样保留',
          home.count('ame378_quickNavTileWithSymbol') == 6
          and '- (ZL2HomeTapControl *)ame378_quickNavTileWithSymbol:(NSString *)symbol' in home)

    # ── U 线 ──
    check('U1 插件仓库页 import + 属性 + init',
          '#import "ZL2RendererRepoViewController.h"' in repovc
          and '#import "PLRendererPluginService.h"' in repovc
          and '@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rendererItems;' in repovc
          and 'self.rendererItems = [NSMutableArray array];' in repovc)
    check('U2 renderers[] 同源解析 + numberOfRows 公式',
          'index[@"renderers"]' in repovc
          and 'MAX(self.remoteItems.count, 1) + MAX(self.rendererItems.count, 1)' in repovc)
    check('U3 渲染器区卡构建器（已装态回查 + 仓库页跳转）',
          '- (Ame431PluginRepoCardCell *)ame476_rendererCardCell:' in repovc
          and '[PLRendererPluginService availableRenderers]' in repovc
          and repovc.count('[[ZL2RendererRepoViewController alloc] init]') >= 2
          and 'ame476_rendererStart' in repovc)
    check('U4 静态入口兜底（复用 ame475.repo.title）',
          'ame475.repo.title' in repovc
          and 'ame475.repo.installed' in repovc
          and 'ame475.repo.install' in repovc)

    # ── V 线 ──
    v_ok = False
    v1_detail = ''
    try:
        pidx = json.loads((ROOT / 'plugin-repo/index.json').read_text(encoding='utf-8'))
        e0 = pidx['renderers'][0]
        zp = ROOT / 'plugin-repo' / e0['file']
        zsha = hashlib.sha256(zp.read_bytes()).hexdigest()
        v_ok = (e0['id'] == 'mobileglues-dev'
                and zsha == e0['sha256']
                and zp.stat().st_size == e0['size']
                and pidx['updated'] == '2026-11-25')
    except Exception as exc:
        v1_detail = str(exc)
    check('V1 plugin-repo renderers[] 实体对表', v_ok, v1_detail)
    v2_ok = False
    try:
        ridx = json.loads((ROOT / 'renderer-repo/index.json').read_text(encoding='utf-8'))
        re0 = ridx['renderers'][0]
        rzp = ROOT / 'renderer-repo' / re0['file']
        rzsha = hashlib.sha256(rzp.read_bytes()).hexdigest()
        v2_ok = (rzsha == re0['sha256'] and rzp.stat().st_size == re0['size'])
    except Exception:
        pass
    check('V2 renderer-repo 面零回归（B7b 同口径）', v2_ok)
    check('V3 plugin-repo/plugins/ 渲染器包实体在场',
          (ROOT / 'plugin-repo/plugins/mobileglues-dev-1.0.0.zip').is_file())

    # ── W 线 ──
    check('W1 BuildTag Task476 进代', 'ame415_buildTag = @"Task476 · ' in tag)

    if fails:
        print(f'[FAIL] task476_selfcheck {len(fails)} 项:')
        for f in fails:
            print('  -', f)
        return 1
    print('[PASS] task476_selfcheck: T/U/V/W 全绿（rail ZL2 图标化 + 插件仓库渲染器区 + 仓库面对表 + 代际）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
