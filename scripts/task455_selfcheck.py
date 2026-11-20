#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task455 selfcheck：三症状落码验收门（启动卡死感 / 侧边栏折叠态 / 版本数据）

三案根因（装机 latestlog 2ed20a6 + IMG_0720 + 双轮日志交叉实证）：
  ① 启动卡死感 = Task346 杠杆逐源放行启动期令牌突发（插件装载 + Ame398 外观
    同步重放 + Ame429 壁纸 overlay）→ 500ms 内整壳重建 ×3+1、两次 0.3s
    CrossDissolve 重叠（Unbalanced appearance transitions）；根修 = 首帧落地
    前抑制（记脏），首壳 viewDidAppear 恰好补建一次（整壳重建 4→2）。
  ② 侧边栏标题/条目「有时不显示不占满」= 窗格恒以持久化折叠态（64pt 图标栏）
    起步（title 宽 0 ∈ Task394 设计内折叠行为；IMG_0720 实锤）+ 头行 trailing
    弱不等式无宽度驱动源（引擎可把标题抗压 250 压到 0 宽）；根修 = 启动态
    改会话级恒展开（设备侧写入面退役 + 旧键清账 + 头行等式 pin 999）。
  ③ 版本数据「重新要下载」观感 = ZL2VersionIndex 远程清单纯内存态每启动必走
    网络（927 条 piston-meta 拉取）；根修 = 磁盘缓存 TTL 24h + 网络失败过期
    快照兜底。附带真雷：Task255 消费端裸键查表（auto_control_update_check 缺
    control. 前缀）= 开关 ON 功能零生效（Task230 同款家族第二例）。

本门三道防线：
  R 修复形态执法（七项：抑制/声明/flush/头行 pin/键迁移/裸键/缓存）
  X 家族全仓静态扫描（偏好键点分前缀零容忍 + AppLanguageChanged 广播面清单
    锁定 + 旧折叠键写入面清零——防新启动面绕过启动合并 / 新裸键雷 / 持久化回潮）
  S 扫描器敏感性自证（--selftest 变体必红）
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NAT = os.path.join(ROOT, "Natives")

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def rd(p):
    return open(os.path.join(NAT, p), encoding="utf-8").read()

# ============ R 修复形态（三案判例本体） ============
theme = rd("ZL2Theme.m")
theme_h = rd("ZL2Theme.h")
shell = rd("ZL2ShellViewController.m")
preview = rd("Preview/AmeFluentPreviewMain.m")
repo = rd("ZL2ControlRepoViewController.m")
vindex = rd("ZL2VersionIndex.m")

# —— ① 启动期令牌突发合并 ——
check("R1a 启动抑制状态与首帧守卫在场（ame455_startupLanded + viewIfLoaded）",
      "static BOOL ame455_startupLanded" in theme
      and "static BOOL ame455_startupRebuildDirty" in theme
      and "!ame455_root || !ame455_root.viewIfLoaded" in theme)
check("R1b 抑制分支在 ame346_requestRootRebuild 最前（记脏后 return，不落 Task380 冷却）",
      re.search(r"static void ame346_requestRootRebuild\(void\) \{\s*\n\s*// ★ Task455", theme) is not None
      and "ame455_startupRebuildDirty = YES;" in theme)
check("R2 首帧锚点消费公开声明 + 方法体在 @implementation 内",
      "+ (BOOL)ame455_consumeStartupRebuild;" in theme_h
      and theme.count("+ (BOOL)ame455_consumeStartupRebuild {") == 1)
impl_pos = theme.find("@implementation ZL2Theme")
check("R3 消费方法体位置在 @implementation 内（ObjC 方法不得落文件域）",
      impl_pos >= 0 and theme.find("+ (BOOL)ame455_consumeStartupRebuild {") > impl_pos)
check("R4 壳首帧落地 flush 在场（viewDidAppear 进程级一次块内 consume → 异步补建）",
      "if ([ZL2Theme ame455_consumeStartupRebuild]) {" in shell
      and shell.find("[ZL2Theme ame455_consumeStartupRebuild]") < shell.find("[ZL2FestivalEffects attachToWindow:"))

