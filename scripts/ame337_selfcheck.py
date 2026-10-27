#!/usr/bin/env python3
"""Task337 门禁电池 —— 三线收口断言（装机 latestlog + 三问）。

线① 旧版本安装加载器闪退根修（NSInternalInconsistencyException 实锤栈：
    CFNetwork → ame336_asyncGet → setSelectedProfileName → CFXNotificationPost
    → ZL2VersionsViewController ame_rebuildList → CoreAutoLayout throw）：
  A1 FabricUtils ame336 profile 注册段主线程化（selectedProfileName 在
     dispatch main 块内）
  A2 ZL2VersionsViewController.reloadVersions 主线程防御钳制（通知链来源
     线程不可控，非主线程转发主队列）
  A3 FabricUtils POJAV_GAME_DIR getenv 兜底（对表 ame336_installAPIForVendor）
线② neoforge 获取清单失败根修（双雷）：
  B1 过滤改 ame185_loaderVersionMatchesGameVersion 共享匹配器（NeoForge
     maven 版本无 MC 前缀："21.1.77"/"26.1.2"，旧 hasPrefix:"<mc>-" 恒空）
  B2 BMCLAPI /neoforge/meta/api/maven/details 真镜像端点（旧 PLMirrorCenter
     /maven 静态映射拼 API 路径 = 死端点 404）
  B3 双形态解析（官方 versions[] + BMCLAPI files[] DIRECTORY）
  B4 旧 hasPrefix:prefix 过滤退役（neoforge 分支零残留）
  B5 skipPatterns 非 client 变体剔除表
  B6 utils.h + LauncherPreferences.h import 面
  B7 download_source 策略排序（bmclFirst）
线③ 继续退役旧界面（第二实体 Forge/NeoForge 页内直装）：
  C1 Addons 页零 ForgeInstallViewController 引用（前向声明+push 全退役）
  C2 ame337_installForgeLikeVendor 执行器存在
  C3 installer jar 三形态路径（NeoForge 1.20.1 老坐标/NeoForge 现代/Forge）
  C4 ForgeDirectInstaller import + installForgeFromInstaller 调用
  C5 M3 确认 + ame336Installing 忙态复用 + completion 统一主线程
  C6 Preview 桩：installForgeFromInstaller 桩补齐（语义面盲区第十一例
     预判——ZL2GameAddonsViewController.o 进 Preview 链接面）+ 两旧表单
     桩退役（失去消费者）
  C7 旧下载页链路保留（DownloadViewController 仍引用 ForgeInstall——
     退役纪律：只退役新 UI 流程内的跳转）
  C8 versionId 含 MC 版本段（JavaLauncher inferJavaMajor 口径）
线④ 结构完整性：
  D1 括号平衡（HEAD 对照式 × 4 文件）
  D2 Preview TU 面（ZL2GameAddonsViewController 在 ui_fluent_smoke.sh）
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

def _strip_strings_comments(text):
    sys.path.insert(0, os.path.join(ROOT, 'scripts'))
    import task139_syntax_gate as _t139
    return _t139.strip_strings_comments(text)

def _deltas(src):
    return (src.count('{') - src.count('}'),
            src.count('(') - src.count(')'),
            src.count('[') - src.count(']'))

gav = read('Natives/ZL2GameAddonsViewController.m')
fum = read('Natives/installer/FabricUtils.m')
zvv = read('Natives/ZL2VersionsViewController.m')
stub = read('Natives/Preview/ZL2PagesStub.m')

# ── A 线① 闪退根修 ──────────────────────────────────────────
# A1: ame336_installFabricLikeVendor 函数体内，selectedProfileName 赋值
#     必须位于 dispatch main 块中（提取 Task337 根修注释之后的块验证）
m337 = re.search(r'Task337 线①闪退根修.*?\}\);', fum, re.S)
check('A1 FabricUtils profile 注册段 dispatch main（selectedProfileName 三连收口）',
      bool(m337)
      and 'dispatch_async(dispatch_get_main_queue' in m337.group(0)
      and '[localVersionList addObject:' in m337.group(0)
      and 'saveProfile:profile withName:profileId' in m337.group(0)
      and 'PLProfiles.current.selectedProfileName = profileId' in m337.group(0),
      'Task337 根修块缺失或三调用不全')

# 主函数体内不得再有【块外】裸 selectedProfileName 赋值（防回退：
# strip 注释后提取 ame336 函数体，dispatch 块外出现即 FAIL；注释字样不算）
mfn = re.search(r'ame336_installFabricLikeVendor.*?(?=\n@end)', fum, re.S)
body_code = _strip_strings_comments(mfn.group(0) if mfn else '')
stripped = re.sub(r'dispatch_async\(dispatch_get_main_queue.*?\}\);', '', body_code, flags=re.S)
check('A1b dispatch 块外零裸 selectedProfileName 赋值（防回退）',
      'selectedProfileName = profileId' not in stripped,
      '函数体 dispatch main 块外仍有裸赋值')

# A2: ZL2VersionsViewController.reloadVersions 主线程钳制
mrv = re.search(r'- \(void\)reloadVersions \{.*?\n\}', zvv, re.S)
check('A2 ZL2Versions reloadVersions 主线程防御钳制',
      bool(mrv)
      and 'isMainThread' in mrv.group(0)
      and 'dispatch_async(dispatch_get_main_queue' in mrv.group(0)
      and '__weak typeof(self) weakSelf' in mrv.group(0),
      '钳制三件套缺失')

# A3: getenv 兜底
check('A3 FabricUtils POJAV_GAME_DIR 兜底（NSHomeDirectory）',
      'ame336_gameDir = ame336_env ? [NSString stringWithUTF8String:ame336_env] : NSHomeDirectory()' in fum,
      '兜底缺失')

# ── B 线② neoforge 清单双雷根修 ──────────────────────────────
mneo = re.search(r'if \(\[identifier isEqualToString:@"neoforge"\]\) \{(.*?)\n    \}', gav, re.S)
neo = mneo.group(1) if mneo else ''
check('B1 neoforge 过滤改 ame185 共享匹配器',
      'ame185_loaderVersionMatchesGameVersion(version, self.gameVersion)' in neo,
      '匹配器调用缺失')
check('B2 BMCLAPI neoforge/meta details 真镜像端点',
      'https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/neoforge' in neo,
      '真镜像端点缺失')
check('B3 双形态解析（versions[] + files[] DIRECTORY）',
      'json[@"versions"]' in neo and 'json[@"files"]' in neo
      and '"DIRECTORY"' in neo,
      '双形态解析缺失')
check('B4 旧 hasPrefix:"<mc>-" 过滤退役',
      'hasPrefix:prefix' not in neo and 'NSString *prefix' not in neo,
      '旧过滤残留')
check('B5 skipPatterns 非 client 变体剔除',
      'skipPatterns' in neo and 'userdev' in neo and 'sources' in neo,
      '剔除表缺失')
check('B6 utils.h + LauncherPreferences.h import',
      '#import "utils.h"' in gav and '#import "LauncherPreferences.h"' in gav,
      'import 缺失')
check('B7 download_source 策略排序（bmclFirst）',
      "getPrefObject(@\"general.download_source\")" in neo
      and 'bmclFirst' in neo,
      '策略排序缺失')

# ── C 线③ Forge/NeoForge 退役 + 页内直装 ─────────────────────
gav_code = _strip_strings_comments(gav)
check('C1 Addons 页零 ForgeInstallViewController 代码引用（注释字样合法）',
      'ForgeInstallViewController' not in gav_code,
      '代码仍有引用（前向声明/push）')
check('C2 ame337_installForgeLikeVendor 执行器存在',
      '- (void)ame337_installForgeLikeVendor:(NSString *)vendor' in gav
      and 'ame337_installForgeLikeVendor:amVendor' in gav,
      '执行器声明或调用缺失')
mexe = re.search(r'ame337_installForgeLikeVendor.*?(?=\n#pragma mark - OptiFine)', gav, re.S)
exe = mexe.group(0) if mexe else ''
check('C3 installer jar 三形态路径',
      'net/neoforged/forge/%@/forge-%@-installer.jar' in exe
      and 'net/neoforged/neoforge/%@/neoforge-%@-installer.jar' in exe
      and 'net/minecraftforge/forge/%@/forge-%@-installer.jar' in exe,
      '三形态路径缺失')
check('C4 ForgeDirectInstaller import + 直装调用',
      '#import "installer/ForgeDirectInstaller.h"' in gav
      and '[ForgeDirectInstaller installForgeFromInstaller:am337Dest' in exe,
      'import 或调用缺失')
check('C5 M3 确认 + 忙态复用 + completion 主线程',
      'Task337 inline install start' in gav
      and 'ame336Installing = YES' in gav
      and re.search(r'ame337_installForgeLikeVendor.*?safeCompletion.*?dispatch_get_main_queue', exe, re.S) is not None,
      'M3/忙态/主线程回调缺失')
check('C6a Preview 桩 installForgeFromInstaller 补齐',
      '+ (BOOL)installForgeFromInstaller:(NSString *)installerPath' in stub
      and stub.count('+ (BOOL)installForgeFromInstaller') >= 1,
      '桩缺失（Preview 链接面 Undefined 预判）')
check('C6b Preview 两旧表单桩退役（失去消费者）',
      '@interface ForgeInstallViewController' not in stub
      and '@interface FabricInstallViewController' not in stub,
      '死桩残留')
dl = read('Natives/DownloadViewController.m') if os.path.exists(os.path.join(ROOT, 'Natives/DownloadViewController.m')) else ''
check('C7 旧下载页链路保留（退役纪律）',
      'ForgeInstallViewController' in dl,
      'DownloadViewController 引用缺失（误伤旧链路）')
check('C8 versionId 含 MC 版本段',
      '"%@-%@-%@", gameVersion' in exe
      and 'compoundPrefix' in exe,
      'versionId 构造缺失')

# ── D 结构完整性 ────────────────────────────────────────────
for rel in ('Natives/ZL2GameAddonsViewController.m',
            'Natives/installer/FabricUtils.m',
            'Natives/ZL2VersionsViewController.m',
            'Natives/Preview/ZL2PagesStub.m'):
    cur = _deltas(_strip_strings_comments(read(rel)))
    try:
        head_src = subprocess.run(['git', 'show', f'HEAD:{rel}'],
                                  cwd=ROOT, capture_output=True, text=True).stdout
        head = _deltas(_strip_strings_comments(head_src))
        check(f'D1 括号平衡(HEAD对照) {os.path.basename(rel)}', cur == head,
              f'cur={cur} head={head}')
    except Exception as e:
        check(f'D1 括号平衡(HEAD对照) {os.path.basename(rel)}', False, str(e))
smoke = read('scripts/ui_fluent_smoke.sh')
check('D2 Preview TU 面（Addons 页 + FabricUtils 保持）',
      'ZL2GameAddonsViewController' in smoke and 'installer/FabricUtils' in smoke,
      'TU 清单漂移')

# ame336 语义演进回归（E4 前向声明断言→退役断言：gav 内 FabricInstall 零引用）
check('D3 Task336 E4 语义演进：FabricInstall 代码零引用断言保持',
      'FabricInstallViewController' not in gav_code,
      'Task336 退役断言回退')

print()
if failures:
    print(f'FAIL {len(failures)}/{passed + len(failures)}: ' + ', '.join(failures))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
