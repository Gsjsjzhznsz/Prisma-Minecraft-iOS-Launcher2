#!/usr/bin/env python3
"""Task336 门禁电池 —— 三线收口断言（IMG_0500 装机截图三问）。

线① 26.x 年份制门控根修（「26.x 的新版本没有加载器可选」）：
  A1 ame_versionComponents 前导数字段解析（26.3/26.4-snapshot-6/1.21.11）
  A2 NSNotFound ?: 陷阱防线（显式判断，不用 ?: 取 location）
  A3 纯数字点形态闸（ame_isPlainNumericVersion）
  A4 fabricLike 语义比较 ≥1.14（26.x 全系+快照通过）
  A5 legacyFabric 1.3–1.13（26.x 天然排除）
  A6 forgeFamily 纯数字形态（快照排除）
  A7 neoforge ≥1.20.1 + 年份制支持
  A8 门控注释锚 Task336
线② Fabric-like 页内直装（「点击安装跳到这里」退役旧表单）：
  B1 FabricUtils.ame336_installFabricLikeVendor 声明（.h）+ 实现（.m）
  B2 候选轮询 ame336_fetchProfile（PLMirrorCenter 策略序 + 断环 nil）
  B3 profile 注册 Task322 混居 gameDir=versions/<id>
  B4 API 三厂分流（legacy-fabric-api/qsl/fabric-api + legacy-fabric 标签）
  B5 API 失败不翻转安装主体（非关键错误纪律）
  B6 Modrinth 返回数组消费（NSArray 而非 dict["versions"]）
线③ 分发改造 + 旧界面退役：
  C1 Addons 分发 = M3 确认 + 直装（不再 push FabricInstallViewController）
  C2 FabricInstallViewController 前向声明退役（零代码引用）
  C3 ame336Installing 忙态（防重入 + 安装中…）
  C4 旧下载页链路保留（DownloadViewController 仍 import FabricInstall——
     退役纪律：只退役新 UI 流程内的跳转，旧页实体下轮处理）
  C5 成功链 ReloadProfileList + 隔离骨架 + M3Dialog 完成弹窗
线④ 结构完整性：
  D1 括号平衡（HEAD 对照式）
  D2 CMake 编译面（FabricUtils.m 在列）
  D3 FabricUtils.h/.m 接口一致（ame336_installFabricLikeVendor 双面）
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

gav = read('Natives/ZL2GameAddonsViewController.m')
fuh = read('Natives/installer/FabricUtils.h')
fum = read('Natives/installer/FabricUtils.m')

# ── A 线① 26.x 门控语义化 ───────────────────────────────────
check('A1 ame_versionComponents 前导数字段解析',
      'ame_versionComponents' in gav
      and 'componentsSeparatedByString:@"."' in gav)
check('A2 NSNotFound ?: 陷阱防线（显式 NSNotFound 判断）',
      re.search(r'firstNonDigit\.location == NSNotFound', gav)
      and not re.search(r'rangeOfCharacterFromSet[^\n]*\.location \?:', gav))
check('A3 ame_isPlainNumericVersion 纯数字点形态闸',
      'ame_isPlainNumericVersion' in gav
      and '0123456789.' in gav)
check('A4 fabricLike ≥1.14 语义比较',
      re.search(r'ame_fabricLikeSupported.{0,200}ame_versionComponentsAtLeast:@\[@1, @14\]', gav, re.S))
check('A5 legacyFabric 1.3–1.13 + 非 1 系排除',
      re.search(r'ame_legacyFabricSupported.{0,300}minor >= 3 && minor <= 13', gav, re.S)
      and 'comps[0].integerValue != 1' in gav)
check('A6 forgeFamily 纯数字形态（快照排除）',
      re.search(r'ame_forgeFamilySupported.{0,300}ame_isPlainNumericVersion', gav, re.S))
check('A7 neoforge ≥1.20.1 + 年份制',
      re.search(r'ame_neoforgeSupported.{0,400}comps\[0\]\.integerValue >= 2', gav, re.S)
      and 'patch >= 1' in gav)
check('A8 Task336 门控注释锚 + 26.x 实测记录',
      'Task336' in gav and '26.3' in gav and '26.4-snapshot-6' in gav)

# ── B 线② 直装执行器 ────────────────────────────────────────
check('B1 执行器声明+实现双面',
      'ame336_installFabricLikeVendor' in fuh
      and fum.count('ame336_installFabricLikeVendor') >= 1)
check('B2 候选轮询 + 断环',
      'ame336_fetchProfile' in fum
      and 'candidateURLsForVendor:vendor' in fum
      and fum.count('tryNext = nil') >= 2)
check('B3 profile 注册混居口径',
      'profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@", profileId]' in fum
      and '[PLProfiles.current saveProfile:profile withName:profileId]' in fum
      and 'Task322' in fum)
check('B4 API 三厂分流',
      '@"legacy-fabric-api"' in fum and '@"qsl"' in fum and '@"fabric-api"' in fum
      and '@"legacy-fabric"' in fum)
check('B5 API 失败不翻转主体（completion(YES, nil) 非关键纪律）',
      re.search(r'ame336_installAPIForVendor.{0,3000}completion\(YES, nil\)', fum, re.S)
      and 'API 失败不翻转安装主体成败' in fum)
check('B6 Modrinth 数组消费（NSArray 版本列表）',
      re.search(r'ame336_asyncGet\(\[NSURL URLWithString:apiUrl\], \^\(id json', fum)
      and '![json isKindOfClass:[NSArray class]]' in fum)
check('B7 completion 主线程化（safeCompletion dispatch main）',
      'dispatch_async(dispatch_get_main_queue(), ^{ completion(s, pid, e); });' in fum)
check('B8 版本 json 落盘 + localVersionList 注册',
      'saveJSONToFile(profileJson, jsonPath)' in fum
      and 'localVersionList addObject' in fum)

# ── C 线③ 分发改造 + 退役 ───────────────────────────────────
check('C1 M3 确认 + 直装（不再 push 旧表单）',
      '确认安装' in gav
      and 'ame336_installFabricLikeVendor:vendor' in gav
      and not re.search(r'FabricInstallViewController \*vc', gav))
check('C2 FabricInstallViewController 前向声明退役',
      not re.search(r'@interface FabricInstallViewController', gav))
check('C3 ame336Installing 忙态（防重入 + 安装中…）',
      'ame336Installing' in gav
      and gav.count('ame336Installing') >= 4
      and '@"安装中…"' in gav)
check('C4 旧下载页链路保留（DownloadViewController→Forge 表单不动）',
      'ForgeInstallViewController *vc' in gav
      and re.search(r'FabricInstallViewController alloc', read('Natives/DownloadViewController.m')) is None
      and re.search(r'ForgeInstallViewController alloc', read('Natives/DownloadViewController.m')))
check('C5 成功链三件套',
      'ReloadProfileList' in gav
      and 'ame324_ensureIsolationSkeletonsAll' in gav
      and gav.count('安装完成') >= 1)

# ── D 结构完整性 ────────────────────────────────────────────
def _strip_strings_comments(text):
    sys.path.insert(0, os.path.join(ROOT, 'scripts'))
    import task139_syntax_gate as _t139
    return _t139.strip_strings_comments(text)

def _deltas(src):
    return (src.count('{') - src.count('}'),
            src.count('(') - src.count(')'),
            src.count('[') - src.count(']'))

for rel in ['Natives/ZL2GameAddonsViewController.m', 'Natives/installer/FabricUtils.m']:
    cur = _deltas(_strip_strings_comments(read(rel)))
    head_src = subprocess.run(['git', 'show', f'HEAD:{rel}'],
                              capture_output=True, text=True).stdout
    head = _deltas(_strip_strings_comments(head_src))
    check(f'D1 括号平衡(HEAD对照) {os.path.basename(rel)}', cur == head,
          f'cur={cur} head={head}')

cmk = read('Natives/CMakeLists.txt')
check('D2 CMake 编译面 FabricUtils.m 在列', 'installer/FabricUtils.m' in cmk)
check('D3 接口双面一致（.h 声明参数序 == .m 实现）',
      re.search(r'ame336_installFabricLikeVendor:\(NSString \*\)vendor\s*\n\s*gameVersion:', fuh)
      and re.search(r'ame336_installFabricLikeVendor:\(NSString \*\)vendor\s*\n\s*gameVersion:', fum))

print(f'\nRESULT: {passed} pass, {len(failures)} fail')
if failures:
    print('FAILURES PRESENT:', ', '.join(failures))
    sys.exit(1)
print('ALL GREEN')