# —— ② 侧边栏会话级 + 头行宽度 pin ——
check("R5a 头行尾随等式 pin（999，等式替代弱不等式；旧 LessThanOrEqual 头行面清零）",
      shell.count("ame455_headerTrailing") >= 3
      and "self.ame455_headerTrailing.priority = 999;" in shell
      and "constraintEqualToAnchor:self.paneWrap.trailingAnchor constant:-12.0]" in shell
      and "constraintLessThanOrEqualToAnchor:self.paneWrap.trailingAnchor constant:-12.0" not in shell)
check("R5b 回读键整链退役（★Task460 重锚：非折叠钦定——折叠二态/回读/清账全链退役，壳零键面零状态）",
      'boolForKey:@"ame376.paneCollapsed.ui"' not in shell
      and 'removeObjectForKey:@"ame376.paneCollapsed"' not in shell
      and "BOOL ame376_paneCollapsed;" not in shell
      and "self.paneToggleButton" not in shell)
check("R5c 设备侧写入面退役（开关块零 setBool 持久化）",
      "setBool:weakSelf.ame376_paneCollapsed" not in shell)
check("R5d CI 预览驱动链退役（★Task460 重锚：-zl2pane 真壳驱动退役 = 真壳恒 280 展开渲染；镜像轨 -zl2pane 契约保留）",
      'forKey:@"ame376.paneCollapsed.ui"' not in preview
      and "ame417_expanded" not in preview
      and "-zl2pane" in preview)

# —— ③ 版本清单磁盘缓存 + 裸键根修 ——
check("R6a 缓存四件套（TTL/路径/水合/写回）在场",
      "ame455_manifestCacheTTL" in vindex
      and "ame_version_manifest_cache.json" in vindex
      and "ame455_hydrateFromManifestCacheAllowStale:" in vindex
      and "ame455_writeManifestCacheWithVersions:" in vindex)
check("R6b 快速路径与兕底双挂点（新鲜直读 + 网络全败快照兜底）",
      "if ([self ame455_hydrateFromManifestCacheAllowStale:NO]) return;" in vindex
      and "if ([self ame455_hydrateFromManifestCacheAllowStale:YES]) return;" in vindex)
check("R6c Task255 消费端键补全点分前缀（control. 前缀查表）",
      'getPrefBool(@"control.auto_control_update_check")' in repo)

# ============ X 家族全仓静态扫描 ============
# X1 偏好键字面量点分前缀零容忍（裸键 = Getter/Setter "could not find" 家族，
#    Task230 auto_keyboard_sdl / Task455 auto_control_update_check 两例定谳：
#    注册表 = 点分节字典路径，任何裸键查表必然回落默认值 = 静默功能失效）
pref_pat = re.compile(r'\b(?:getPref(?:Bool|Object|Float|Int)|setPref(?:Bool|Object|Float|Int))\(\s*@"([^"]+)"')
undotted = []
n_m = 0
for dirpath, dirnames, filenames in os.walk(NAT):
    if os.path.relpath(dirpath, NAT).startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith((".m", ".h")):
            continue
        n_m += 1
        try:
            text = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        except Exception:
            continue
        for m in pref_pat.finditer(text):
            if "." not in m.group(1):
                undotted.append("%s:%s" % (fn, m.group(1)))
check("X1 偏好键字面量无点分前缀 = 0（裸键查表家族零容忍，扫描 %d 个 ObjC 文件）" % n_m,
      len(undotted) == 0, detail=",".join(undotted[:8]))

# X2 AppLanguageChanged 直接广播面清单锁定（启动面唯一合法广播 = Task346 杠杆
#    ZL2Theme.m ×1；设置页动作 ZL2SettingPages.m ×1 + 数据迁移 DataTransferService.m
#    ×2 均为交互面；新启动面直接广播 = 绕过 Task455 启动合并，清单变即红）
allowed = {"ZL2Theme.m": 1, "ZL2SettingPages.m": 1, "DataTransferService.m": 2}
observed = {}
for dirpath, dirnames, filenames in os.walk(NAT):
    if os.path.relpath(dirpath, NAT).startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith(".m"):
            continue
        text = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        cnt = text.count('postNotificationName:@"AppLanguageChanged"')
        if cnt:
            observed[fn] = observed.get(fn, 0) + cnt
