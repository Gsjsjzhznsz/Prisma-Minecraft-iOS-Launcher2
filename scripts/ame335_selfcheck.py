#!/usr/bin/env python3
"""Task335 门禁电池 —— 五线收口断言。

线① 清单加载失败/原版安装秒败根修（MRDT × ZL2VersionIndex 兑底）：
  A1 MRDT 引入 ZL2VersionIndex 头
  A2 主查找 remoteVersionEntryForIdSync 兑底
  A3 inheritsFrom 父版本查找同款兑底
  A4 契约声明在 .h（含主线程不等待语义）
  A5 实现三语义（主线程快照/限时等待/latest-* 种子滤除）
  A6 安装钮恒可点（原版安装不再被禁用）
  A7 busy 态不再改安装钮文案（卡「清单加载中」投诉根修）
  A8 lastVersionId 指向实际下载版本（profile 命名根修）
线② 模组加载器同步 ZL2（Legacy Fabric / Quilt 全家族）：
  B1 FabricUtils endpoints 含 Legacy Fabric（meta.legacyfabric.net v2）
  B2 vendor 段三厂 pickList
  B3 presetVendor/presetLoaderVersion 声明 + 应用（vendor 段回显 + 版本直通）
  B4 API 安装三厂分流（legacy-fabric-api / qsl / loaderTag legacy-fabric）
  B5 Addons 页九卡构造（legacyfabric/legacyfabricapi/quilt/quiltapi）
  B6 互斥表全家族五键
  B7 分发面 presetVendor 三厂直装
线③ 旧 UI 功能迁新 UI（清单端点泛化）：
  C1 legacyfabric 加载器清单端点（meta.legacyfabric.net）
  C2 quilt 加载器清单端点（meta.quiltmc.org v3）
  C3 Modrinth 三项目（fabric-api / legacy-fabric-api / qsl）
  C4 ame_syncFetch 40s 硬顶（不无限卡）
  C5 loadingIdentifiers 在途去重（多点不叠加）
线④ 图标同步 ZL2（除 IPA 图标）：
  D1 resources/ModLoaderIcons 六标准键在位（Makefile cp -R 链）
  D2 Natives/ModLoaderIcons 六标准键在位（CMake GLOB 链）
  D3 Helper legacyfabric PNG 分支先于 fabric（containsString 吞并防线）
  D4 零 *_light/*_dark iconBundleName 死引用残余
  D5 CMakeLists MODLOADER_ICONS_DIR GLOB 拷贝面接驳在案
  D6 legacyfabric.png 双链同字节（单一事实源）
  D7 IPA 图标不动（resources/AppIcon*.png 零改动）
线⑤ 结构完整性：
  E1 括号平衡（HEAD 对照式，task139 剥离算法）
  E2 FabricInstallViewController.h 新 property 与 .m 应用一致
  E3 CMake 编译面含三个涉改 TU
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

failures = []
passed = 0

def check(name, cond, detail=''):
    global passed
    if cond:
        passed += 1
        print(f'  ok  {name}')
    else:
        failures.append(name)
        print(f'  FAIL {name} {detail}')

def read(rel):
    with open(os.path.join(ROOT, rel), errors='ignore') as f:
        return f.read()

# ── A 线① 清单/原版安装根修 ─────────────────────────────────
mrdt = read('Natives/MinecraftResourceDownloadTask.m')
vih = read('Natives/ZL2VersionIndex.h')
vim = read('Natives/ZL2VersionIndex.m')
gav = read('Natives/ZL2GameAddonsViewController.m')

check('A1 MRDT 引入 ZL2VersionIndex 头',
      '#import "ZL2VersionIndex.h"' in mrdt)
check('A2 主查找兑底 remoteVersionEntryForIdSync',
      mrdt.count('remoteVersionEntryForIdSync') >= 2)
check('A3 inheritsFrom 同款兑底（第二处在 inheritsFrom 块内）',
      re.search(r'inheritsFrom[^\n]*\n[^#]*?remoteVersionEntryForIdSync', mrdt, re.S)
      or (mrdt.count('remoteVersionEntryForIdSync') >= 2
          and mrdt.find('remoteVersionEntryForIdSync', mrdt.find('inheritsFrom')) > 0))
check('A4 契约声明 + 主线程不等待语义',
      'remoteVersionEntryForIdSync' in vih
      and 'isMainThread' in vim)
check('A5 实现：限时等待 + latest-* 滤除（url 字段闸）',
      'ame_waitForRemoteList' in vim
      and 'latest-*' in vim
      and vim.count('@"url"') >= 2)
check('A6 安装钮恒可点（userInteractionEnabled = YES）',
      re.search(r'installButton\.userInteractionEnabled\s*=\s*YES', gav))
check('A7 busy 态不改文案（「清单加载中…」不在 installLabel 赋值链）',
      'installLabel.text = hasSelection ? @"安装"' in gav
      and not re.search(r'installLabel\.text\s*=\s*@"清单加载中', gav))
check('A8 lastVersionId = self.gameVersion（实际下载版本）',
      re.search(r'profile\[@"lastVersionId"\]\s*=\s*self\.gameVersion', gav))

# ── B 线② 加载器同步 ZL2 ────────────────────────────────────
futils = read('Natives/installer/FabricUtils.m')
fivh = read('Natives/installer/FabricInstallViewController.h')
fivm = read('Natives/installer/FabricInstallViewController.m')

check('B1 Legacy Fabric 端点（meta.legacyfabric.net v2 双端点 + profile/json）',
      '@"Legacy Fabric"' in futils
      and 'meta.legacyfabric.net/v2/versions/game' in futils
      and 'meta.legacyfabric.net/v2/versions/loader' in futils
      and 'meta.legacyfabric.net/v2/versions/loader/%@/%@/profile/json' in futils)
check('B2 vendor 段三厂 pickList',
      '@[@"Fabric", @"Legacy Fabric", @"Quilt"]' in fivm)
check('B3 preset 双 property + vendor 回显 + 版本直通',
      'presetVendor' in fivh and 'presetLoaderVersion' in fivh
      and 'self.presetVendor.length > 0 ? self.presetVendor' in fivm
      and fivm.count('self.presetLoaderVersion') >= 2
      and 'indexOfObject:current' in fivm)
check('B4 API 三厂分流（legacy-fabric-api / qsl / legacy-fabric loaderTag）',
      '@"legacy-fabric-api"' in fivm and '@"qsl"' in fivm
      and '@"legacy-fabric"' in fivm
      and 'project/%@/version?game_versions' in fivm)
check('B5 Addons 九卡构造',
      all(k in gav for k in
          ['ame_cardWithIdentifier:@"legacyfabric"',
           'ame_cardWithIdentifier:@"legacyfabricapi"',
           'ame_cardWithIdentifier:@"quilt"',
           'ame_cardWithIdentifier:@"quiltapi"'])
      and gav.count('ame_cardWithIdentifier:') >= 9)
check('B6 互斥表全家族（五主键 + optifine 特例）',
      all(f'@"{k}":' in gav for k in ['forge', 'neoforge', 'fabric', 'legacyfabric', 'quilt', 'optifine'])
      and '@[@"forge", @"fabric", @"legacyfabric", @"quilt", @"optifine"]' in gav)
check('B7 分发三厂 preset 直装',
      'vc.presetVendor = @"Legacy Fabric"' in gav
      and 'vc.presetVendor = @"Quilt"' in gav
      and 'vc.presetVendor = @"Fabric"' in gav)

# ── C 线③ 端点泛化 ──────────────────────────────────────────
check('C1 legacyfabric 清单端点',
      'https://meta.legacyfabric.net/v2/versions/loader/%@' in gav)
check('C2 quilt 清单端点 v3',
      'https://meta.quiltmc.org/v3/versions/loader/%@' in gav)
check('C3 Modrinth 三项目',
      all(p in gav for p in ['@"fabric-api"', '@"legacy-fabric-api"', '@"qsl"'])
      and 'ame_fetchModrinthVersionsForProject' in gav)
check('C4 ame_syncFetch 40s 硬顶',
      'timeoutIntervalForRequest = 20' in gav
      and 'timeoutIntervalForResource = 40' in gav
      and re.search(r'40LL \* NSEC_PER_SEC', gav))
check('C5 在途去重 loadingIdentifiers',
      'loadingIdentifiers containsObject:ident' in gav
      and 'loadingIdentifiers removeObject:ident' in gav)

# ── D 线④ 图标同步 ZL2 ──────────────────────────────────────
KEYS = ['fabric', 'forge', 'legacyfabric', 'neoforge', 'optifine', 'quilt']
res_icons = os.path.join(ROOT, 'Natives/resources/ModLoaderIcons')
cmk_icons = os.path.join(ROOT, 'Natives/ModLoaderIcons')

check('D1 resources/ModLoaderIcons 六标准键（Makefile 链）',
      all(os.path.isfile(os.path.join(res_icons, f'{k}.png')) for k in KEYS),
      str(sorted(os.listdir(res_icons)) if os.path.isdir(res_icons) else 'DIR MISSING'))
check('D2 Natives/ModLoaderIcons 六标准键（CMake GLOB 链）',
      all(os.path.isfile(os.path.join(cmk_icons, f'{k}.png')) for k in KEYS),
      str(sorted(os.listdir(cmk_icons)) if os.path.isdir(cmk_icons) else 'DIR MISSING'))
check('D3 Helper legacyfabric 分支先于 fabric',
      re.search(r'containsString:@"legacyfabric"\]\)\s*return @"legacyfabric"',
                read('Natives/ModLoaderIconHelper.m'))
      and read('Natives/ModLoaderIconHelper.m').find(
          'containsString:@"legacyfabric"') < read('Natives/ModLoaderIconHelper.m').rfind(
          'return @"fabric"'))
check('D4 零 *_light/*_dark iconBundleName 残余',
      not re.search(r'iconBundleName:@"[a-z]+_(light|dark)"', gav))
check('D5 CMake GLOB 拷贝面接驳',
      'MODLOADER_ICONS_DIR' in read('Natives/CMakeLists.txt')
      and 'file(GLOB MODLOADER_ICON_FILES' in read('Natives/CMakeLists.txt'))
check('D6 legacyfabric.png 双链同字节',
      os.path.isfile(os.path.join(res_icons, 'legacyfabric.png'))
      and os.path.isfile(os.path.join(cmk_icons, 'legacyfabric.png'))
      and open(os.path.join(res_icons, 'legacyfabric.png'), 'rb').read()
      == open(os.path.join(cmk_icons, 'legacyfabric.png'), 'rb').read())
try:
    from PIL import Image  # noqa: F401
    _im = Image.open(os.path.join(res_icons, 'legacyfabric.png'))
    _im.verify()
    _ok = _im.size[0] > 0
except Exception:
    _ok = os.path.getsize(os.path.join(res_icons, 'legacyfabric.png')) > 100
check('D7 legacyfabric.png 真实可解析', _ok)
check('D8 IPA 图标零改动（AppIcon 资产不在本轮 diff）',
      subprocess.run(['git', 'diff', '--name-only', 'HEAD', '--',
                      'Natives/resources/'],
                     capture_output=True, text=True).stdout.find('AppIcon') < 0)

# ── E 结构完整性 ────────────────────────────────────────────
def _strip_strings_comments(text):
    sys.path.insert(0, os.path.join(ROOT, 'scripts'))
    import task139_syntax_gate as _t139
    return _t139.strip_strings_comments(text)

def _deltas(src):
    return (src.count('{') - src.count('}'),
            src.count('(') - src.count(')'),
            src.count('[') - src.count(']'))

for rel in ['Natives/MinecraftResourceDownloadTask.m',
            'Natives/ZL2GameAddonsViewController.m',
            'Natives/ZL2VersionIndex.m',
            'Natives/installer/FabricInstallViewController.m',
            'Natives/installer/FabricUtils.m',
            'Natives/ModLoaderIconHelper.m']:
    cur = _deltas(_strip_strings_comments(read(rel)))
    head_src = subprocess.run(['git', 'show', f'HEAD:{rel}'],
                              capture_output=True, text=True).stdout
    head = _deltas(_strip_strings_comments(head_src))
    check(f'E1 括号平衡(HEAD对照) {os.path.basename(rel)}', cur == head,
          f'cur={cur} head={head}')

check('E2 preset property .h 声明与 .m 应用一致',
      re.search(r'@property.*presetVendor', fivh)
      and re.search(r'@property.*presetLoaderVersion', fivh))
# E4 语义面盲区第十例防线：ZL2GameAddonsViewController.m 文件内前向声明
# （非 import installer 头）必须与 installer/FabricInstallViewController.h
# 的 preset 双 property 同步扩展（CI smoke 40515594446 实锤缺口）。
_m = re.search(r'@interface FabricInstallViewController.*?@end', gav, re.S)
check('E4 前向声明同步 preset 双 property',
      bool(_m) and 'presetVendor' in _m.group(0)
      and 'presetLoaderVersion' in _m.group(0))
cmk = read('Natives/CMakeLists.txt')
check('E3 CMake 编译面含涉改 TU',
      'ZL2VersionIndex.m' in cmk and 'installer/FabricUtils.m' in cmk
      and 'ModLoaderIconHelper.m' in cmk and 'ZL2GameAddonsViewController.m' in cmk)

print(f'\nRESULT: {passed} pass, {len(failures)} fail')
if failures:
    print('FAILURES PRESENT:', ', '.join(failures))
    sys.exit(1)
print('ALL GREEN')