check("X2 AppLanguageChanged 广播面清单锁定（ZL2Theme×1/SettingPages×1/DataTransfer×2）",
      observed == allowed, detail=str(observed))

# X3 旧折叠键写入面清零 + 清账点退役（★Task460 重锚：非折叠钦定——读/写/
#    清账全链退役，键面全仓零容忍防回潮）
old_key_writers = 0
old_key_remove = 0
for dirpath, dirnames, filenames in os.walk(NAT):
    if os.path.relpath(dirpath, NAT).startswith("external"):
        continue
    for fn in filenames:
        if not fn.endswith((".m", ".h")):
            continue
        text = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        for m in re.finditer(r'set(?:Bool|Object|Float|Int):\s*[^;]*?forKey:@"ame376\.paneCollapsed"', text):
            old_key_writers += 1
        old_key_remove += text.count('removeObjectForKey:@"ame376.paneCollapsed"')
check("X3 旧折叠键写入面 = 0 且清账/读面全退役（★Task460 重锚：键面全链零容忍）",
      old_key_writers == 0 and old_key_remove == 0,
      detail="writers=%d remove=%d" % (old_key_writers, old_key_remove))

# ============ S 敏感性自证（--selftest） ============
def run_selftest():
    ok = True
    # S1 裸键样本必须被 X1 判红
    bad = 'getPrefBool(@"auto_control_update_check")'
    ok &= pref_pat.search(bad) is not None and "." not in pref_pat.search(bad).group(1)
    # S2 点分键样本必须被 X1 放行
    good = 'getPrefBool(@"control.auto_control_update_check")'
    m = pref_pat.search(good)
    ok &= m is not None and "." in m.group(1)
    # S3 数字前缀键（ame217 家族）必须被点分判据放行
    m2 = pref_pat.search('setPrefObject(@"ame217.autoRendererBlacklist", v)')
    ok &= m2 is not None and "." in m2.group(1)
    # S4 旧键写入样本必须被 X3 判红（ObjC 消息语法：冒号后直接实参）
    bad3 = '[NSUserDefaults.standardUserDefaults setBool:weakSelf.ame376_paneCollapsed\n                                                  forKey:@"ame376.paneCollapsed"];'
    ok &= re.search(r'set(?:Bool|Object|Float|Int):\s*[^;]*?forKey:@"ame376\.paneCollapsed"', bad3) is not None
    # S4b .ui 后缀写入样本必须被 X3 放行（引号锚定：Collapsed 后必须紧跟闭引号）
    ok &= re.search(r'set(?:Bool|Object|Float|Int):\s*[^;]*?forKey:@"ame376\.paneCollapsed"',
                    '[NSUserDefaults setBool:(!e) forKey:@"ame376.paneCollapsed.ui"]') is None
    # S5 广播面样本变体必须判红（清单 +1）
    ok &= 'postNotificationName:@"AppLanguageChanged"' in '[[NSNotificationCenter defaultCenter] postNotificationName:@"AppLanguageChanged" object:nil];'
    print("PASS S1-S5 扫描器敏感性自证" if ok else "FAIL S 扫描器敏感性自证")
    return ok

if "--selftest" in sys.argv:
    sys.exit(0 if run_selftest() else 1)

check("S 判例注释留档（三案根因 + 证据锚在场）",
      "★ Task455" in theme and "Task455" in shell and "Task455" in vindex and "Task455" in repo)

if fails:
    print("task455_selfcheck RED (%d): %s" % (len(fails), "; ".join(fails)))
    return_code = 1
else:
    print("task455_selfcheck ALL PASS")
    return_code = 0
sys.exit(return_code)
